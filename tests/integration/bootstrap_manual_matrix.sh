#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_helpers.sh"

integration_init
stub_curl_http_ok
source_libs

APP_DIR="$TMP_DIR/app"
mkdir -p "$APP_DIR"
cd "$APP_DIR"

require_cmd() { return 0; }
cmd_doctor() { log_info "Prerequisites OK."; return 0; }
cloudflare_run_tunnel() { return 0; }
cloudflare_stop_tunnel() { return 0; }
cloudflare_tunnel_running() { return 1; }
cf_get_tunnel_connections() { echo "[]"; }
cf_ensure_zone() { CF_ZONE_ID="zone-123"; CF_ACCOUNT_ID="acct-123"; log_info "Cloudflare zone ready: example.com"; }
cf_get_tunnel() { echo ""; }
cf_create_tunnel() { echo "tunnel-123"; }
cf_ensure_dns_record() { log_info "DNS record up-to-date: $2"; }
cf_get_tunnel_token() { echo "token-123"; }

cases=(
  "dev|subdomain.example.com|root|subdomain.example.com|subdomain.example.com||"
  "staging|example.com|root,api|staging.example.com|staging.example.com|api-staging.example.com|"
)

for case in "${cases[@]}"; do
  IFS='|' read -r env domain hosts expected_domain expect_root expect_api expect_www <<<"$case"
  output_file="$TMP_DIR/output-${env}.txt"
  cmd_bootstrap --domain "$domain" --env "$env" --hosts "$hosts" --site-port 8080 >"$output_file" 2>&1 || true
  output="$(cat "$output_file")"
  OUTPUT_DUMP="$output"
  echo "Output captured at: $output_file"

  assert_contains "$output" "Context: app=app env=$env domain=$expected_domain"
  assert_contains "$output" "Manual mode: FB does not manage your app process."

  config_path="$FB_HOME/app/$env/config.yml"
  assert_true "[[ -f \"$config_path\" ]]" "config.yml written for $env"

  if [[ -n "$expect_root" ]]; then
    assert_true "grep -q \"hostname: $expect_root\" \"$config_path\"" "root hostname for $env"
  fi
  if [[ -n "$expect_api" ]]; then
    assert_true "grep -q \"hostname: $expect_api\" \"$config_path\"" "api hostname for $env"
  fi
  if [[ -n "$expect_www" ]]; then
    assert_true "grep -q \"hostname: $expect_www\" \"$config_path\"" "www hostname for $env"
  fi
done

echo "bootstrap_manual_matrix.sh OK"
