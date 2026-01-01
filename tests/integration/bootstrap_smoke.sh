#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_helpers.sh"

integration_init
stub_curl_http_ok
source_libs

APP_DIR="$TMP_DIR/app"
mkdir -p "$APP_DIR"
cat >"$APP_DIR/docker-compose.yml" <<'YAML'
services:
  app:
    image: example/app
    ports:
      - "8055:8055"
YAML

cd "$APP_DIR"

# Override heavy operations for integration smoke test
require_cmd() { return 0; }
cmd_doctor() { log_info "Prerequisites OK."; return 0; }
cloudflare_run_tunnel() { return 0; }
cloudflare_stop_tunnel() { return 0; }
cloudflare_tunnel_running() { return 1; }
cf_get_tunnel_connections() { echo "[]"; }
cf_ensure_zone() { CF_ZONE_ID="zone-123"; CF_ACCOUNT_ID="acct-123"; log_info "Cloudflare zone ready: example.com"; }
cf_get_tunnel() { echo ""; }
cf_create_tunnel() { echo "tunnel-123"; }
cf_ensure_dns_record() { log_info "DNS record up-to-date: $2"; }
cf_get_tunnel_token() { echo "token-123"; }

output_file="$TMP_DIR/output.txt"
cmd_bootstrap --domain example.com --env dev --hosts root >"$output_file" 2>&1 || true
output="$(cat "$output_file")"
OUTPUT_DUMP="$output"
echo "Output captured at: $output_file"

assert_contains "$output" "Context: app=app env=dev domain=dev.example.com"
assert_contains "$output" "Cloudflare zone ready"
assert_contains "$output" "Rendered cloudflared config"
assert_contains "$output" "Running docker compose up -d"

config_path="$FB_HOME/app/dev/config.yml"
assert_true "[[ -f \"$config_path\" ]]" "config.yml written"

echo "bootstrap_smoke.sh OK"
