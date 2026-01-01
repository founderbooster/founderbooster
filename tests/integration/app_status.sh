#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_helpers.sh"

integration_init
source_libs

APP_DIR="$TMP_DIR/appstatus"
mkdir -p "$APP_DIR"
cd "$APP_DIR"

cat >"$APP_DIR/founderbooster.yml" <<'YAML'
app: appstatus
domains:
  dev: demo.example.com
ports:
  dev:
    site: 8080
    api: 8081
YAML

mkdir -p "$FB_HOME/appstatus/dev"
cat >"$FB_HOME/appstatus/dev/config.yml" <<'YAML'
tunnel: tunnel-123
ingress:
  - hostname: demo.example.com
    service: http://localhost:8080
  - hostname: api-demo.example.com
    service: http://localhost:8081
  - service: http_status:404
YAML

echo "1234" >"$FB_HOME/appstatus/dev/cloudflared.pid"

cloudflare_tunnel_running() {
  local pid_file="$1"
  [[ -f "$pid_file" ]]
}

output="$(cmd_app_status --app appstatus --env dev --hosts root)"
OUTPUT_DUMP="$output"

assert_contains "$output" "App status: appstatus/dev"
assert_contains "$output" "cloudflared running (pid 1234)."
assert_contains "$output" "Resolved ports: site=8080 api=8081 (source=config)"
assert_contains "$output" "Live: https://demo.example.com"

echo "app_status.sh OK"
