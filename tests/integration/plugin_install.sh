#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_helpers.sh"

integration_init
source_libs

require_license() { return 0; }
cmd_version() { echo "0.1.0"; }

manifest_path="$TMP_DIR/manifest.json"
os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) arch="amd64" ;;
  arm64|aarch64) arch="arm64" ;;
esac
platform="${os}-${arch}"
tarball_name="fb-plugin-ttl-0.1.0-${platform}.tar.gz"
tarball_path="$TMP_DIR/$tarball_name"
sha_path="$TMP_DIR/$tarball_name.sha256"

cat >"$manifest_path" <<JSON
{
  "latest": "0.1.0",
  "min_core_version": "0.0.1",
  "download_base_url": "https://downloads.example.com",
  "platforms": {
    "${platform}": {
      "tarball": "plugins/ttl/releases/0.1.0/${tarball_name}",
      "sha256":  "plugins/ttl/releases/0.1.0/${tarball_name}.sha256"
    }
  }
}
JSON

pkg_dir="$TMP_DIR/pkg"
mkdir -p "$pkg_dir"
cat >"$pkg_dir/fb-plugin-ttl" <<'SH'
#!/usr/bin/env bash
echo "ttl"
SH
chmod +x "$pkg_dir/fb-plugin-ttl"
tar -czf "$tarball_path" -C "$pkg_dir" fb-plugin-ttl
if command -v shasum >/dev/null 2>&1; then
  expected_hash="$(shasum -a 256 "$tarball_path" | awk '{print $1}')"
else
  expected_hash="$(sha256sum "$tarball_path" | awk '{print $1}')"
fi
printf '%s  %s\n' "$expected_hash" "$(basename "$tarball_path")" >"$sha_path"

cat >"$STUB_BIN/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
dest=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      dest="$2"
      shift 2
      ;;
    http*://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done
if [[ -z "$dest" || -z "$url" ]]; then
  exit 1
fi
case "$url" in
  */manifest.json)
    cp "$TEST_MANIFEST_PATH" "$dest"
    ;;
  *.tar.gz)
    cp "$TEST_TARBALL_PATH" "$dest"
    ;;
  *.sha256)
    cp "$TEST_SHA_PATH" "$dest"
    ;;
  *)
    exit 1
    ;;
esac
SH
chmod +x "$STUB_BIN/curl"

export TEST_MANIFEST_PATH="$manifest_path"
export TEST_TARBALL_PATH="$tarball_path"
export TEST_SHA_PATH="$sha_path"
export FB_DOWNLOAD_BASE_URL="https://downloads.example.com"

output="$(plugin_install ttl)"
OUTPUT_DUMP="$output"

assert_contains "$output" "Installed plugin ttl (0.1.0)"
assert_true "[[ -x \"$FB_HOME/plugins/fb-plugin-ttl\" ]]" "plugin binary installed"
assert_true "[[ \"$(cat "$FB_HOME/plugins/ttl.version")\" == \"0.1.0\" ]]" "version file written"

echo "plugin_install.sh OK"
