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

cat >"$APP_DIR/docker-compose.yml" <<'YAML'
services:
  app:
    image: example/app
    ports:
      - "8080:8080"
YAML

mkdir -p "$FB_HOME/appdown/dev"
cat >"$FB_HOME/appdown/dev/config.yml" <<'YAML'
tunnel: tunnel-999
ingress:
  - hostname: appdown.example.com
    service: http://localhost:8080
  - service: http_status:404
YAML

cloudflare_stop_tunnel() { return 0; }
stop_app_stack() { log_info "Stopped docker compose"; return 0; }
cf_ensure_zone() { CF_ZONE_ID="zone-123"; CF_ACCOUNT_ID="acct-123"; }
cf_delete_dns_record() { log_info "Deleted DNS record: $2"; }
cf_delete_tunnel() { log_info "Deleted tunnel: $2"; }

output="$(cmd_app_down appdown/dev --purge)"
OUTPUT_DUMP="$output"

assert_contains "$output" "Stopping: app=appdown env=dev"
assert_contains "$output" "Removed local state: $FB_HOME/appdown/dev"
assert_true "[[ ! -d \"$FB_HOME/appdown/dev\" ]]" "state dir removed"

echo "app_down.sh OK"
