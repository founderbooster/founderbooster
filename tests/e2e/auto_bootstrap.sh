#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_helpers.sh"

e2e_require_env CLOUDFLARE_API_TOKEN
e2e_require_domain
e2e_require_cmd docker cloudflared curl

e2e_setup_home

DEFAULT_AUTO_APP_DIR="$ROOT_DIR/tests/e2e/apps/directus-demo"
APP_DIR="${E2E_AUTO_APP_DIR:-$DEFAULT_AUTO_APP_DIR}"
if [[ ! -f "$APP_DIR/docker-compose.yml" && ! -f "$APP_DIR/docker-compose.yaml" ]]; then
  if [[ -n "${E2E_AUTO_APP_DIR:-}" ]]; then
    e2e_die "Auto app dir missing docker-compose.yml or docker-compose.yaml: $APP_DIR"
  fi
  e2e_die "Default auto app dir missing docker-compose.yml or docker-compose.yaml: $APP_DIR (set E2E_AUTO_APP_DIR to override)"
fi

cd "$APP_DIR"

env_name="${E2E_ENV:-dev}"
hosts_list="${E2E_HOSTS:-}"
domain="${E2E_AUTO_DOMAIN:-$E2E_DOMAIN}"

echo "INFO: fb app list (pre-bootstrap)"
list_out="$(e2e_fb app list || true)"
printf '%s\n' "$list_out" | sed 's/^/  /'

echo "INFO: fb bootstrap auto mode"
bootstrap_args=(--env "$env_name" --domain "$domain")
if [[ -n "$hosts_list" ]]; then
  bootstrap_args+=(--hosts "$hosts_list")
fi
e2e_fb bootstrap "${bootstrap_args[@]}"

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
expected_compose="$APP_DIR"
if [[ -n "${HOME:-}" && "$expected_compose" == "$HOME/"* ]]; then
  expected_compose="~/${expected_compose#$HOME/}"
fi
if [[ "$list_out" != *"compose=$expected_compose"* ]]; then
  e2e_die "Expected compose dir not shown in app list: compose=$expected_compose"
fi

if e2e_should_teardown; then
  echo "INFO: fb app down --purge"
  e2e_fb app down "$(basename "$APP_DIR")/$env_name" --purge
else
  echo "INFO: skipping teardown (E2E_SKIP_TEARDOWN=1)"
fi

echo "auto_bootstrap.sh OK"
