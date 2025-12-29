#!/usr/bin/env bash
set -euo pipefail

cf_api_request() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local url="https://api.cloudflare.com/client/v4${path}"
  local auth="Authorization: Bearer ${CLOUDFLARE_API_TOKEN:-}"
  if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
    die "CLOUDFLARE_API_TOKEN is required for Cloudflare API calls."
  fi
  local attempt=1
  local max_attempts=3
  local status=""
  local body=""
  while ((attempt<=max_attempts)); do
    local tmp
    tmp="$(mktemp)"
    if [[ -n "$data" ]]; then
      if ! status="$(curl -sS -X "$method" -H "$auth" -H "Content-Type: application/json" --data "$data" -o "$tmp" -w "%{http_code}" "$url")"; then
        status="000"
      fi
    else
      if ! status="$(curl -sS -X "$method" -H "$auth" -o "$tmp" -w "%{http_code}" "$url")"; then
        status="000"
      fi
    fi
    body="$(cat "$tmp")"
    rm -f "$tmp"
    if [[ "$status" =~ ^2 ]]; then
      printf '%s' "$body"
      return 0
    fi
    log_warn "Cloudflare API $method $path failed (status $status)."
    if [[ "$status" == "429" || "$status" =~ ^5 ]]; then
      if ((attempt < max_attempts)); then
        local sleep_sec=$((attempt * 2))
        log_warn "Retrying in ${sleep_sec}s..."
        sleep "$sleep_sec"
        attempt=$((attempt + 1))
        continue
      fi
    fi
    log_error "Cloudflare API error body: $body"
    return 1
  done
  return 1
}

cf_get_zone() {
  local domain="$1"
  local resp
  local candidate
  local -a parts
  IFS='.' read -r -a parts <<<"$domain"
  local count="${#parts[@]}"
  local i

  for ((i=0; i<=count-2; i++)); do
    candidate="${parts[*]:i}"
    candidate="${candidate// /.}"
    resp="$(cf_api_request GET "/zones?name=$candidate")"
    if [[ "$(echo "$resp" | jq -r '.success')" != "true" ]]; then
      local err
      err="$(echo "$resp" | jq -r '.errors[0].message // empty')"
      if [[ -n "$err" ]]; then
        die "Cloudflare zone lookup failed for $candidate: $err"
      fi
      die "Cloudflare zone lookup failed for $candidate."
    fi
    CF_ZONE_ID="$(echo "$resp" | jq -r '.result[0].id // empty')"
    CF_ACCOUNT_ID="$(echo "$resp" | jq -r '.result[0].account.id // empty')"
    if [[ -n "$CF_ZONE_ID" && -n "$CF_ACCOUNT_ID" ]]; then
      CF_ZONE_NAME="$candidate"
      return 0
    fi
  done
  return 1
}

cf_ensure_zone() {
  local domain="$1"
  if cf_get_zone "$domain"; then
    log_info "Cloudflare zone ready: $domain"
    return 0
  fi
  die "Cloudflare zone not found for $domain or parent domains. Add the zone in Cloudflare and try again."
}

cf_get_tunnel() {
  local account_id="$1"
  local name="$2"
  local resp
  resp="$(cf_api_request GET "/accounts/$account_id/cfd_tunnel?name=$name")"
  if [[ "$(echo "$resp" | jq -r '.success')" != "true" ]]; then
    local err
    err="$(echo "$resp" | jq -r '.errors[0].message // empty')"
    if [[ -n "$err" ]]; then
      die "Cloudflare tunnel lookup failed for $name: $err"
    fi
    die "Cloudflare tunnel lookup failed for $name."
  fi
  echo "$resp" | jq -r '.result[0].id // empty'
}

cf_create_tunnel() {
  local account_id="$1"
  local name="$2"
  local resp
  resp="$(cf_api_request POST "/accounts/$account_id/cfd_tunnel" "{\"name\":\"$name\"}")"
  if [[ "$(echo "$resp" | jq -r '.success')" != "true" ]]; then
    local err
    err="$(echo "$resp" | jq -r '.errors[0].message // empty')"
    if [[ -n "$err" ]]; then
      die "Cloudflare tunnel creation failed for $name: $err"
    fi
    die "Cloudflare tunnel creation failed for $name."
  fi
  echo "$resp" | jq -r '.result.id'
}

