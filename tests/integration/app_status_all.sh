#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_helpers.sh"

integration_init
source_libs

APP_DIR="$TMP_DIR/appstatusall"
mkdir -p "$APP_DIR"
cd "$APP_DIR"

cat >"$APP_DIR/founderbooster.yml" <<'YAML'
app: appstatusall
domains:
  dev: demo.example.com
  prod: demo.example.com
ports:
  dev:
    site: 8080
    api: 8081
  prod:
    site: 9090
    api: 9091
YAML

mkdir -p "$FB_HOME/appstatusall/dev"
mkdir -p "$FB_HOME/appstatusall/prod"

cat >"$FB_HOME/appstatusall/dev/config.yml" <<'YAML'
tunnel: tunnel-dev
ingress:
  - hostname: dev.demo.example.com
    service: http://localhost:8080
  - service: http_status:404
YAML

cat >"$FB_HOME/appstatusall/prod/config.yml" <<'YAML'
tunnel: tunnel-prod
ingress:
  - hostname: demo.example.com
    service: http://localhost:9090
  - service: http_status:404
YAML

cloudflare_tunnel_running() { return 1; }

output="$(cmd_app_status --app appstatusall --all)"
OUTPUT_DUMP="$output"

assert_contains "$output" "App status: appstatusall/dev"
assert_contains "$output" "App status: appstatusall/prod"

echo "app_status_all.sh OK"
