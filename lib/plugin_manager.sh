#!/usr/bin/env bash
set -euo pipefail

plugin_help() {
  cat <<'EOF'
Usage: fb plugin <command>

Commands:
  install <name>      Install or update a plugin (Early Access)
  update <name>       Update a plugin (Early Access)
  update --all        Update all installed plugins (Early Access)
  list                List installed plugins
  remove <name>       Remove a plugin
EOF
}

plugin_install_help() {
  cat <<'EOF'
Usage: fb plugin install <name>
EOF
}

plugin_update_help() {
  cat <<'EOF'
Usage: fb plugin update <name>|--all
EOF
}

plugin_remove_help() {
  cat <<'EOF'
Usage: fb plugin remove <name>
EOF
}

plugin_platform() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$os" in
    darwin|linux) ;;
    *) die "Unsupported OS: $os" ;;
  esac
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) die "Unsupported arch: $arch" ;;
  esac
  echo "$os-$arch"
}

plugin_manifest_value() {
  local file="$1"
  local key="$2"
  awk -F'"' -v k="$key" '$2==k {print $4; exit}' "$file"
}

plugin_manifest_platform_value() {
  local file="$1"
  local platform="$2"
  local key="$3"
  awk -v platform="$platform" -v key="$key" '
    $0 ~ "\""platform"\"" {in_platform=1}
    in_platform && $0 ~ "\""key"\"" {
      gsub(/.*"'"$key"'":[[:space:]]*"/,"")
      gsub(/".*/,"")
      print
      exit
    }
    in_platform && $0 ~ /^[[:space:]]*}/ {in_platform=0}
  ' "$file"
}

sha256_hash() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return 0
  fi
  die "Missing shasum or sha256sum."
}

plugin_install() {
  local name="$1"
  if [[ -z "$name" ]]; then
    plugin_install_help
    return 1
  fi

  require_license
  require_cmd curl
  require_cmd tar

  local base_url
  base_url="$(downloads_base_url)"
  local manifest_url="$base_url/plugins/$name/manifest.json"
  local manifest tmp_dir
  tmp_dir="$(mktemp -d)"
  manifest="$tmp_dir/manifest.json"

  if ! curl -fsSL "$manifest_url" -o "$manifest"; then
    rm -rf "$tmp_dir"
    die "Failed to download plugin manifest: $manifest_url"
  fi

  local latest min_core manifest_base
  latest="$(plugin_manifest_value "$manifest" "latest")"
  min_core="$(plugin_manifest_value "$manifest" "min_core_version")"
  manifest_base="$(plugin_manifest_value "$manifest" "download_base_url")"
  manifest_base="${manifest_base:-$base_url}"

  if [[ -z "$latest" ]]; then
    rm -rf "$tmp_dir"
    die "Plugin manifest missing latest version."
  fi
  if [[ -n "$min_core" ]]; then
    local current
    current="$(cmd_version)"
    if is_semver "$current" && is_semver "$min_core"; then
      if ! version_ge "$current" "$min_core"; then
        rm -rf "$tmp_dir"
        die "Plugin requires FounderBooster $min_core+. Run: fb self update"
      fi
    else
      log_warn "Skipping min_core_version check (non-semver core version: $current)."
    fi
  fi

  local platform
  platform="$(plugin_platform)"
  local tarball_path sha_path
  tarball_path="$(plugin_manifest_platform_value "$manifest" "$platform" "tarball")"
  sha_path="$(plugin_manifest_platform_value "$manifest" "$platform" "sha256")"
  if [[ -z "$tarball_path" || -z "$sha_path" ]]; then
    rm -rf "$tmp_dir"
    die "Plugin manifest missing platform entry for $platform"
  fi

  local tarball_url="$manifest_base/$tarball_path"
  local sha_url="$manifest_base/$sha_path"
  local tarball_file="$tmp_dir/$(basename "$tarball_path")"
  local sha_file="$tmp_dir/$(basename "$sha_path")"

  if ! curl -fsSL "$tarball_url" -o "$tarball_file"; then
    rm -rf "$tmp_dir"
    die "Failed to download plugin tarball: $tarball_url"
  fi
  if ! curl -fsSL "$sha_url" -o "$sha_file"; then
    rm -rf "$tmp_dir"
    die "Failed to download plugin checksum: $sha_url"
  fi

  local expected actual
  expected="$(awk '{print $1; exit}' "$sha_file")"
  actual="$(sha256_hash "$tarball_file")"
  if [[ -z "$expected" || "$expected" != "$actual" ]]; then
    rm -rf "$tmp_dir"
    die "Checksum verification failed for $tarball_file"
  fi

  local extract_dir="$tmp_dir/extract"
  mkdir -p "$extract_dir"
  tar -xzf "$tarball_file" -C "$extract_dir"

  local plugin_bin="fb-plugin-$name"
  local found
  found="$(find "$extract_dir" -type f -name "$plugin_bin" -maxdepth 4 | head -n1)"
  if [[ -z "$found" ]]; then
    rm -rf "$tmp_dir"
    die "Plugin binary not found in tarball: $plugin_bin"
  fi

  local dest_dir="$FB_HOME/plugins"
  ensure_dir "$dest_dir"
  local dest="$dest_dir/$plugin_bin"
  cp "$found" "$dest"
  chmod +x "$dest"
  printf '%s\n' "$latest" >"$dest_dir/${name}.version"

  rm -rf "$tmp_dir"
  log_info "Installed plugin $name ($latest)"
}