cf_get_tunnel_token() {
  local account_id="$1"
  local tunnel_id="$2"
  local resp
  resp="$(cf_api_request GET "/accounts/$account_id/cfd_tunnel/$tunnel_id/token")"
  if [[ "$(echo "$resp" | jq -r '.success')" != "true" ]]; then
    return 1
  fi
  echo "$resp" | jq -r '.result // empty'
}

cf_ensure_dns_record() {
  local zone_id="$1"
  local name="$2"
  local content="$3"
  local resp record_id existing_content
  resp="$(cf_api_request GET "/zones/$zone_id/dns_records?type=CNAME&name=$name")"
  if [[ "$(echo "$resp" | jq -r '.success')" != "true" ]]; then
    die "DNS record lookup failed for $name."
  fi
  record_id="$(echo "$resp" | jq -r '.result[0].id // empty')"
  existing_content="$(echo "$resp" | jq -r '.result[0].content // empty')"
  if [[ -n "$record_id" ]]; then
    if [[ "$existing_content" == "$content" ]]; then
      log_info "DNS record up-to-date: $name"
      return 0
    fi
    resp="$(cf_api_request PUT "/zones/$zone_id/dns_records/$record_id" "{\"type\":\"CNAME\",\"name\":\"$name\",\"content\":\"$content\",\"proxied\":true}")"
    if [[ "$(echo "$resp" | jq -r '.success')" != "true" ]]; then
      die "DNS record update failed for $name."
    fi
    log_info "DNS record updated: $name"
    return 0
  fi
  resp="$(cf_api_request POST "/zones/$zone_id/dns_records" "{\"type\":\"CNAME\",\"name\":\"$name\",\"content\":\"$content\",\"proxied\":true}")"
  if [[ "$(echo "$resp" | jq -r '.success')" != "true" ]]; then
    die "DNS record creation failed for $name."
  fi
  log_info "DNS record created: $name"
}

cf_get_dns_record() {
  local zone_id="$1"
  local name="$2"
  local resp
  resp="$(cf_api_request GET "/zones/$zone_id/dns_records?type=CNAME&name=$name")"
  if [[ "$(echo "$resp" | jq -r '.success')" != "true" ]]; then
    die "DNS record lookup failed for $name."
  fi
  echo "$resp" | jq -r '.result[0] // empty'
}

cloudflare_token_path() {
  local app="$1"
  local env="$2"
  echo "$FB_HOME/$app/$env/tunnel.token"
}

cloudflare_config_path() {
  local app="$1"
  local env="$2"
  echo "$FB_HOME/$app/$env/config.yml"
}

cloudflare_pid_path() {
  local app="$1"
  local env="$2"
  echo "$FB_HOME/$app/$env/cloudflared.pid"
}

cloudflare_log_path() {
  local app="$1"
  local env="$2"
  echo "$FB_HOME/$app/$env/cloudflared.log"
}

cloudflare_token_help() {
  cat <<'EOF'
To provide a Cloudflare tunnel token:

1) Create or select the tunnel in Cloudflare Zero Trust.
2) Copy the tunnel token from the tunnel details page.
3) Save it to:
   ~/.founderbooster/<app>/<env>/tunnel.token

If CLOUDFLARE_API_TOKEN has permissions, fb will fetch this automatically.
EOF
}

cloudflare_token_create_help() {
  cat <<'EOF'
Create a Cloudflare API token:

1) Log in to Cloudflare and go to:
   https://dash.cloudflare.com/profile/api-tokens
2) Click "Create Token" (custom token).
3) Use these permissions:
   - Account: Cloudflare Tunnel = Edit
   - Zone: DNS = Edit
   - Zone: Zone = Read
4) Scope to the account and the zone (domain) you plan to use.
5) Create and copy the token, then export it:
   export CLOUDFLARE_API_TOKEN=your_token_here
EOF
}

