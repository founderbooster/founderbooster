#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

assert_true() {
  local condition="$1"
  local msg="${2:-}"
  if ! eval "$condition"; then
    echo "ASSERT_TRUE failed: $condition $msg" >&2
    if [[ -n "${OUTPUT_DUMP:-}" ]]; then
      printf '%s\n' "$OUTPUT_DUMP" >&2
    fi
    exit 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "ASSERT_CONTAINS failed: missing '$needle'" >&2
    if [[ -n "${OUTPUT_DUMP:-}" ]]; then
      printf '%s\n' "$OUTPUT_DUMP" >&2
    fi
    exit 1
  fi
}

cleanup_tmp() {
  if [[ "${KEEP_TMP:-}" == "1" ]]; then
    return 0
  fi
  rm -rf "$TMP_DIR"
}

integration_init() {
  TMP_DIR="$(mktemp -d)"
  trap cleanup_tmp EXIT

  export FB_HOME="$TMP_DIR/fb-home"
  export FOUNDERBOOSTER_HOME="$FB_HOME"
  export FB_TEST_MODE="true"
  export CLOUDFLARE_API_TOKEN="test-token"

  STUB_BIN="$TMP_DIR/bin"
  mkdir -p "$STUB_BIN"
  export PATH="$STUB_BIN:$PATH"

  stub_common_bins
}

stub_common_bins() {
  cat >"$STUB_BIN/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "compose" && "$2" == "config" ]]; then
  if [[ "${3:-}" == "--format" && "${4:-}" == "json" ]]; then
    cat <<'JSON'
{
  "services": {
    "app": {
      "ports": ["8055:8055"]
    }
  }
}
JSON
  else
    cat <<'YAML'
services:
  app:
    ports:
      - "8055:8055"
YAML
  fi
  exit 0
fi
if [[ "$1" == "compose" && "$2" == "up" ]]; then
  echo "[+] up 1/1"
  exit 0
fi
if [[ "$1" == "compose" && "$2" == "down" ]]; then
  echo "No resource found to remove"
  exit 0
fi
if [[ "$1" == "compose" && "$2" == "ls" ]]; then
  echo "[]"
  exit 0
fi
if [[ "$1" == "ps" ]]; then
  exit 0
fi
exit 0
SH
  chmod +x "$STUB_BIN/docker"

  cat >"$STUB_BIN/cloudflared" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$STUB_BIN/cloudflared"

  cat >"$STUB_BIN/lsof" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "$STUB_BIN/lsof"

  cat >"$STUB_BIN/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$STUB_BIN/sleep"

  cat >"$STUB_BIN/ps" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$STUB_BIN/ps"

  cat >"$STUB_BIN/hostname" <<'SH'
#!/usr/bin/env bash
echo "test-host"
SH
  chmod +x "$STUB_BIN/hostname"
}

stub_curl_http_ok() {
  cat >"$STUB_BIN/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
write_out=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[i]}" in
    -w)
      write_out="${args[i+1]}"
      i=$((i+1))
      ;;
  esac
done
if [[ "$write_out" == *"%{redirect_url}"* ]]; then
  printf '%s' ""
  exit 0
fi
if [[ "$write_out" == *"%{http_code}"* ]]; then
  printf '200'
  exit 0
fi
exit 0
SH
  chmod +x "$STUB_BIN/curl"
}

stub_curl_self_update() {
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
if [[ "$url" == *"/manifest.json" ]]; then
  cp "$TEST_MANIFEST_PATH" "$dest"
  exit 0
fi
if [[ "$url" == *"/install.sh" ]]; then
  cp "$TEST_INSTALLER_PATH" "$dest"
  exit 0
fi
exit 1
SH
  chmod +x "$STUB_BIN/curl"
}

source_libs() {
  export FB_ROOT="$ROOT_DIR"
  # shellcheck source=lib/common.sh
  source "$ROOT_DIR/lib/common.sh"
  # shellcheck source=lib/config.sh
  source "$ROOT_DIR/lib/config.sh"
  # shellcheck source=lib/context.sh
  source "$ROOT_DIR/lib/context.sh"
  # shellcheck source=lib/ports.sh
  source "$ROOT_DIR/lib/ports.sh"
  # shellcheck source=lib/cloudflare.sh
  source "$ROOT_DIR/lib/cloudflare.sh"
  # shellcheck source=lib/deploy.sh
  source "$ROOT_DIR/lib/deploy.sh"
  # shellcheck source=lib/doctor.sh
  source "$ROOT_DIR/lib/doctor.sh"
  # shellcheck source=lib/bootstrap.sh
  source "$ROOT_DIR/lib/bootstrap.sh"
  # shellcheck source=lib/version.sh
  source "$ROOT_DIR/lib/version.sh"
  # shellcheck source=lib/license.sh
  source "$ROOT_DIR/lib/license.sh"
  # shellcheck source=lib/list.sh
  source "$ROOT_DIR/lib/list.sh"
  # shellcheck source=lib/app.sh
  source "$ROOT_DIR/lib/app.sh"
}

