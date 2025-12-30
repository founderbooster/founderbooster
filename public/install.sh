#!/usr/bin/env bash
set -euo pipefail

DEFAULT_DOWNLOAD_BASE_URL="https://downloads.founderbooster.com"
DOWNLOAD_BASE_URL="${FB_DOWNLOAD_BASE_URL:-${DOWNLOAD_BASE_URL:-$DEFAULT_DOWNLOAD_BASE_URL}}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
NO_VERIFY="${NO_VERIFY:-}"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$OS" in
  darwin)
    case "$ARCH" in
      arm64) PLATFORM="darwin-arm64" ;;
      x86_64) PLATFORM="darwin-amd64" ;;
      *)
        echo "ERROR: Unsupported arch $ARCH for macOS." >&2
        exit 1
        ;;
    esac
    ;;
  linux)
    case "$ARCH" in
      x86_64|amd64) PLATFORM="linux-amd64" ;;
      aarch64|arm64) PLATFORM="linux-arm64" ;;
      *)
        echo "ERROR: Unsupported arch $ARCH for Linux." >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "ERROR: Unsupported OS $OS (expected darwin or linux)." >&2
    exit 1
    ;;
esac

if [[ -z "${INSTALL_DIR:-}" ]]; then
  INSTALL_DIR="/usr/local/bin"
fi

if [[ ! -w "$INSTALL_DIR" ]]; then
  if [[ -z "${INSTALL_DIR:-}" || "$INSTALL_DIR" == "/usr/local/bin" ]]; then
    if [[ -d "/opt/homebrew/bin" && -w "/opt/homebrew/bin" ]]; then
      INSTALL_DIR="/opt/homebrew/bin"
    elif [[ "$OS" == "linux" ]]; then
      fallback_dir="$HOME/.local/bin"
      mkdir -p "$fallback_dir" 2>/dev/null || true
      if [[ -w "$fallback_dir" ]]; then
        INSTALL_DIR="$fallback_dir"
      fi
    fi
  fi
fi

if [[ ! -w "$INSTALL_DIR" ]]; then
  echo "ERROR: Cannot write to $INSTALL_DIR." >&2
  echo "Re-run with sudo or choose another path:" >&2
  echo "  curl -fsSL $DOWNLOAD_BASE_URL/install.sh | INSTALL_DIR=/some/path bash" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

download_file() {
  local url="$1"
  local out="$2"
  if ! curl -fsSL "$url" -o "$out"; then
    echo "ERROR: Failed to download $url" >&2
    exit 1
  fi
}

manifest="$tmp_dir/manifest.json"
download_file "$DOWNLOAD_BASE_URL/manifest.json" "$manifest"

manifest_base="$(awk -F'"' '/"download_base_url"/{print $4}' "$manifest")"
if [[ -n "$manifest_base" ]]; then
  DOWNLOAD_BASE_URL="$manifest_base"
fi

latest="$(awk -F'"' '/"latest"/{print $4}' "$manifest")"
if [[ -z "$latest" ]]; then
  echo "ERROR: Could not determine latest version." >&2
  exit 1
fi

tarball_path="$(awk -v platform="$PLATFORM" '
  $0 ~ "\""platform"\"" {inplat=1}
  inplat && $0 ~ "\"tarball\"" {gsub(/[",]/,""); gsub(/^[ \t]+/, "", $2); print $2; exit}
' FS=": " "$manifest")"

sha_path="$(awk -v platform="$PLATFORM" '
  $0 ~ "\""platform"\"" {inplat=1}
  inplat && $0 ~ "\"sha256\"" {gsub(/[",]/,""); gsub(/^[ \t]+/, "", $2); print $2; exit}
' FS=": " "$manifest")"

if [[ -z "$tarball_path" || -z "$sha_path" ]]; then
  echo "ERROR: Manifest does not include $PLATFORM." >&2
  exit 1
fi

tarball_url="$DOWNLOAD_BASE_URL/$tarball_path"
sha_url="$DOWNLOAD_BASE_URL/$sha_path"

tarball="$tmp_dir/founderbooster.tar.gz"
sha_file="$tmp_dir/founderbooster.tar.gz.sha256"

download_file "$tarball_url" "$tarball"
download_file "$sha_url" "$sha_file"

sha256_sum() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return 0
  fi
  echo "ERROR: Missing shasum or sha256sum." >&2
  exit 1
}

if [[ -z "$NO_VERIFY" ]]; then
  expected="$(awk '{print $1}' "$sha_file")"
  actual="$(sha256_sum "$tarball")"
  if [[ "$expected" != "$actual" ]]; then
    echo "ERROR: Checksum verification failed." >&2
    exit 1
  fi
else
  echo "WARN: Skipping checksum verification (NO_VERIFY=1)." >&2
fi

tar -xzf "$tarball" -C "$tmp_dir"
pkg_dir="$(find "$tmp_dir" -maxdepth 1 -type d -name "founderbooster-*-$PLATFORM" | head -1)"
if [[ -z "$pkg_dir" ]]; then
  echo "ERROR: Could not locate extracted package." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
cp "$pkg_dir/fb" "$INSTALL_DIR/fb"
chmod +x "$INSTALL_DIR/fb"

runtime_dir="$HOME/.founderbooster/runtime"
mkdir -p "$runtime_dir/lib" "$runtime_dir/templates"
cp -R "$pkg_dir/lib/." "$runtime_dir/lib/"
cp -R "$pkg_dir/templates/." "$runtime_dir/templates/"

mkdir -p "$HOME/.founderbooster"
cp "$pkg_dir/VERSION" "$HOME/.founderbooster/VERSION"

echo "FounderBooster installed: $latest"
echo "Binary: $INSTALL_DIR/fb"
if [[ "$OS" == "linux" ]]; then
  if ! command -v fb >/dev/null 2>&1; then
    echo "Note: add $INSTALL_DIR to PATH (e.g. ~/.profile or ~/.bashrc):"
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
  fi
fi
if [[ ! -f "$HOME/.founderbooster/license.key" ]]; then
  echo "License: not activated (required for official updates/support)."
  echo "  Run: fb activate <license-key>"
fi
echo
echo "Try a demo repo:"
echo "  Docker/Auto: directus-demo"
echo "  Manual/Port-first: port-first-demo"
echo
echo "Then run:"
echo "  export CLOUDFLARE_API_TOKEN=..."
echo "  fb bootstrap --domain yourdomain.com --env dev"
echo
echo "Uninstall:"
echo "  fb self uninstall"
