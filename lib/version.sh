#!/usr/bin/env bash
set -euo pipefail

cmd_version() {
  local version_file="$FB_HOME/VERSION"
  if [[ -f "$version_file" ]]; then
    cat "$version_file"
    return 0
  fi
  if [[ -f "$FB_ROOT/VERSION" ]]; then
    cat "$FB_ROOT/VERSION"
    return 0
  fi
  echo "dev"
}

cmd_version_pretty() {
  cat <<'EOF'
╔════════════════════════════╗
║ FounderBooster             ║
║ From localhost → live      ║
╚════════════════════════════╝
EOF
  echo "$(cmd_version)"
  echo
  print_early_access_footer
}

cmd_self_update() {
  local base_url="${FB_DOWNLOAD_BASE_URL:-${DOWNLOAD_BASE_URL:-https://downloads.founderbooster.com}}"
  require_license
  local manifest
  manifest="$(mktemp)"
  if ! curl -fsSL "$base_url/manifest.json" -o "$manifest"; then
    die "Failed to download manifest from $base_url"
  fi
  local latest
  latest="$(awk -F'"' '/"latest"/{print $4}' "$manifest")"
  if [[ -z "$latest" ]]; then
    rm -f "$manifest"
    die "Failed to parse latest version from manifest."
  fi
  local installed
  installed="$(cmd_version)"
  if [[ "$installed" == "$latest" ]]; then
    rm -f "$manifest"
    log_info "Already up to date ($installed)."
    return 0
  fi
  rm -f "$manifest"
  log_info "Updating from $installed to $latest..."
  local installer
  installer="$(mktemp)"
  if ! curl -fsSL "$base_url/install.sh" -o "$installer"; then
    rm -f "$installer"
    die "Failed to download installer from $base_url"
  fi
  bash "$installer"
  rm -f "$installer"
}

cmd_self_uninstall() {
  local bin_path=""
  bin_path="$(command -v fb 2>/dev/null || true)"
  if [[ -z "$bin_path" ]]; then
    local install_dir="${INSTALL_DIR:-/usr/local/bin}"
    if [[ ! -w "$install_dir" ]]; then
      if [[ "$install_dir" == "/usr/local/bin" && -d "/opt/homebrew/bin" && -w "/opt/homebrew/bin" ]]; then
        install_dir="/opt/homebrew/bin"
      elif [[ -d "$HOME/.local/bin" ]]; then
        install_dir="$HOME/.local/bin"
      fi
    fi
    bin_path="$install_dir/fb"
  fi
  if [[ -f "$bin_path" ]]; then
    rm -f "$bin_path"
    log_info "Removed $bin_path"
  else
    log_warn "fb binary not found at $bin_path"
  fi
  if [[ -d "$FB_HOME" ]]; then
    rm -rf "$FB_HOME"
    log_info "Removed $FB_HOME"
  fi
  log_info "FounderBooster uninstalled."
}
