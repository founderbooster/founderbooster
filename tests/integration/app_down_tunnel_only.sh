#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_helpers.sh"

integration_init
source_libs

APP_DIR="$TMP_DIR/appdown"
mkdir -p "$APP_DIR"
cd "$APP_DIR"

cat >"$APP_DIR/founderbooster.yml" <<'YAML'
app: appdown
YAML

mkdir -p "$FB_HOME/appdown/dev"
cat >"$FB_HOME/appdown/dev/config.yml" <<'YAML'
tunnel: tunnel-999
ingress:
  - hostname: appdown.example.com
    service: http://localhost:8080
  - service: http_status:404
YAML

stop_flag="$TMP_DIR/stop-called"
stack_flag="$TMP_DIR/stack-called"

cloudflare_stop_tunnel() { printf 'called' >"$stop_flag"; }
stop_app_stack() { printf 'called' >"$stack_flag"; return 0; }
cf_ensure_zone() { CF_ZONE_ID="zone-123"; CF_ACCOUNT_ID="acct-123"; }
cf_delete_dns_record() { return 0; }

output_file="$TMP_DIR/output.txt"
cmd_app_down appdown/dev --tunnel-only >"$output_file" 2>&1 || true
output="$(cat "$output_file")"
OUTPUT_DUMP="$output"

assert_contains "$output" "Stopping: app=appdown env=dev"
assert_true "[[ -f \"$stop_flag\" ]]" "tunnel stopped"
assert_true "[[ ! -f \"$stack_flag\" ]]" "stack not stopped"
assert_true "[[ -d \"$FB_HOME/appdown/dev\" ]]" "state dir kept"

echo "app_down_tunnel_only.sh OK"
