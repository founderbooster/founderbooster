#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

e2e_die() {
  echo "E2E ERROR: $*" >&2
  exit 1
}

e2e_require_env() {
  local name
  for name in "$@"; do
    if [[ -z "${!name:-}" ]]; then
      e2e_die "Missing required env var: $name"
    fi
  done
}

e2e_require_domain() {
  if [[ -z "${E2E_DOMAIN:-}" && -z "${E2E_AUTO_DOMAIN:-}" && -z "${E2E_MANUAL_DOMAIN:-}" ]]; then
    e2e_die "Missing required env var: E2E_DOMAIN (or E2E_AUTO_DOMAIN/E2E_MANUAL_DOMAIN)"
  fi
}

e2e_require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      e2e_die "Missing required command: $cmd"
    fi
  done
}

e2e_wait_for_url() {
  local url="$1"
  local label="${2:-URL}"
  local tries="${3:-30}"
  local delay="${4:-2}"
  local i code
  for ((i=1; i<=tries; i++)); do
    code="$(curl -s -o /dev/null -w "%{http_code}" "$url" || true)"
    if [[ "$code" != "000" && "$code" != "502" && "$code" != "503" && "$code" != "504" ]]; then
      echo "INFO: $label reachable (http $code)."
      return 0
    fi
    sleep "$delay"
  done
  e2e_die "$label not reachable after $((tries * delay))s: $url"
}

e2e_wait_for_cloudflare_url() {
  local url="$1"
  local label="${2:-Cloudflare URL}"
  local tries="${3:-30}"
  local delay="${4:-2}"
  local i code
  for ((i=1; i<=tries; i++)); do
    code="$(curl -s -o /dev/null -w "%{http_code}" "$url" || true)"
    case "$code" in
      200|301|302|307|308)
        echo "INFO: $label ready (http $code)."
        return 0
        ;;
      000|502|503|504|530)
        ;;
      *)
        ;;
    esac
    sleep "$delay"
  done
  e2e_die "$label not ready after $((tries * delay))s: $url"
}

e2e_wait_for_local_port() {
  local port="$1"
  e2e_wait_for_url "http://localhost:$port" "Local app"
}

e2e_should_teardown() {
  [[ "${E2E_SKIP_TEARDOWN:-}" != "1" ]]
}

e2e_print_url_snippet() {
  local url="$1"
  local label="${2:-Live URL}"
  local snippet
  snippet="$(curl -sL --max-time 10 "$url" | head -c 400 | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')"
  if [[ -n "$snippet" ]]; then
    echo "INFO: $label snippet: ${snippet}..."
  else
    echo "INFO: $label snippet: <empty response>"
  fi
}

e2e_setup_home() {
  TMP_DIR="$(mktemp -d)"
  trap e2e_cleanup EXIT
  export FB_HOME="$TMP_DIR/fb-home"
  export FOUNDERBOOSTER_HOME="$FB_HOME"
}

e2e_cleanup() {
  if [[ "${KEEP_TMP:-}" == "1" || "${E2E_SKIP_TEARDOWN:-}" == "1" ]]; then
    return 0
  fi
  rm -rf "$TMP_DIR"
}

e2e_fb() {
  local fb_bin="${FB_BIN:-$ROOT_DIR/cmd/fb}"
  "$fb_bin" "$@"
}
