#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_helpers.sh"

integration_init
source_libs

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

cat >"$FB_HOME/appstatus/dev/ports.json" <<'JSON'
{"site":8080,"api":8081}
JSON

cloudflare_tunnel_running() { return 1; }

output="$(cmd_app_status -a appstatus -e dev -H root,api 2>&1)"
OUTPUT_DUMP="$output"

assert_contains "$output" "App status: appstatus/dev"
assert_contains "$output" "Resolved ports: site=8080 api=8081 (source=ports.json)"
assert_contains "$output" "Live: https://demo.example.com"
assert_contains "$output" "Live: https://api-demo.example.com"

echo "app_status_short_flags.sh OK"