cloudflare_get_token_or_file() {
  local app="$1"
  local env="$2"
  local account_id="$3"
  local tunnel_id="$4"
  local token
  if token="$(cf_get_tunnel_token "$account_id" "$tunnel_id")"; then
    if [[ -n "$token" ]]; then
      local path
      path="$(cloudflare_token_path "$app" "$env")"
      ensure_dir "$(dirname "$path")"
      umask 077
      printf '%s\n' "$token" >"$path"
      echo "$token"
      return 0
    fi
  fi
  local file
  file="$(cloudflare_token_path "$app" "$env")"
  if [[ -f "$file" ]]; then
    token="$(cat "$file")"
    if [[ -n "$token" ]]; then
      echo "$token"
      return 0
    fi
  fi
  cloudflare_token_help
  die "Cloudflare tunnel token missing at $file."
}

render_cloudflared_config() {
  local app="$1"
  local env="$2"
  local tunnel_id="$3"
  local ingress_rules="$4"
  local template="$5"
  local out
  out="$(cloudflare_config_path "$app" "$env")"
  ensure_dir "$(dirname "$out")"
  {
    echo "tunnel: $tunnel_id"
    echo "ingress:"
    printf '%s\n' "$ingress_rules"
    echo "  - service: http_status:404"
  } >"$out"
  log_info "Rendered cloudflared config: $out"
}

cloudflare_tunnel_running() {
  local pid_file="$1"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file")"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

cloudflare_find_pid_by_config() {
  local config="$1"
  local pid=""
  pid="$(ps -eo pid=,command= | awk -v cfg="$config" '$0 ~ /cloudflared tunnel/ && $0 ~ ("--config " cfg) {print $1; exit}')"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "$pid"
    return 0
  fi
  return 1
}

cloudflare_run_tunnel() {
  local app="$1"
  local env="$2"
  local token="$3"
  local config
  config="$(cloudflare_config_path "$app" "$env")"
  local pid_file
  pid_file="$(cloudflare_pid_path "$app" "$env")"
  local log_file
  log_file="$(cloudflare_log_path "$app" "$env")"

  if cloudflare_tunnel_running "$pid_file"; then
    log_info "cloudflared already running (pid $(cat "$pid_file"))"
    return 0
  fi

  local existing_pid=""
  if existing_pid="$(cloudflare_find_pid_by_config "$config")"; then
    ensure_dir "$(dirname "$pid_file")"
    umask 077
    printf '%s\n' "$existing_pid" >"$pid_file"
    log_warn "cloudflared already running for config (pid $existing_pid); synced pid file"
    return 0
  fi

  ensure_dir "$(dirname "$pid_file")"
  umask 077
  nohup cloudflared tunnel --config "$config" run --token "$token" >"$log_file" 2>&1 &
  printf '%s\n' "$!" >"$pid_file"
  log_info "cloudflared started (pid $(cat "$pid_file"))"
  log_info "cloudflared logs: $log_file"
}

cloudflare_stop_tunnel() {
  local app="$1"
  local env="$2"
  local pid_file
  pid_file="$(cloudflare_pid_path "$app" "$env")"
  if ! [[ -f "$pid_file" ]]; then
    log_info "cloudflared not running (no pid file)."
    return 1
  fi
  local pid
  pid="$(cat "$pid_file")"
  if [[ -z "$pid" ]]; then
    log_info "cloudflared not running (empty pid file)."
    return 1
  fi
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid"
    for _ in {1..10}; do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 0.2
    done
    if kill -0 "$pid" 2>/dev/null; then
      log_warn "cloudflared did not exit; sending SIGKILL (pid $pid)."
      kill -9 "$pid" 2>/dev/null || true
    fi
    if kill -0 "$pid" 2>/dev/null; then
      log_warn "cloudflared still running (pid $pid)."
      return 1
    fi
    log_info "Stopped cloudflared (pid $pid)."
  else
    log_info "cloudflared not running."
  fi
  rm -f "$pid_file"
}

cmd_cloudflare() {
  local sub="${1:-}"
  case "$sub" in
    token)
      local next="${2:-}"
      if [[ "$next" == "help" ]]; then
        cloudflare_token_help
        return 0
      fi
      if [[ "$next" == "create" ]]; then
        cloudflare_token_create_help
        return 0
      fi
      ;;
    help|-h|--help|"")
      cat <<'EOF'
Usage: fb cloudflare <command>

Commands:
  token help        Show tunnel token instructions
  token create      Show API token creation instructions
EOF
      return 0
      ;;
  esac
  die "Unknown cloudflare command. Run: fb cloudflare --help"
}
