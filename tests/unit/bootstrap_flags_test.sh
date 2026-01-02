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

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

export FB_HOME="$TMP_DIR/fb-home"
export FB_TEST_MODE="true"
export FB_ROOT="$ROOT_DIR"
mkdir -p "$FB_HOME"

APP_DIR="$TMP_DIR/app"
mkdir -p "$APP_DIR"
cat >"$APP_DIR/docker-compose.yml" <<'YAML'
services:
  app:
    image: example/app
    ports:
      - "8080:8080"
YAML
cd "$APP_DIR"

source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/context.sh"
source "$ROOT_DIR/lib/cloudflare.sh"
source "$ROOT_DIR/lib/deploy.sh"
source "$ROOT_DIR/lib/bootstrap.sh"

export FB_HOME="$TMP_DIR/fb-home"
mkdir -p "$FB_HOME"

CAP_SITE_FLAG=""
CAP_API_FLAG=""
fb_config_init() { CONFIG_FILE=""; }
config_app_name() { return 0; }
config_get() { return 0; }
resolve_ports() {
  CAP_SITE_FLAG="$3"
  CAP_API_FLAG="$4"
  if [[ -n "$CAP_SITE_FLAG" ]]; then
    SITE_PORT="$CAP_SITE_FLAG"
  else
    SITE_PORT="8080"
  fi
  if [[ -n "$CAP_API_FLAG" ]]; then
    API_PORT="$CAP_API_FLAG"
  else
    API_PORT="$SITE_PORT"
  fi
  PORTS_SOURCE="flags"
}
docker_published_ports_for_app() { return 1; }
ensure_ports_available() { return 0; }
port_in_use() { return 1; }
ports_json_path() { echo "$FB_HOME/$1/$2/ports.json"; }
write_ports_json() { return 0; }
require_cmd() { return 0; }
cmd_doctor() { return 0; }
deploy_app() { return 0; }
cloudflare_run_tunnel() { return 0; }
cloudflare_stop_tunnel() { return 0; }
cloudflare_tunnel_running() { return 1; }
cf_get_tunnel_connections() { echo "[]"; }
cf_ensure_zone() { CF_ZONE_ID="zone-123"; CF_ACCOUNT_ID="acct-123"; }
cf_get_tunnel() { echo ""; }
cf_create_tunnel() { echo "tunnel-123"; }
cf_ensure_dns_record() { return 0; }
cloudflare_get_token_or_file() { echo "token-123"; }

cmd_bootstrap -d example.com -i 9090 -e dev

assert_eq "" "$CAP_SITE_FLAG" "site flag should be empty when -s omitted"
assert_eq "9090" "$CAP_API_FLAG" "api flag should capture -i"
assert_eq "8080" "$SITE_PORT" "site should default when -s omitted"
assert_eq "9090" "$API_PORT" "api should use -i value"

echo "bootstrap_flags_test.sh OK"
