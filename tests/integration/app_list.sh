#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_helpers.sh"

integration_init
source_libs

mkdir -p "$FB_HOME/app1/dev"
mkdir -p "$FB_HOME/app2/prod"
printf '%s\n' "$HOME/demo-app" >"$FB_HOME/app1/dev/compose.dir"

cat >"$FB_HOME/app1/dev/config.yml" <<'YAML'
tunnel: tunnel-123
ingress:
  - hostname: app1.example.com
    service: http://localhost:8000
  - service: http_status:404
YAML

cat >"$FB_HOME/app2/prod/config.yml" <<'YAML'
tunnel: tunnel-456
ingress:
  - hostname: app2.example.com
    service: http://localhost:9000
  - service: http_status:404
YAML

echo "4242" >"$FB_HOME/app1/dev/cloudflared.pid"

cloudflare_tunnel_running() {
  local pid_file="$1"
  [[ -f "$pid_file" ]]
}

output="$(cmd_list)"
OUTPUT_DUMP="$output"

assert_contains "$output" "- app1/dev - type=app tunnel=running pid=4242 compose=~/demo-app"
assert_contains "$output" "- app2/prod - type=app tunnel=stopped pid=- compose=-"

echo "app_list.sh OK"
