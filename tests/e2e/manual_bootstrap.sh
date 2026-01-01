#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_helpers.sh"

e2e_require_env CLOUDFLARE_API_TOKEN
e2e_require_domain
e2e_require_cmd cloudflared curl

e2e_setup_home

DEFAULT_MANUAL_APP_DIR="$ROOT_DIR/tests/e2e/apps/port-first-demo"
APP_DIR="${E2E_MANUAL_APP_DIR:-$DEFAULT_MANUAL_APP_DIR}"
if [[ ! -d "$APP_DIR" ]]; then
  if [[ -n "${E2E_MANUAL_APP_DIR:-}" ]]; then
    e2e_die "Manual app dir missing: $APP_DIR"
  fi
  e2e_die "Default manual app dir missing: $APP_DIR (set E2E_MANUAL_APP_DIR to override)"
fi

cd "$APP_DIR"

env_name="${E2E_ENV:-dev}"
hosts_list="${E2E_HOSTS:-root}"
domain="${E2E_MANUAL_DOMAIN:-$E2E_DOMAIN}"
port="${E2E_MANUAL_PORT:-3000}"

start_cmd="${E2E_MANUAL_START_CMD:-}"
if [[ -z "$start_cmd" ]]; then
  if [[ -x "./scripts/run-local.sh" ]]; then
    start_cmd="./scripts/run-local.sh"
  fi
fi
if [[ -z "$start_cmd" ]]; then
  e2e_die "Missing E2E_MANUAL_START_CMD (or scripts/run-local.sh)."
fi

echo "INFO: starting local server"
server_pid=""
server_kill_mode="pid"
if command -v setsid >/dev/null 2>&1; then
  setsid bash -c "exec $start_cmd" >/dev/null 2>&1 &
  server_pid=$!
  server_kill_mode="pgid"
else
  bash -c "exec $start_cmd" >/dev/null 2>&1 &
  server_pid=$!
fi

stop_local_server() {
  if [[ -z "${server_pid:-}" ]]; then
    return 0
  fi
  if [[ "$server_kill_mode" == "pgid" ]]; then
    kill -TERM -- "-$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" 2>/dev/null || true
  else
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" 2>/dev/null || true
  fi
  if [[ -n "${E2E_MANUAL_PORT:-}" ]] && command -v lsof >/dev/null 2>&1; then
    local lingering_pids=""
    lingering_pids="$(lsof -ti tcp:"$E2E_MANUAL_PORT" 2>/dev/null || true)"
    if [[ -n "$lingering_pids" ]]; then
      kill -TERM $lingering_pids >/dev/null 2>&1 || true
      sleep 1
      lingering_pids="$(lsof -ti tcp:"$E2E_MANUAL_PORT" 2>/dev/null || true)"
      if [[ -n "$lingering_pids" ]]; then
        kill -KILL $lingering_pids >/dev/null 2>&1 || true
      fi
    fi
  fi
}

if e2e_should_teardown; then
  trap stop_local_server EXIT
fi

e2e_wait_for_local_port "$port"

echo "INFO: fb app list (pre-bootstrap)"
list_out="$(e2e_fb app list || true)"
printf '%s\n' "$list_out" | sed 's/^/  /'

echo "INFO: fb bootstrap manual mode"
e2e_fb bootstrap --env "$env_name" --domain "$domain" --hosts "$hosts_list" --site-port "$port"

config_path="$FB_HOME/$(basename "$APP_DIR")/$env_name/config.yml"
if [[ ! -f "$config_path" ]]; then
  e2e_die "Missing config.yml: $config_path"
fi

if ! grep -q '^tunnel:' "$config_path"; then
  e2e_die "Missing tunnel ID in $config_path"
fi

if ! grep -q "hostname: $domain" "$config_path"; then
  e2e_die "Missing hostname $domain in $config_path"
fi

e2e_wait_for_cloudflare_url "https://$domain" "Cloudflare URL"
e2e_print_url_snippet "https://$domain" "Cloudflare URL"

echo "INFO: fb app list (post-bootstrap)"
list_out="$(e2e_fb app list || true)"
printf '%s\n' "$list_out" | sed 's/^/  /'

if e2e_should_teardown; then
  echo "INFO: stopping local server"
  stop_local_server
else
  echo "INFO: skipping local server shutdown (E2E_SKIP_TEARDOWN=1)"
fi

if e2e_should_teardown; then
  echo "INFO: fb app down --purge"
  e2e_fb app down "$(basename "$APP_DIR")/$env_name" --purge
else
  echo "INFO: skipping teardown (E2E_SKIP_TEARDOWN=1)"
fi

echo "manual_bootstrap.sh OK"
