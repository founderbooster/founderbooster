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

source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/ports.sh"
source "$ROOT_DIR/lib/list.sh"
source "$ROOT_DIR/lib/app.sh"

# Override FB_HOME after sourcing common.sh
export FB_HOME="$TMP_DIR/fb-home"
mkdir -p "$FB_HOME"
export HOME="$TMP_DIR/home"
mkdir -p "$HOME"

# Stubs
fb_config_init() { CONFIG_FILE=""; }
config_app_name() { return 1; }
config_get() { return 1; }
resolve_domain_for_env() { DOMAIN_NAME="$1"; }
docker_published_ports_for_app() { return 1; }
cloudflare_config_path() { echo "$FB_HOME/$1/$2/config.yml"; }
cloudflare_pid_path() { echo "$FB_HOME/$1/$2/cloudflared.pid"; }
cloudflare_token_path() { echo "$FB_HOME/$1/$2/tunnel.token"; }
cloudflare_compose_dir_path() { echo "$FB_HOME/$1/$2/compose.dir"; }
cloudflare_stop_tunnel() { echo "stopped $1/$2"; }
cloudflare_tunnel_running() { [[ -f "$1" ]]; }
app_repo_matches() { return 0; }
stop_app_stack() { echo "stopped stack $1/$2"; return 0; }

app="app1"
env="dev"
state_dir="$FB_HOME/$app/$env"
mkdir -p "$state_dir"
echo "tunnel: 1234" >"$state_dir/config.yml"
echo "hostname: example.com" >>"$state_dir/config.yml"
printf '{"site":8055,"api":8055}\n' >"$state_dir/ports.json"
echo "4321" >"$state_dir/cloudflared.pid"
mkdir -p "$HOME/projects/demo"
printf '%s\n' "$HOME/projects/demo" >"$state_dir/compose.dir"

# fb app list
list_out="$(cmd_list 2>&1)"
assert_contains "$list_out" "- $app/$env - type=app tunnel=running pid=4321 compose=~/projects/demo"

# fb app status
status_out="$(cmd_app_status --app "$app" --env "$env" 2>&1)"
assert_contains "$status_out" "App status: $app/$env"
assert_contains "$status_out" "cloudflared running (pid 4321)."
assert_contains "$status_out" "Live: https://example.com"

# fb app down --tunnel-only (should not remove state)
down_tunnel_out="$(cmd_app_down --app "$app" --env "$env" --tunnel-only 2>&1)"
assert_contains "$down_tunnel_out" "Stopping: app=$app env=$env"
assert_true "[[ -d \"$state_dir\" ]]" "state dir should remain for tunnel-only"

app2="app1"
env2="staging"
state_dir2="$FB_HOME/$app2/$env2"
mkdir -p "$state_dir2"
echo "tunnel: 5678" >"$state_dir2/config.yml"

# fb app status --all
status_all_out="$(cmd_app_status --app "$app2" --all 2>&1)"
assert_contains "$status_all_out" "App status: $app2/dev"
assert_contains "$status_all_out" "App status: $app2/staging"

# fb app down --purge
down_out="$(cmd_app_down --app "$app" --env "$env" --purge 2>&1)"
assert_contains "$down_out" "Stopping: app=$app env=$env"
assert_contains "$down_out" "Removed local state: $state_dir"
assert_true "[[ ! -d \"$state_dir\" ]]" "state dir should be removed"

echo "app_test.sh OK"
