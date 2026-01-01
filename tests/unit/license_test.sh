#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "ASSERT_CONTAINS failed: missing '$needle'" >&2
    exit 1
  fi
}

assert_true() {
  local condition="$1"
  local msg="${2:-}"
  if ! eval "$condition"; then
    echo "ASSERT_TRUE failed: $condition $msg" >&2
    exit 1
  fi
}

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/license.sh"

export FB_HOME="$TMP_DIR/fb-home"
mkdir -p "$FB_HOME"

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

assert_true 'is_signed_license_key "'"$license_key"'"' "is_signed_license_key"
assert_true 'verify_signed_license "'"$license_key"'"' "verify_signed_license"

cmd_activate "$license_key" >/dev/null 2>&1
assert_true "[[ -f \"$FB_HOME/license.key\" ]]" "license.key created"
stored="$(cat "$FB_HOME/license.key")"
assert_contains "$stored" "FB1-"

echo "license_test.sh OK"
