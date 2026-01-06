#!/usr/bin/env bash
set -euo pipefail

bootstrap_help() {
  cat <<'EOF'
Usage: fb bootstrap [options]

Options:
  -a, --app NAME         Override app name
  -e, --env ENV          Environment (dev|staging|prod)
  -d, --domain DOMAIN    Override domain
  -s, --site-port PORT   Override site port
  -i, --api-port PORT    Override api port
  -H, --hosts LIST       Comma list: root,api,www
  --auto-ports       Auto-select next available port pair
  --auto-detect-ports  Auto-detect Docker ports (default: on)
  --no-cache         Create Cloudflare cache bypass rule for hostnames (requires Cache Rules/Rulesets Edit)
  --shared-tunnel    Reuse <app>-<env> tunnel name across machines (HA)
  --machine          Emit machine-readable FB_ lines (default: on)
  --print-env        Emit machine-readable FB_ lines (default: on)
  --no-machine       Disable machine-readable FB_ lines
  --no-print-env     Disable machine-readable FB_ lines
EOF
}

log_live_urls() {
  local domain="$1"
  log_info "Open:"
  if is_true "$HOSTNAME_ROOT"; then
    log_info "  https://$domain"
  fi
  if is_true "$HOSTNAME_API"; then
    log_info "  https://$API_HOSTNAME_OVERRIDE"
  fi
  if is_true "$HOSTNAME_WWW"; then
    log_info "  https://$WWW_HOSTNAME_OVERRIDE"
  fi
  if is_true "$HOSTNAME_ROOT"; then
    log_info "🚀 Live: https://$domain"
  elif is_true "$HOSTNAME_API"; then
    log_info "🚀 Live: https://$API_HOSTNAME_OVERRIDE"
  elif is_true "$HOSTNAME_WWW"; then
    log_info "🚀 Live: https://$WWW_HOSTNAME_OVERRIDE"
  fi
}

log_ports_summary() {
  local source="$PORTS_SOURCE"
  if [[ "$SITE_PORT" == "$API_PORT" ]]; then
    if [[ "${FB_USER_PORTS:-}" == "true" ]]; then
      log_info "Using user-specified ports: site=$SITE_PORT api=$API_PORT."
      return 0
    fi
    case "$source" in
      docker) log_info "Using detected ports: localhost:$SITE_PORT (from Docker)." ;;
      ports.json) log_info "Using saved ports: site=$SITE_PORT api=$API_PORT (from previous run)." ;;
      config) log_info "Using config ports: site=$SITE_PORT api=$API_PORT." ;;
      auto) log_info "Auto-selected ports: site=$SITE_PORT api=$API_PORT." ;;
      deterministic) log_info "Using default ports: site=$SITE_PORT api=$API_PORT." ;;
      *) log_info "Using ports: site=$SITE_PORT api=$API_PORT." ;;
    esac
  else
    if [[ "${FB_USER_PORTS:-}" == "true" ]]; then
      log_info "Using user-specified ports: site=$SITE_PORT api=$API_PORT."
      return 0
    fi
    case "$source" in
      docker) log_info "Using detected ports: site=$SITE_PORT api=$API_PORT (from Docker)." ;;
      ports.json) log_info "Using saved ports: site=$SITE_PORT api=$API_PORT (from previous run)." ;;
      config) log_info "Using config ports: site=$SITE_PORT api=$API_PORT." ;;
      auto) log_info "Auto-selected ports: site=$SITE_PORT api=$API_PORT." ;;
      deterministic) log_info "Using default ports: site=$SITE_PORT api=$API_PORT." ;;
      *) log_info "Using ports: site=$SITE_PORT api=$API_PORT." ;;
    esac
  fi
}

