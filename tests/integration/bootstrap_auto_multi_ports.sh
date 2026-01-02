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
      - "8000:8000"
      - "8001:8001"
      - "8002:8002"
YAML

cd "$APP_DIR"

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
docker_published_ports_for_app() { printf '%s\n' 8000 8001 8002; }

output="$(cmd_bootstrap -d example.com -e dev 2>&1 || true)"
OUTPUT_DUMP="$output"

assert_contains "$output" "Multiple Docker ports found"
assert_contains "$output" "Choose ports explicitly: fb bootstrap -s <site> -i <api> (or --site-port/--api-port)"

echo "bootstrap_auto_multi_ports.sh OK"
