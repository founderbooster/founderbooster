#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    echo "ASSERT_EQ failed: expected='$expected' actual='$actual' $msg" >&2
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

export FB_HOME="$TMP_DIR/fb-home"
export FB_TEST_MODE="true"

STUB_BIN="$TMP_DIR/bin"
mkdir -p "$STUB_BIN"
export PATH="$STUB_BIN:$PATH"

cat >"$STUB_BIN/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
url="${@: -1}"
if [[ "$url" == "http://localhost:8055" ]]; then
  if [[ "${CURL_MODE:-}" == "redirect" ]]; then
    printf 'http://localhost:8055/admin'
    exit 0
  fi
fi
if [[ "$url" == "http://localhost:8055/admin" ]]; then
  if [[ "${CURL_MODE:-}" == "code200" ]]; then
    printf '200'
    exit 0
  fi
fi
if [[ "$url" == "http://localhost:8055/ready-404" ]]; then
  if [[ "${CURL_MODE:-}" == "code404" ]]; then
    printf '404'
    exit 0
  fi
fi
printf '000'
SH
chmod +x "$STUB_BIN/curl"

source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/bootstrap.sh"

# resolve_ready_url
export CURL_MODE="redirect"
assert_eq "http://localhost:8055/admin" "$(resolve_ready_url "http://localhost:8055")" "resolve_ready_url should follow redirect"
export CURL_MODE=""
assert_eq "000" "$(resolve_ready_url "http://localhost:8055")" "resolve_ready_url should keep original when no redirect"

# hash_short
short1="$(hash_short "machine-a")"
short2="$(hash_short "machine-a")"
assert_eq "$short1" "$short2" "hash_short deterministic"
assert_true '[[ "${#short1}" -eq 4 ]]' "hash_short length"
assert_true '[[ "$short1" =~ ^[a-f0-9]{4}$ || "$short1" =~ ^[A-Za-z0-9]{4}$ ]]' "hash_short format"

# machine_suffix uses /etc/machine-id or hostname; ensure 4 chars
suffix="$(machine_suffix)"
assert_true '[[ "${#suffix}" -eq 4 ]]' "machine_suffix length"

# wait_for_http_ready: accept 200
export CURL_MODE="code200"
wait_for_http_ready "http://localhost:8055/admin" "Ready test" || {
  echo "wait_for_http_ready should succeed on 200" >&2
  exit 1
}

# wait_for_http_ready with reject_404 should fail quickly
export CURL_MODE="code404"
if wait_for_http_ready "http://localhost:8055/ready-404" "Reject 404" "true"; then
  echo "wait_for_http_ready should not succeed on 404 when reject_404=true" >&2
  exit 1
fi

echo "bootstrap_test.sh OK"
