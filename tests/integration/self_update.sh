#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_helpers.sh"

integration_init
source_libs

key_path="$TMP_DIR/private.pem"
pub_path="$TMP_DIR/public.pem"
openssl genrsa -out "$key_path" 2048 >/dev/null 2>&1
openssl rsa -in "$key_path" -pubout -out "$pub_path" >/dev/null 2>&1

export FOUNDERBOOSTER_LICENSE_PUBKEY_PATH="$pub_path"

payload='{"customer_id":"acme-1","issued_at":"2025-12-31","notes":"test"}'
payload_file="$TMP_DIR/payload.json"
printf '%s' "$payload" >"$payload_file"

sig_b64="$(openssl dgst -sha256 -sign "$key_path" "$payload_file" | openssl base64 -A)"
sig_b64url="$(printf '%s' "$sig_b64" | tr '+/' '-_' | tr -d '=')"
payload_b64="$(openssl base64 -A -in "$payload_file")"
payload_b64url="$(printf '%s' "$payload_b64" | tr '+/' '-_' | tr -d '=')"

license_key="FB1-${payload_b64url}-${sig_b64url}"
export FOUNDERBOOSTER_LICENSE_KEY="$license_key"

mkdir -p "$FB_HOME"
echo "0.0.1" >"$FB_HOME/VERSION"

TEST_MANIFEST_PATH="$TMP_DIR/manifest.json"
TEST_INSTALLER_PATH="$TMP_DIR/install.sh"
export TEST_MANIFEST_PATH
export TEST_INSTALLER_PATH

cat >"$TEST_MANIFEST_PATH" <<'JSON'
{
  "latest": "0.0.2",
  "download_base_url": "https://downloads.example.com",
  "platforms": {}
}
JSON

cat >"$TEST_INSTALLER_PATH" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ -z "${FB_HOME:-}" ]]; then
  echo "FB_HOME not set" >&2
  exit 1
fi
echo "0.0.2" >"$FB_HOME/VERSION"
echo "installed"
SH
chmod +x "$TEST_INSTALLER_PATH"

stub_curl_self_update

plugin_update_flag="$TMP_DIR/plugins-updated"
plugin_update_all() { printf 'updated' >"$plugin_update_flag"; }

output="$(cmd_self_update --with-plugins)"
OUTPUT_DUMP="$output"

assert_true "[[ \"$(cat "$FB_HOME/VERSION")\" == \"0.0.2\" ]]" "version updated"
assert_true "[[ -f \"$plugin_update_flag\" ]]" "plugins updated"

echo "self_update.sh OK"
