#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "ASSERT_CONTAINS failed: missing '$needle' $msg" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-}"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "ASSERT_NOT_CONTAINS failed: found '$needle' $msg" >&2
    exit 1
  fi
}

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

export FB_HOME="$TMP_DIR/fb-home"
export FOUNDERBOOSTER_HOME="$FB_HOME"
export FB_TEST_MODE="true"
export FB_ROOT="$ROOT_DIR"
mkdir -p "$FB_HOME"

APP_DIR="$TMP_DIR/app"
mkdir -p "$APP_DIR"
cd "$APP_DIR"

source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/context.sh"
source "$ROOT_DIR/lib/ports.sh"
source "$ROOT_DIR/lib/cloudflare.sh"
source "$ROOT_DIR/lib/deploy.sh"
source "$ROOT_DIR/lib/bootstrap.sh"

export FB_HOME="$TMP_DIR/fb-home"
mkdir -p "$FB_HOME"

fb_config_init() { CONFIG_FILE=""; }
config_app_name() { return 0; }
config_get() { return 0; }
resolve_ports() {
  SITE_PORT="${3:-8080}"
  API_PORT="${4:-9090}"
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
cloudflare_write_tunnel_name() { return 0; }
cf_get_tunnel_connections() { echo "[]"; }
cf_ensure_zone() { CF_ZONE_ID="zone-123"; CF_ACCOUNT_ID="acct-123"; CF_ZONE_NAME="example.com"; }
cf_get_tunnel() { echo "tunnel-xyz"; }
cf_create_tunnel() { echo "tunnel-123"; }
cf_ensure_dns_record() { return 0; }
render_cloudflared_config() { return 0; }
cloudflare_get_token_or_file() { echo "token-123"; }

output="$(cmd_bootstrap -a demo -d example.com -e dev -s 8080 -i 9090 -H root,api --shared-tunnel 2>/dev/null)"

assert_contains "$output" "FB_APP=demo"
assert_contains "$output" "FB_ENV=dev"
assert_contains "$output" "FB_ZONE_APEX=example.com"
assert_contains "$output" "FB_TUNNEL_NAME=demo-dev"
assert_contains "$output" "FB_TUNNEL_ID=tunnel-xyz"
assert_contains "$output" "FB_FQDNS=api-dev.example.com,dev.example.com"
assert_contains "$output" "FB_STATE_DIR=$FB_HOME/demo/dev"
assert_not_contains "$output" "token-123" "should not print Cloudflare token"

echo "bootstrap_machine_output_test.sh OK"
