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
die() { log_error "$@"; return 1; }
config_app_name() { return 1; }
config_get() { return 1; }
resolve_domain_for_env() { DOMAIN_NAME="$1"; }
docker_published_ports_for_app() { return 1; }
cloudflare_config_path() { echo "$FB_HOME/$1/$2/config.yml"; }
cloudflare_pid_path() { echo "$FB_HOME/$1/$2/cloudflared.pid"; }
cloudflare_token_path() { echo "$FB_HOME/$1/$2/tunnel.token"; }
cloudflare_compose_dir_path() { echo "$FB_HOME/$1/$2/compose.dir"; }
cloudflare_tunnel_name_path() { echo "$FB_HOME/$1/$2/tunnel.name"; }
cloudflare_stop_tunnel() { echo "stopped $1/$2"; }
cloudflare_tunnel_running() { [[ -f "$1" ]]; }
cloudflare_find_pid_by_config() { return 1; }
app_repo_matches() { return 0; }
stop_app_stack() { echo "stopped stack $1/$2"; return 0; }
cf_ensure_zone() { CF_ZONE_ID="zone-123"; CF_ACCOUNT_ID="acct-123"; }
cf_delete_dns_record() { echo "deleted dns $2"; }
cf_delete_tunnel() { echo "deleted tunnel $2"; }
cf_get_tunnel() { echo "tunnel-xyz"; }
cf_ensure_dns_record() { echo "ensure dns $2"; }
cf_create_tunnel() { echo "tunnel-abc"; }
cloudflare_get_token_or_file() { echo "token-123"; }
fb_abs_path() { printf '%s' "$1"; }
cloudflare_run_tunnel() {
  local app="$1"
  local env="$2"
  local token="$3"
  local pid_file
  pid_file="$(cloudflare_pid_path "$app" "$env")"
  if [[ -f "$pid_file" ]]; then
    echo "cloudflared already running (pid $(cat "$pid_file"))"
    return 0
  fi
  printf '9999\n' >"$pid_file"
  echo "cloudflared started (pid 9999)"
  echo "token_used=$token"
}

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
assert_contains "$list_out" "- $app/$env - type=app status=published pid=4321 compose=~/projects/demo"

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
assert_contains "$down_out" "App purged. Recreate with: fb bootstrap"
assert_true "[[ ! -d \"$state_dir\" ]]" "state dir should be removed"

# fb app down (unpublish)
down_unpub_out="$(cmd_app_down --app "$app2" --env "$env2" 2>&1)"
assert_contains "$down_unpub_out" "App unpublished. Local runtime preserved."
assert_contains "$down_unpub_out" "fb app up $app2/$env2"
if [[ "$down_unpub_out" == *"stopped stack"* ]]; then
  echo "ASSERT_TRUE failed: runtime should not be stopped by default" >&2
  exit 1
fi

app4="app4"
env4="dev"
state_dir4="$FB_HOME/$app4/$env4"
mkdir -p "$state_dir4"
echo "tunnel: 9999" >"$state_dir4/config.yml"
export FOUNDERBOOSTER_APP_DOWN_LEGACY_DEFAULT="1"
legacy_out="$(cmd_app_down --app "$app4" --env "$env4" 2>&1)"
unset FOUNDERBOOSTER_APP_DOWN_LEGACY_DEFAULT
assert_contains "$legacy_out" "stopped stack $app4/$env4"

app3="app1"
env3="dev"
state_dir3="$FB_HOME/$app3/$env3"
mkdir -p "$state_dir3"
cat >"$state_dir3/state.json" <<'JSON'
{
  "version": 1,
  "app": "app1",
  "env": "dev",
  "zone_apex": "example.com",
  "fqdns": ["api-dev.example.com", "dev.example.com"],
  "tunnel_name": "app1-dev",
  "tunnel_id": "tunnel-xyz",
  "shared_tunnel": false,
  "paths": {
    "config_yml": "",
    "ports_json": "",
    "compose_dir_file": "",
    "tunnel_name_file": "",
    "tunnel_token_file": "",
    "cloudflared_pid_file": "",
    "cloudflared_log_file": ""
  },
  "updated_at": "2024-01-01T00:00:00Z"
}
JSON
echo "tunnel: tunnel-xyz" >"$state_dir3/config.yml"
echo "hostname: dev.example.com" >>"$state_dir3/config.yml"
echo "hostname: api-dev.example.com" >>"$state_dir3/config.yml"
echo "token-123" >"$state_dir3/tunnel.token"

up_out="$(cmd_app_up --app "$app3" --env "$env3" 2>&1)"
assert_contains "$up_out" "App re-published."
assert_contains "$up_out" "ensure dns dev.example.com"
assert_contains "$up_out" "ensure dns api-dev.example.com"
assert_contains "$up_out" "cloudflared started (pid 9999)"

up_again_out="$(cmd_app_up --app "$app3" --env "$env3" 2>&1)"
assert_contains "$up_again_out" "cloudflared already running"

missing_out="$(cmd_app_up --app missing --env dev 2>&1 || true)"
assert_contains "$missing_out" "No local state. Run fb bootstrap in your app repo."

echo "app_test.sh OK"