plugin_remove() {
  local name="$1"
  if [[ -z "$name" ]]; then
    plugin_remove_help
    return 1
  fi
  local dest_dir="$FB_HOME/plugins"
  local plugin_bin="$dest_dir/fb-plugin-$name"
  if [[ -f "$plugin_bin" ]]; then
    rm -f "$plugin_bin"
    rm -f "$dest_dir/${name}.version"
    log_info "Removed plugin $name"
    return 0
  fi
  log_warn "Plugin not found: $name"
}

plugin_list() {
  local dir="$FB_HOME/plugins"
  if [[ ! -d "$dir" ]]; then
    log_warn "No plugins installed."
    return 0
  fi
  local entries
  entries="$(find "$dir" -maxdepth 1 -type f -name 'fb-plugin-*' 2>/dev/null | sort || true)"
  if [[ -z "$entries" ]]; then
    log_warn "No plugins installed."
    return 0
  fi
  while IFS= read -r plugin_path; do
    [[ -z "$plugin_path" ]] && continue
    local base name version_file version
    base="$(basename "$plugin_path")"
    name="${base#fb-plugin-}"
    version_file="$dir/${name}.version"
    version="unknown"
    if [[ -f "$version_file" ]]; then
      version="$(cat "$version_file")"
    fi
    echo "$name - version=$version"
  done <<<"$entries"
}

plugin_update_all() {
  require_license
  local dir="$FB_HOME/plugins"
  if [[ ! -d "$dir" ]]; then
    log_warn "No plugins installed."
    return 0
  fi
  local entries
  entries="$(find "$dir" -maxdepth 1 -type f -name 'fb-plugin-*' 2>/dev/null | sort || true)"
  if [[ -z "$entries" ]]; then
    log_warn "No plugins installed."
    return 0
  fi
  while IFS= read -r plugin_path; do
    [[ -z "$plugin_path" ]] && continue
    local base name
    base="$(basename "$plugin_path")"
    name="${base#fb-plugin-}"
    plugin_install "$name"
  done <<<"$entries"
}

cmd_plugin() {
  local sub="${1:-}"
  case "$sub" in
    install)
      shift
      plugin_install "${1:-}"
      ;;
    update)
      shift
      if [[ "${1:-}" == "--all" ]]; then
        plugin_update_all
      else
        plugin_install "${1:-}"
      fi
      ;;
    list)
      shift
      plugin_list
      ;;
    remove)
      shift
      plugin_remove "${1:-}"
      ;;
    help|-h|--help|"")
      plugin_help
      ;;
    *)
      die "Unknown plugin command: $sub"
      ;;
  esac
}
