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

payload='{"customer_id":"acme-2","issued_at":"2025-12-30","notes":"integration"}'
payload_file="$TMP_DIR/payload.json"
printf '%s' "$payload" >"$payload_file"

sig_b64="$(openssl dgst -sha256 -sign "$key_path" "$payload_file" | openssl base64 -A)"
sig_b64url="$(printf '%s' "$sig_b64" | tr '+/' '-_' | tr -d '=')"
payload_b64="$(openssl base64 -A -in "$payload_file")"
payload_b64url="$(printf '%s' "$payload_b64" | tr '+/' '-_' | tr -d '=')"

license_key="FB1-${payload_b64url}-${sig_b64url}"

cmd_activate "$license_key" >/dev/null 2>&1

assert_true "[[ -f \"$FB_HOME/license.key\" ]]" "license.key created"
stored="$(cat "$FB_HOME/license.key")"
assert_contains "$stored" "FB1-"

echo "activate.sh OK"