wait_for_http_ready() {
  local url="$1"
  local label="$2"
  local reject_404="${3:-false}"
  local tries=30
  local delay=2
  if [[ "${FB_TEST_MODE:-}" == "true" ]]; then
    tries=3
    delay=0
  fi
  local i
  for ((i=1; i<=tries; i++)); do
    local code
    if code="$(curl -s -o /dev/null -w "%{http_code}" "$url")"; then
      :
    else
      code="000"
    fi
    if [[ "$reject_404" == "true" && "$code" == "404" ]]; then
      sleep "$delay"
      continue
    fi
    if [[ "$code" != "000" && "$code" != "502" && "$code" != "503" && "$code" != "504" ]]; then
      if [[ "$code" == "302" ]]; then
        log_info "$label reachable (http $code, redirect expected)."
      else
        log_info "$label reachable (http $code)."
      fi
      return 0
    fi
    sleep "$delay"
  done
  log_warn "$label not reachable after $((tries * delay))s; continuing."
  return 1
}

resolve_ready_url() {
  local url="$1"
  local redirect
  redirect="$(curl -s -o /dev/null -w "%{redirect_url}" "$url" || true)"
  if [[ -n "$redirect" ]]; then
    echo "$redirect"
    return 0
  fi
  echo "$url"
}

hash_short() {
  local input="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$input" | shasum -a 256 | awk '{print substr($1,1,4)}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$input" | sha256sum | awk '{print substr($1,1,4)}'
    return 0
  fi
  printf '%s' "$input" | tr -cd 'a-zA-Z0-9' | cut -c1-4
}

machine_suffix() {
  local raw=""
  if [[ -f "/etc/machine-id" ]]; then
    raw="$(cat /etc/machine-id 2>/dev/null || true)"
  fi
  if [[ -z "$raw" ]]; then
    raw="$(hostname 2>/dev/null || true)"
  fi
  if [[ -z "$raw" ]]; then
    raw="fb"
  fi
  hash_short "$raw"
}

