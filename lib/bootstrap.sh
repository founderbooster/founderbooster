#!/usr/bin/env bash
set -euo pipefail

bootstrap_help() {
  cat <<'EOF'
Usage: fb bootstrap [options]

Options:
  --app NAME         Override app name
  --env ENV          Environment (dev|staging|prod)
  --domain DOMAIN    Override domain
  --site-port PORT   Override site port
  --api-port PORT    Override api port
  --hosts LIST       Comma list: root,api,www
  --auto-ports       Auto-select next available port pair
  --auto-detect-ports  Auto-detect Docker ports (default: on)
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
  local tries=30
  local delay=2
  local i
  for ((i=1; i<=tries; i++)); do
    local code
    if code="$(curl -s -o /dev/null -w "%{http_code}" "$url")"; then
      :
    else
      code="000"
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

cmd_bootstrap() {
  FB_BOOTSTRAP="true"
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

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --app)
        app_name="$2"
        shift 2
        ;;
      --env)
        env_name="$2"
        shift 2
        ;;
      --domain)
        domain="$2"
        shift 2
        ;;
      --site-port)
        site_port="$2"
        user_ports="true"
        shift 2
        ;;
      --api-port)
        api_port="$2"
        user_ports="true"
        shift 2
        ;;
      --hosts)
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
    log_info "Manual mode: --env not provided; defaulting to prod."
  fi
  if [[ -z "$env_name" ]]; then
    env_name="dev"
  fi

  local include_root="true"
  local include_api="true"
  local include_www="true"
  local hosts_override="false"
  if [[ -n "$hosts_list" ]]; then
    hosts_override="true"
    include_root="false"
    include_api="false"
    include_www="false"
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
  elif [[ "$manual_mode" == "true" ]]; then
    include_api="false"
    include_www="false"
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
    if [[ ! -f "$PWD/docker-compose.yml" ]]; then
      log_error "Auto mode expects docker-compose.yml in the current directory."
      log_error "If your app is already running, use Manual mode with --site-port (and --api-port)."
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
            log_info "Choose ports explicitly: fb bootstrap --site-port <site> --api-port <api>"
          fi
        else
          log_warn "Docker ports detected ($docker_ports_list), but auto-detect is disabled."
          log_info "Choose ports explicitly: fb bootstrap --site-port $rec_site --api-port $rec_api"
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
  local tunnel_id
  tunnel_id="$(cf_get_tunnel "$CF_ACCOUNT_ID" "$tunnel_name")"
  if [[ -z "$tunnel_id" ]]; then
    tunnel_id="$(cf_create_tunnel "$CF_ACCOUNT_ID" "$tunnel_name")"
    log_info "Created Cloudflare tunnel: $tunnel_name"
  else
    log_info "Cloudflare tunnel exists: $tunnel_name"
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

  local ingress_rules
  ingress_rules="$(build_ingress_rules "$DOMAIN_NAME" "$SITE_PORT" "$API_PORT" "$HOSTNAME_ROOT" "$HOSTNAME_API" "$HOSTNAME_WWW" "$API_HOSTNAME_OVERRIDE" "$WWW_HOSTNAME_OVERRIDE")"
  render_cloudflared_config "$APP_NAME" "$ENV_NAME" "$tunnel_id" "$ingress_rules" \
    "$FB_ROOT/templates/cloudflared/config.yml.tmpl"

  local token
  token="$(cloudflare_get_token_or_file "$APP_NAME" "$ENV_NAME" "$CF_ACCOUNT_ID" "$tunnel_id")"

  log_info "Starting cloudflared tunnel"
  cloudflare_run_tunnel "$APP_NAME" "$ENV_NAME" "$token"

  local app_deployed="false"
  if [[ "$manual_mode" == "true" ]]; then
    log_info "Manual mode: FB does not manage your app process. Start your app separately."
  elif deploy_app "$ENV_NAME"; then
    app_deployed="true"
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
          cloudflare_stop_tunnel "$APP_NAME" "$ENV_NAME" || true
          cloudflare_run_tunnel "$APP_NAME" "$ENV_NAME" "$token"
        else
          log_warn "Multiple Docker ports found after deploy: $post_list"
          log_info "Choose ports explicitly: fb bootstrap --site-port <site> --api-port <api>"
        fi
      fi
    fi
  fi

  if [[ "$app_deployed" == "true" ]]; then
    if [[ -n "$SITE_PORT" ]]; then
      wait_for_http_ready "http://localhost:$SITE_PORT" "Local app" || true
    fi
    if [[ -n "$DOMAIN_NAME" ]]; then
      wait_for_http_ready "https://$DOMAIN_NAME" "Cloudflare" || true
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
}
