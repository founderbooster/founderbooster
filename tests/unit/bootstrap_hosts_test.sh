#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "ASSERT_CONTAINS failed: missing '$needle'" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "ASSERT_NOT_CONTAINS failed: found '$needle'" >&2
    exit 1
  fi
}

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

export FB_HOME="$TMP_DIR/fb-home"
export FB_TEST_MODE="true"
export FB_ROOT="$ROOT_DIR"
mkdir -p "$FB_HOME"

APP_DIR="$TMP_DIR/app"
mkdir -p "$APP_DIR"
cat >"$APP_DIR/docker-compose.yml" <<'YAML'
services:
  app:
    image: example/app
    ports:
      - "8080:8080"
YAML
cd "$APP_DIR"

source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/context.sh"
source "$ROOT_DIR/lib/cloudflare.sh"
source "$ROOT_DIR/lib/deploy.sh"
source "$ROOT_DIR/lib/bootstrap.sh"

export FB_HOME="$TMP_DIR/fb-home"
mkdir -p "$FB_HOME"

fb_config_init() { CONFIG_FILE=""; }
config_app_name() { return 0; }
config_get() { return 0; }
resolve_ports() { SITE_PORT="8080"; API_PORT="8080"; PORTS_SOURCE="flags"; }
docker_published_ports_for_app() { return 1; }
ensure_ports_available() { return 0; }
ports_json_path() { echo "$FB_HOME/$1/$2/ports.json"; }
write_ports_json() { return 0; }
require_cmd() { return 0; }
cmd_doctor() { return 0; }
deploy_app() { return 0; }
cloudflare_run_tunnel() { return 0; }
cloudflare_stop_tunnel() { return 0; }
cloudflare_tunnel_running() { return 1; }
cf_get_tunnel_connections() { echo "[]"; }
cf_ensure_zone() { CF_ZONE_ID="zone-123"; CF_ACCOUNT_ID="acct-123"; }
cf_get_tunnel() { echo ""; }
cf_create_tunnel() { echo "tunnel-123"; }
cf_ensure_dns_record() { return 0; }
cloudflare_get_token_or_file() { echo "token-123"; }

cmd_bootstrap -d example.com

config_path="$FB_HOME/app/dev/config.yml"
if [[ ! -f "$config_path" ]]; then
  echo "Expected config.yml at $config_path" >&2
  exit 1
fi

config_contents="$(cat "$config_path")"
assert_contains "$config_contents" "hostname: dev.example.com"
assert_not_contains "$config_contents" "hostname: api-dev.example.com"
assert_not_contains "$config_contents" "hostname: www-dev.example.com"

echo "bootstrap_hosts_test.sh OK"
