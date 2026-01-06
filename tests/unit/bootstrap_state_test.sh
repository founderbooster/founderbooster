#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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

state_dir="$FB_HOME/demo/dev"
mkdir -p "$state_dir"
printf '%s\n' "$APP_DIR" >"$state_dir/compose.dir"
printf '{"site":8080,"api":9090}\n' >"$state_dir/ports.json"

cmd_bootstrap -a demo -d example.com -e dev -s 8080 -i 9090 -H root,api,www --shared-tunnel >/dev/null 2>&1

state_path="$FB_HOME/demo/dev/state.json"
assert_true "[[ -f \"$state_path\" ]]" "state.json should exist"

PYTHON_BIN="python3"
if ! command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python"
fi

$PYTHON_BIN - <<'PY' "$state_path" "$APP_DIR" \
  "$FB_HOME/demo/dev/config.yml" \
  "$FB_HOME/demo/dev/ports.json" \
  "$FB_HOME/demo/dev/compose.dir" \
  "$FB_HOME/demo/dev/tunnel.name" \
  "$FB_HOME/demo/dev/tunnel.token" \
  "$FB_HOME/demo/dev/cloudflared.pid" \
  "$FB_HOME/demo/dev/cloudflared.log"
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

required = ["version", "app", "env", "zone_apex", "fqdns", "tunnel_name", "tunnel_id", "shared_tunnel", "updated_at", "compose_dir", "paths"]
for key in required:
    if key not in data:
        raise SystemExit(f"missing key: {key}")

if data["version"] != 1:
    raise SystemExit("version must be 1")
if data["app"] != "demo" or data["env"] != "dev":
    raise SystemExit("app/env mismatch")
if data["zone_apex"] != "example.com":
    raise SystemExit("zone_apex mismatch")
if data["tunnel_name"] != "demo-dev":
    raise SystemExit("tunnel_name mismatch")
if data["tunnel_id"] != "tunnel-xyz":
    raise SystemExit("tunnel_id mismatch")
if data["shared_tunnel"] is not True:
    raise SystemExit("shared_tunnel mismatch")
if data["compose_dir"] != sys.argv[2]:
    raise SystemExit("compose_dir mismatch")
expected = ["api-dev.example.com", "dev.example.com", "www-dev.example.com"]
if data["fqdns"] != expected:
    raise SystemExit(f"fqdns mismatch: {data['fqdns']}")
if data.get("ports") != {"site": 8080, "api": 9090}:
    raise SystemExit("ports mismatch")
paths = data.get("paths", {})
expected_paths = {
    "config_yml": sys.argv[3],
    "ports_json": sys.argv[4],
    "compose_dir_file": sys.argv[5],
    "tunnel_name_file": sys.argv[6],
    "tunnel_token_file": sys.argv[7],
    "cloudflared_pid_file": sys.argv[8],
    "cloudflared_log_file": sys.argv[9],
}
if paths != expected_paths:
    raise SystemExit(f"paths mismatch: {paths}")
if "token-123" in json.dumps(data):
    raise SystemExit("state.json should not include token contents")
PY

echo "bootstrap_state_test.sh OK"
