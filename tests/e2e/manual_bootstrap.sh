#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_helpers.sh"

e2e_require_env CLOUDFLARE_API_TOKEN E2E_DOMAIN E2E_MANUAL_APP_DIR
e2e_require_cmd cloudflared curl

e2e_setup_home

APP_DIR="$E2E_MANUAL_APP_DIR"
if [[ ! -d "$APP_DIR" ]]; then
  e2e_die "Manual app dir missing: $APP_DIR"
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
bash -c "$start_cmd" >/dev/null 2>&1 &
server_pid=$!

trap 'kill "$server_pid" >/dev/null 2>&1 || true' EXIT

e2e_wait_for_local_port "$port"

echo "INFO: fb app list"
e2e_fb app list || true

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

e2e_wait_for_url "https://$domain" "Cloudflare URL"

echo "INFO: stopping local server"
kill "$server_pid" >/dev/null 2>&1 || true
wait "$server_pid" 2>/dev/null || true

echo "INFO: fb app down --purge"
e2e_fb app down "$(basename "$APP_DIR")/$env_name" --purge

echo "manual_bootstrap.sh OK"