fb_abs_path() {
  local path="$1"
  if [[ "$path" == /* ]]; then
    printf '%s' "$path"
    return 0
  fi
  if command -v realpath >/dev/null 2>&1; then
    realpath "$path"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY' "$path"
import os
import sys
print(os.path.abspath(sys.argv[1]))
PY
    return 0
  fi
  printf '%s' "$PWD/$path"
}

sanitize_fb_value() {
  local val="${1:-}"
  val="${val//$'\n'/}"
  val="${val//$'\r'/}"
  printf '%s' "$val"
}

json_escape() {
  local val="${1:-}"
  val="${val//\\/\\\\}"
  val="${val//\"/\\\"}"
  val="${val//$'\n'/}"
  val="${val//$'\r'/}"
  val="${val//$'\t'/}"
  printf '%s' "$val"
}

build_bootstrap_fqdns_list() {
  local list=""
  if is_true "$HOSTNAME_ROOT"; then
    list+="$DOMAIN_NAME"$'\n'
  fi
  if is_true "$HOSTNAME_API"; then
    list+="$API_HOSTNAME_OVERRIDE"$'\n'
  fi
  if is_true "$HOSTNAME_WWW"; then
    list+="$WWW_HOSTNAME_OVERRIDE"$'\n'
  fi
  if [[ -z "$list" ]]; then
    return 0
  fi
  printf '%s' "$list" | awk 'NF' | sort -u
}

print_fb_env_lines() {
  local app="${1:-}"
  local env="${2:-}"
  local zone_apex="${3:-}"
  local tunnel_name="${4:-}"
  local tunnel_id="${5:-}"
  local fqdns="${6:-}"
  local state_dir="${7:-}"

  printf 'FB_APP=%s\n' "$(sanitize_fb_value "$app")"
  printf 'FB_ENV=%s\n' "$(sanitize_fb_value "$env")"
  printf 'FB_ZONE_APEX=%s\n' "$(sanitize_fb_value "$zone_apex")"
  printf 'FB_TUNNEL_NAME=%s\n' "$(sanitize_fb_value "$tunnel_name")"
  printf 'FB_TUNNEL_ID=%s\n' "$(sanitize_fb_value "$tunnel_id")"
  printf 'FB_FQDNS=%s\n' "$(sanitize_fb_value "$fqdns")"
  printf 'FB_STATE_DIR=%s\n' "$(sanitize_fb_value "$state_dir")"
}

build_bootstrap_fqdns() {
  local list=""
  local item
  while IFS= read -r item; do
    list+="${list:+,}$item"
  done < <(build_bootstrap_fqdns_list || true)
  printf '%s' "$list"
}

read_compose_dir_value() {
  local file="$1"
  if [[ -f "$file" ]]; then
    local val
    val="$(cat "$file" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    printf '%s' "$val"
    return 0
  fi
  return 1
}

write_state_json() {
  local state_dir="$1"
  local app="$2"
  local env="$3"
  local zone_apex="$4"
  local tunnel_name="$5"
  local tunnel_id="$6"
  local shared_tunnel="$7"
  local fqdns_list="$8"
  local compose_dir="$9"
  local ports_json="${10:-}"
  local auto_mode="${11:-}"
  local runtime_type="${12:-}"

  ensure_dir "$state_dir"
  local tmp_file="$state_dir/state.json.tmp"
  local out_file="$state_dir/state.json"
  local updated_at
  updated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local fqdns_json=""
  local item
  while IFS= read -r item; do
    fqdns_json+="${fqdns_json:+,}\"$(json_escape "$item")\""
  done <<<"$fqdns_list"

  local config_yml
  config_yml="$(fb_abs_path "$(cloudflare_config_path "$app" "$env")")"
  local ports_json_path
  ports_json_path="$(fb_abs_path "$(ports_json_path "$app" "$env")")"
  local compose_dir_file
  compose_dir_file="$(fb_abs_path "$(cloudflare_compose_dir_path "$app" "$env")")"
  local tunnel_name_file
  tunnel_name_file="$(fb_abs_path "$(cloudflare_tunnel_name_path "$app" "$env")")"
  local tunnel_token_file
  tunnel_token_file="$(fb_abs_path "$(cloudflare_token_path "$app" "$env")")"
  local cloudflared_pid_file
  cloudflared_pid_file="$(fb_abs_path "$(cloudflare_pid_path "$app" "$env")")"
  local cloudflared_log_file
  cloudflared_log_file="$(fb_abs_path "$(cloudflare_log_path "$app" "$env")")"

  local runtime_json=""
  local cloudflared_running="false"
  if cloudflare_tunnel_running "$cloudflared_pid_file"; then
    cloudflared_running="true"
  fi
  runtime_json="\"cloudflared_running\":${cloudflared_running}"

  printf '{' >"$tmp_file"
  printf '"version":1,' >>"$tmp_file"
  printf '"app":"%s",' "$(json_escape "$app")" >>"$tmp_file"
  printf '"env":"%s",' "$(json_escape "$env")" >>"$tmp_file"
  printf '"zone_apex":"%s",' "$(json_escape "$zone_apex")" >>"$tmp_file"
  printf '"fqdns":[%s],' "$fqdns_json" >>"$tmp_file"
  printf '"tunnel_name":"%s",' "$(json_escape "$tunnel_name")" >>"$tmp_file"
  printf '"tunnel_id":"%s",' "$(json_escape "$tunnel_id")" >>"$tmp_file"
  printf '"shared_tunnel":%s,' "$shared_tunnel" >>"$tmp_file"
  if [[ -n "$auto_mode" ]]; then
    printf '"auto_mode":%s,' "$auto_mode" >>"$tmp_file"
  fi
  if [[ -n "$runtime_type" ]]; then
    printf '"runtime_type":"%s",' "$(json_escape "$runtime_type")" >>"$tmp_file"
  fi
  printf '"compose_dir":"%s",' "$(json_escape "$compose_dir")" >>"$tmp_file"
  if [[ -n "$ports_json" ]]; then
    printf '"ports":{%s},' "$ports_json" >>"$tmp_file"
  fi
  printf '"paths":{' >>"$tmp_file"
  printf '"config_yml":"%s",' "$(json_escape "$config_yml")" >>"$tmp_file"
  printf '"ports_json":"%s",' "$(json_escape "$ports_json_path")" >>"$tmp_file"
  printf '"compose_dir_file":"%s",' "$(json_escape "$compose_dir_file")" >>"$tmp_file"
  printf '"tunnel_name_file":"%s",' "$(json_escape "$tunnel_name_file")" >>"$tmp_file"
  printf '"tunnel_token_file":"%s",' "$(json_escape "$tunnel_token_file")" >>"$tmp_file"
  printf '"cloudflared_pid_file":"%s",' "$(json_escape "$cloudflared_pid_file")" >>"$tmp_file"
  printf '"cloudflared_log_file":"%s"' "$(json_escape "$cloudflared_log_file")" >>"$tmp_file"
  printf '},' >>"$tmp_file"
  if [[ -n "$runtime_json" ]]; then
    printf '"runtime":{%s},' "$runtime_json" >>"$tmp_file"
  fi
  printf '"updated_at":"%s"' "$(json_escape "$updated_at")" >>"$tmp_file"
  printf '}\n' >>"$tmp_file"

  chmod 0644 "$tmp_file"
  mv -f "$tmp_file" "$out_file"
}

cmd_bootstrap() {
  FB_BOOTSTRAP="true"
  if [[ "${FB_TRACE:-}" == "true" ]]; then
    set -x
  fi
  local user_ports="false"
  FB_USER_PORTS="false"
  local app_name=""
  local env_name=""
  local domain=""
  local site_port=""
  local api_port=""
  local auto_ports="false"
  local auto_detect_ports="true"
  local hosts_list=""
  local no_cache="false"
  local shared_tunnel="false"
  local print_env="true"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a|--app)
        app_name="$2"
        shift 2
        ;;
      -e|--env)
        env_name="$2"
        shift 2
        ;;
      -d|--domain)
        domain="$2"
        shift 2
        ;;
      -s|--site-port)
        site_port="$2"
        user_ports="true"
        shift 2
        ;;
      -i|--api-port)
        api_port="$2"
        user_ports="true"
        shift 2
        ;;
      -H|--hosts)
        hosts_list="$2"
        shift 2
        ;;
      --auto-ports)
        auto_ports="true"
        shift
        ;;
      --auto-detect-ports)
        auto_detect_ports="true"
        shift
        ;;
      --no-cache)
        no_cache="true"
        shift
        ;;
      --shared-tunnel)
        shared_tunnel="true"
        shift
        ;;
      --machine|--print-env)
        print_env="true"
        shift
        ;;
      --no-machine|--no-print-env)
        print_env="false"
        shift
        ;;
      -h|--help)
        bootstrap_help
        return 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  local manual_mode="false"
  if [[ "$user_ports" == "true" ]]; then
    manual_mode="true"
  fi
  if [[ -z "$env_name" && "$manual_mode" == "true" ]]; then
    env_name="prod"
    log_info "Manual mode: -e (or --env) not provided; defaulting to prod."
  fi
  if [[ -z "$env_name" ]]; then
    env_name="dev"
  fi

  local include_root="true"
  local include_api="false"
  local include_www="false"
  local hosts_override="false"
  if [[ -n "$hosts_list" ]]; then
    hosts_override="true"
    include_root="false"
    hosts_list="${hosts_list// /}"
    IFS=',' read -r -a host_items <<<"$hosts_list"
    if [[ "${#host_items[@]}" -eq 0 ]]; then
      die "Invalid --hosts list. Use root,api,www."
    fi
    for item in "${host_items[@]}"; do
      case "$item" in
        root) include_root="true" ;;
        api) include_api="true" ;;
        www) include_www="true" ;;
        *) die "Unknown --hosts entry: $item (use root,api,www)" ;;
      esac
    done
    if ! is_true "$include_root" && ! is_true "$include_api" && ! is_true "$include_www"; then
      die "At least one host must be set in --hosts (root,api,www)."
    fi
  fi

  resolve_context "$app_name" "$env_name" "$domain" "$site_port" "$api_port" "$auto_ports" "" "dev" "$include_api" "$include_www"
  HOSTNAME_ROOT="$include_root"
  if [[ "$hosts_override" == "true" ]]; then
    HOSTNAME_API="$include_api"
    HOSTNAME_WWW="$include_www"
  elif [[ "$manual_mode" == "true" ]]; then
    HOSTNAME_API="false"
    HOSTNAME_WWW="false"
  fi

  FB_USER_PORTS="$user_ports"
  log_info "Context: app=$APP_NAME env=$ENV_NAME domain=$DOMAIN_NAME"

  if [[ "$manual_mode" != "true" ]]; then
    if ! fb_compose_file >/dev/null 2>&1; then
      log_error "Auto mode expects docker-compose.yml or docker-compose.yaml in the current directory."
      log_error "If your app is already running, use Manual mode with -s (or --site-port) and -i (or --api-port)."
      exit 1
    fi
    local docker_ports
    docker_ports="$(docker_published_ports_for_app "$APP_NAME" || true)"
    if [[ -n "$docker_ports" ]]; then
      local has_site="false"
      local has_api="false"
      if echo "$docker_ports" | grep -qx "$SITE_PORT"; then
        has_site="true"
      fi
      if echo "$docker_ports" | grep -qx "$API_PORT"; then
        has_api="true"
      fi
      if [[ "$has_site" != "true" || "$has_api" != "true" ]]; then
        local docker_ports_list
        docker_ports_list="$(echo "$docker_ports" | paste -sd, -)"
        local rec_site rec_api
        local docker_count
        docker_count="$(echo "$docker_ports" | awk 'END{print NR}')"
        rec_site="$(echo "$docker_ports" | head -n1)"
        rec_api="$(echo "$docker_ports" | sed -n '2p')"
        if [[ -z "$rec_api" ]]; then
          rec_api="$rec_site"
        fi
        if is_true "$auto_detect_ports"; then
          if [[ "$docker_count" -le 2 ]]; then
            log_info "Auto-detect found Docker ports: $docker_ports_list"
            SITE_PORT="$rec_site"
            API_PORT="$rec_api"
            PORTS_SOURCE="docker"
            validate_ports "$SITE_PORT" "$API_PORT" "$PORTS_SOURCE"
            write_ports_json "$(ports_json_path "$APP_NAME" "$ENV_NAME")" "$SITE_PORT" "$API_PORT"
          else
            log_warn "Multiple Docker ports found for this app: $docker_ports_list"
            log_info "Choose ports explicitly: fb bootstrap -s <site> -i <api> (or --site-port/--api-port)"
          fi
        else
          log_warn "Docker ports detected ($docker_ports_list), but auto-detect is disabled."
          log_info "Choose ports explicitly: fb bootstrap -s $rec_site -i $rec_api (or --site-port/--api-port)"
        fi
      fi
    elif is_true "$auto_detect_ports"; then
      log_info "Auto-detect enabled; no Docker ports found yet. Will re-check after deploy."
    fi
  fi

  if [[ "$manual_mode" == "true" ]]; then
    cmd_doctor
    if is_true "$HOSTNAME_ROOT"; then
      if port_in_use "$SITE_PORT"; then
        log_info "Detected local service listening on port $SITE_PORT (expected)."
      else
        log_warn "Nothing is listening on localhost:$SITE_PORT. Start your app, then rerun fb bootstrap."
      fi
    fi
    if is_true "$HOSTNAME_API" && [[ "$API_PORT" != "$SITE_PORT" ]]; then
      if port_in_use "$API_PORT"; then
        log_info "Detected local service listening on port $API_PORT (expected)."
      else
        log_warn "Nothing is listening on localhost:$API_PORT. Start your app, then rerun fb bootstrap."
      fi
    fi
  else
    FB_BOOTSTRAP="true" cmd_doctor --ports --app "$APP_NAME" --env "$ENV_NAME" --domain "$DOMAIN_NAME" --site-port "$SITE_PORT" --api-port "$API_PORT"
    ensure_ports_available "$APP_NAME" "$ENV_NAME" "$AUTO_PORTS"
  fi

  log_ports_summary
  log_info "🔒 Safe by default: FB only creates/updates DNS records for this app's hostnames; other DNS is untouched."

  cf_ensure_zone "$DOMAIN_NAME"
  local tunnel_name="${APP_NAME}-${ENV_NAME}"
  if [[ "$shared_tunnel" != "true" ]]; then
    tunnel_name="${tunnel_name}-$(machine_suffix)"
  fi
  log_info "Using Cloudflare tunnel: $tunnel_name"
  local tunnel_id
  tunnel_id="$(cf_get_tunnel "$CF_ACCOUNT_ID" "$tunnel_name")"
  if [[ -z "$tunnel_id" ]]; then
    tunnel_id="$(cf_create_tunnel "$CF_ACCOUNT_ID" "$tunnel_name")"
    log_info "Created Cloudflare tunnel: $tunnel_name"
  else
    log_info "Cloudflare tunnel exists: $tunnel_name"
  fi
  cloudflare_write_tunnel_name "$APP_NAME" "$ENV_NAME" "$tunnel_name"

  local existing_conn_count
  existing_conn_count="$(cf_get_tunnel_connections "$CF_ACCOUNT_ID" "$tunnel_id" | jq -r 'length' 2>/dev/null || true)"
  if [[ -n "$existing_conn_count" && "$existing_conn_count" -gt 0 ]]; then
    log_warn "Tunnel $tunnel_name already has $existing_conn_count active connection(s)."
    log_warn "If another machine is still connected, responses may mix and cache inconsistently."
    log_warn "Stop other connectors or use a different app/env to isolate."
  fi

  local target="${tunnel_id}.cfargotunnel.com"
  if is_true "$HOSTNAME_ROOT"; then
    cf_ensure_dns_record "$CF_ZONE_ID" "$DOMAIN_NAME" "$target"
  fi
  if is_true "$HOSTNAME_API"; then
    cf_ensure_dns_record "$CF_ZONE_ID" "$API_HOSTNAME_OVERRIDE" "$target"
  fi
  if is_true "$HOSTNAME_WWW"; then
    cf_ensure_dns_record "$CF_ZONE_ID" "$WWW_HOSTNAME_OVERRIDE" "$target"
  fi
  if is_true "$no_cache"; then
    if is_true "$HOSTNAME_ROOT"; then
      if ! cf_ensure_cache_bypass_host "$CF_ZONE_ID" "$DOMAIN_NAME"; then
        log_warn "Failed to set Cloudflare cache bypass for $DOMAIN_NAME (need Cache Rules/Rulesets Edit)."
      fi
    fi
    if is_true "$HOSTNAME_API"; then
      if ! cf_ensure_cache_bypass_host "$CF_ZONE_ID" "$API_HOSTNAME_OVERRIDE"; then
        log_warn "Failed to set Cloudflare cache bypass for $API_HOSTNAME_OVERRIDE (need Cache Rules/Rulesets Edit)."
      fi
    fi
    if is_true "$HOSTNAME_WWW"; then
      if ! cf_ensure_cache_bypass_host "$CF_ZONE_ID" "$WWW_HOSTNAME_OVERRIDE"; then
        log_warn "Failed to set Cloudflare cache bypass for $WWW_HOSTNAME_OVERRIDE (need Cache Rules/Rulesets Edit)."
      fi
    fi
  fi

  local ingress_rules
  ingress_rules="$(build_ingress_rules "$DOMAIN_NAME" "$SITE_PORT" "$API_PORT" "$HOSTNAME_ROOT" "$HOSTNAME_API" "$HOSTNAME_WWW" "$API_HOSTNAME_OVERRIDE" "$WWW_HOSTNAME_OVERRIDE")"
  render_cloudflared_config "$APP_NAME" "$ENV_NAME" "$tunnel_id" "$ingress_rules" \
    "$FB_ROOT/templates/cloudflared/config.yml.tmpl"

  local token
  token="$(cloudflare_get_token_or_file "$APP_NAME" "$ENV_NAME" "$CF_ACCOUNT_ID" "$tunnel_id")"

  local app_deployed="false"
  local tunnel_started="false"
  if [[ "$manual_mode" == "true" ]]; then
    log_info "Manual mode: FB does not manage your app process. Start your app separately."
    log_info "Starting cloudflared tunnel"
    cloudflare_run_tunnel "$APP_NAME" "$ENV_NAME" "$token"
    tunnel_started="true"
  elif deploy_app "$ENV_NAME"; then
    app_deployed="true"
    if [[ -n "$SITE_PORT" ]]; then
      local local_url="http://localhost:$SITE_PORT"
      wait_for_http_ready "$local_url" "Local app" || true
      local ready_url
      ready_url="$(resolve_ready_url "$local_url")"
      if [[ "$ready_url" != "$local_url" ]]; then
        wait_for_http_ready "$ready_url" "Local app (ready)" "true" || true
      fi
    fi
    log_info "Starting cloudflared tunnel"
    cloudflare_run_tunnel "$APP_NAME" "$ENV_NAME" "$token"
    tunnel_started="true"
  else
    log_warn "App deploy failed; starting tunnel anyway."
    log_info "Starting cloudflared tunnel"
    cloudflare_run_tunnel "$APP_NAME" "$ENV_NAME" "$token"
    tunnel_started="true"
  fi

  if [[ "$manual_mode" != "true" ]] && is_true "$auto_detect_ports"; then
    local post_ports
    post_ports="$(docker_published_ports_for_app "$APP_NAME" || true)"
    if [[ -n "$post_ports" ]]; then
      local has_site="false"
      local has_api="false"
      if echo "$post_ports" | grep -qx "$SITE_PORT"; then
        has_site="true"
      fi
      if echo "$post_ports" | grep -qx "$API_PORT"; then
        has_api="true"
      fi
      if [[ "$has_site" != "true" || "$has_api" != "true" ]]; then
        local post_list
        post_list="$(echo "$post_ports" | paste -sd, -)"
        local post_site post_api
        local post_count
        post_count="$(echo "$post_ports" | awk 'END{print NR}')"
        post_site="$(echo "$post_ports" | head -n1)"
        post_api="$(echo "$post_ports" | sed -n '2p')"
        if [[ -z "$post_api" ]]; then
          post_api="$post_site"
        fi
        if [[ "$post_count" -le 2 ]]; then
          log_info "Auto-detect confirmed Docker ports after deploy: $post_list"
          log_info "Updating ports to $post_site/$post_api and restarting tunnel."
          SITE_PORT="$post_site"
          API_PORT="$post_api"
          PORTS_SOURCE="docker"
          validate_ports "$SITE_PORT" "$API_PORT" "$PORTS_SOURCE"
          write_ports_json "$(ports_json_path "$APP_NAME" "$ENV_NAME")" "$SITE_PORT" "$API_PORT"
          local ingress_rules
          ingress_rules="$(build_ingress_rules "$DOMAIN_NAME" "$SITE_PORT" "$API_PORT" "$HOSTNAME_ROOT" "$HOSTNAME_API" "$HOSTNAME_WWW" "$API_HOSTNAME_OVERRIDE" "$WWW_HOSTNAME_OVERRIDE")"
          render_cloudflared_config "$APP_NAME" "$ENV_NAME" "$tunnel_id" "$ingress_rules" \
            "$FB_ROOT/templates/cloudflared/config.yml.tmpl"
          if [[ "$tunnel_started" == "true" ]]; then
            cloudflare_stop_tunnel "$APP_NAME" "$ENV_NAME" || true
            cloudflare_run_tunnel "$APP_NAME" "$ENV_NAME" "$token"
          else
            log_info "Tunnel will start with updated config."
          fi
        else
          log_warn "Multiple Docker ports found after deploy: $post_list"
          log_info "Choose ports explicitly: fb bootstrap -s <site> -i <api> (or --site-port/--api-port)"
        fi
      fi
    fi
  fi

  if [[ "$app_deployed" == "true" ]]; then
    if [[ -n "$DOMAIN_NAME" ]]; then
      local cf_url="https://$DOMAIN_NAME"
      if [[ "${FB_SKIP_READY:-}" == "1" ]]; then
        log_info "Skipping Cloudflare readiness check (FB_SKIP_READY=1)."
      else
        log_info "Waiting for Cloudflare URL readiness (up to 60s): $cf_url"
        wait_for_http_ready "$cf_url" "Cloudflare" "true" || true
      fi
      local cf_ready_url
      cf_ready_url="$(resolve_ready_url "$cf_url")"
    fi
  elif [[ "$manual_mode" != "true" ]]; then
    log_warn "Skipping readiness checks (app not deployed)."
  fi
  local from_main="https://$DOMAIN_NAME"
  local to_main="localhost:$SITE_PORT"
  local from_api="https://$API_HOSTNAME_OVERRIDE"
  local to_api="localhost:$API_PORT"
  local from_www="https://$WWW_HOSTNAME_OVERRIDE"
  local to_www="localhost:$SITE_PORT"
  local w1=0
  if is_true "$HOSTNAME_ROOT"; then
    w1="${#from_main}"
  fi
  if is_true "$HOSTNAME_API" && [[ "${#from_api}" -gt "$w1" ]]; then
    w1="${#from_api}"
  fi
  if is_true "$HOSTNAME_WWW" && [[ "${#from_www}" -gt "$w1" ]]; then
    w1="${#from_www}"
  fi
  log_info "✅ Public exposure ($APP_NAME/$ENV_NAME):"
  if is_true "$HOSTNAME_ROOT"; then
    printf 'INFO:   %-*s -> %s\n' "$w1" "$from_main" "$to_main"
  fi
  if is_true "$HOSTNAME_API"; then
    printf 'INFO:   %-*s -> %s\n' "$w1" "$from_api" "$to_api"
  fi
  if is_true "$HOSTNAME_WWW"; then
    printf 'INFO:   %-*s -> %s\n' "$w1" "$from_www" "$to_www"
  fi
  log_live_urls "$DOMAIN_NAME"
  log_info "🧭 Next steps"
  log_info "  Stop:   fb app down ${APP_NAME}/${ENV_NAME}"
  log_info "  Status: fb app status ${APP_NAME}/${ENV_NAME}"
  log_info "  Logs:   $(cloudflare_log_path "$APP_NAME" "$ENV_NAME")"
  log_info "App published. Next: fb app down ${APP_NAME}/${ENV_NAME} to unpublish; fb app list"

  local zone_apex="${CF_ZONE_NAME:-${DOMAIN_ROOT:-${DOMAIN_NAME:-}}}"
  local fqdns_list
  fqdns_list="$(build_bootstrap_fqdns_list || true)"
  if [[ -z "$fqdns_list" ]]; then
    log_warn "No FQDNs resolved for state.json; writing fqdns=[]."
  fi
  local compose_dir=""
  local compose_dir_file
  compose_dir_file="$(cloudflare_compose_dir_path "$APP_NAME" "$ENV_NAME")"
  if compose_dir="$(read_compose_dir_value "$compose_dir_file")"; then
    :
  else
    compose_dir="$PWD"
  fi
  compose_dir="$(fb_abs_path "$compose_dir")"
  local ports_json=""
  local ports_file
  ports_file="$(ports_json_path "$APP_NAME" "$ENV_NAME")"
  if ports_vals="$(read_ports_json "$ports_file")"; then
    local ports_site ports_api
    ports_site="${ports_vals%% *}"
    ports_api="${ports_vals##* }"
    ports_json="\"site\":${ports_site},\"api\":${ports_api}"
  elif [[ -f "$ports_file" ]]; then
    log_warn "Failed to parse ports.json for state.json; omitting ports."
  fi
  local auto_mode="true"
  local runtime_type="docker-compose"
  if [[ "$manual_mode" == "true" ]]; then
    auto_mode="false"
    runtime_type="manual"
  fi
  local state_dir
  state_dir="$(fb_abs_path "$FB_HOME/$APP_NAME/$ENV_NAME")"
  write_state_json "$state_dir" "$APP_NAME" "$ENV_NAME" "$zone_apex" "$tunnel_name" "$tunnel_id" "$shared_tunnel" "$fqdns_list" "$compose_dir" "$ports_json" "$auto_mode" "$runtime_type"

  if [[ "$print_env" == "true" ]]; then
    local fqdns
    fqdns="$(build_bootstrap_fqdns)"
    print_fb_env_lines "$APP_NAME" "$ENV_NAME" "$zone_apex" "$tunnel_name" "$tunnel_id" "$fqdns" "$state_dir"
  fi
}
