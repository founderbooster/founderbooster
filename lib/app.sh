#!/usr/bin/env bash
set -euo pipefail

app_help() {
  cat <<'EOF'
Usage: fb app <command>

Commands:
  list            List app/env environments
  down            Stop a tunnel and optionally stop the app stack
  status          Show status for an app/env
EOF
}

app_down_help() {
  cat <<'EOF'
Usage: fb app down [options] [app[/env]]

Options:
  --app NAME          App name (defaults to repo or config)
  --env ENV           Environment (default: dev)
  --tunnel-only       Only stop the tunnel
  --purge             Remove local app state (~/.founderbooster/<app>/<env>/)

Examples:
  fb app down
  fb app down my-app
  fb app down my-app/dev
  fb app down --app my-app --env dev --purge
EOF
}

app_status_help() {
  cat <<'EOF'
Usage: fb app status [options] [app[/env]]

Options:
  --app NAME          App name (defaults to repo or config)
  --env ENV           Environment (default: dev)
  --all               Show status for all environments of an app
  --hosts LIST        Comma list: root,api,www
EOF
}

app_repo_matches() {
  local app="$1"
  local cfg_app=""
  cfg_app="$(config_app_name || true)"
  local repo_app
  repo_app="$(safe_basename "$PWD")"

  if [[ -n "$cfg_app" && "$cfg_app" == "$app" ]]; then
    return 0
  fi
  if [[ "$repo_app" == "$app" ]]; then
    return 0
  fi
  return 1
}

stop_app_stack() {
  local app="$1"
  local env="$2"
  if [[ -f "$PWD/docker-compose.yml" ]]; then
    local project="${COMPOSE_PROJECT_NAME:-}"
    if [[ -z "$project" ]]; then
      project="$(fb_compose_project_name "$app" "$env")"
    fi
    if [[ -n "$project" ]]; then
      log_info "Running docker compose down (project: $project)"
      local output
      if output="$(COMPOSE_PROJECT_NAME="$project" docker compose down 2>&1)"; then
        if [[ "$output" == *"No resource found"* ]]; then
          log_info "Docker compose: no resources to stop."
          echo "$output" | sed '/No resource found/d'
        else
          printf '%s\n' "$output"
        fi
        return 0
      fi
      log_warn "Docker compose down failed."
      printf '%s\n' "$output" >&2
      return 0
    fi
    log_info "Running docker compose down"
    local output
    if output="$(docker compose down 2>&1)"; then
      if [[ "$output" == *"No resource found"* ]]; then
        log_info "Docker compose: no resources to stop."
        echo "$output" | sed '/No resource found/d'
      else
        printf '%s\n' "$output"
      fi
      return 0
    fi
    log_warn "Docker compose down failed."
    printf '%s\n' "$output" >&2
    return 0
  fi
  return 1
}

cmd_app_down() {
  local app_name=""
  local env_name="dev"
  local tunnel_only="false"
  local purge="false"
  local repo_hint="false"

  local selector=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --app)
        if [[ -z "${2:-}" || "${2:0:1}" == "-" ]]; then
          die "Usage: fb app down [options] [app[/env]]"
        fi
        app_name="$2"
        shift 2
        ;;
      --env)
        if [[ -z "${2:-}" || "${2:0:1}" == "-" ]]; then
          die "Usage: fb app down [options] [app[/env]]"
        fi
        env_name="$2"
        shift 2
        ;;
      --tunnel-only)
        tunnel_only="true"
        shift
        ;;
      --purge)
        purge="true"
        shift
        ;;
      -h|--help)
        app_down_help
        return 0
        ;;
      -*)
        die "Unknown option: $1"
        ;;
      *)
        if [[ -z "$selector" ]]; then
          selector="$1"
          shift
        else
          die "Unexpected argument: $1"
        fi
        ;;
    esac
  done

  if [[ -n "$selector" ]]; then
    if [[ "$selector" == *"/"* ]]; then
      app_name="${selector%%/*}"
      env_name="${selector##*/}"
    else
      app_name="$selector"
    fi
  fi

  fb_config_init
  if [[ -z "$app_name" ]]; then
    app_name="$(config_app_name)"
    if [[ -n "$app_name" ]]; then
      repo_hint="true"
    fi
  fi
  if [[ -z "$app_name" ]]; then
    if [[ -f "$PWD/docker-compose.yml" ]]; then
      app_name="$(safe_basename "$PWD")"
      repo_hint="true"
    fi
  fi

  if [[ -z "$selector" && "$repo_hint" != "true" ]]; then
    local entries
    entries="$(cmd_list 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$entries" == "1" ]]; then
      local entry
      entry="$(cmd_list | head -n1)"
      if [[ "$entry" == *"/"* ]]; then
        app_name="${entry%%/*}"
        env_name="$(echo "$entry" | awk -F'/' '{print $2}' | awk '{print $1}')"
      fi
    elif [[ -z "$app_name" && "$entries" -gt 1 ]]; then
      die "Multiple environments found. Use: fb app down <app>/<env>"
    fi
  fi

  if [[ -z "$app_name" ]]; then
    app_name="$(safe_basename "$PWD")"
  fi

  log_info "Stopping: app=$app_name env=$env_name"
  cloudflare_stop_tunnel "$app_name" "$env_name" || true

  if is_true "$tunnel_only"; then
    return 0
  fi

  if ! app_repo_matches "$app_name"; then
    log_warn "Current directory does not match app '$app_name'; skipping app stop."
    log_warn "Run from the app repo or pass --tunnel-only."
    return 0
  fi

  if ! stop_app_stack "$app_name" "$env_name"; then
    log_warn "No docker-compose.yml found."
  fi

  log_info "✅ Stopped: $app_name/$env_name"

  if is_true "$purge"; then
    local state_dir="$FB_HOME/$app_name/$env_name"
    local config_path
    config_path="$(cloudflare_config_path "$app_name" "$env_name")"
    local tunnel_name_file
    tunnel_name_file="$(cloudflare_tunnel_name_path "$app_name" "$env_name")"
    local hostnames=""
    if [[ -f "$config_path" ]]; then
      hostnames="$(awk -F': ' '/hostname:/{print $2}' "$config_path" | paste -sd, -)"
    fi
    local tunnel_name=""
    if [[ -f "$tunnel_name_file" ]]; then
      tunnel_name="$(cat "$tunnel_name_file")"
    fi
    if [[ -z "$tunnel_name" ]]; then
      tunnel_name="${app_name}-${env_name}"
    fi
    if [[ -d "$state_dir" ]]; then
      rm -rf "$state_dir"
      log_info "Removed local state: $state_dir"
    else
      log_info "No local state found to remove: $state_dir."
    fi
    log_info "Cloudflare resources left unchanged."
    if [[ -n "$hostnames" ]]; then
      log_info "To remove them manually: delete tunnel \"$tunnel_name\" and DNS records for $hostnames."
    else
      log_info "To remove them manually: delete tunnel \"$tunnel_name\" and DNS records for this app/env."
    fi
  fi
}

cmd_app_status() {
  local app_name=""
  local env_name="dev"
  local selector=""
  local env_override="false"
  local show_all="false"
  local hosts_list=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --app)
        if [[ -z "${2:-}" || "${2:0:1}" == "-" ]]; then
          die "Usage: fb app status [options] [app[/env]]"
        fi
        app_name="$2"
        shift 2
        ;;
      --env)
        if [[ -z "${2:-}" || "${2:0:1}" == "-" ]]; then
          die "Usage: fb app status [options] [app[/env]]"
        fi
        env_name="$2"
        env_override="true"
        shift 2
        ;;
      --all)
        show_all="true"
        shift
        ;;
      --hosts)
        hosts_list="$2"
        shift 2
        ;;
      -h|--help)
        app_status_help
        return 0
        ;;
      -*)
        die "Unknown option: $1"
        ;;
      *)
        if [[ -z "$selector" ]]; then
          selector="$1"
          shift
        else
          die "Unexpected argument: $1"
        fi
        ;;
    esac
  done

  if [[ -n "$selector" ]]; then
    if [[ "$selector" == *"/"* ]]; then
      app_name="${selector%%/*}"
      env_name="${selector##*/}"
      env_override="true"
    else
      app_name="$selector"
    fi
  fi

  fb_config_init
  if [[ -z "$app_name" ]]; then
    app_name="$(config_app_name)"
  fi
  if [[ -z "$app_name" ]]; then
    app_name="$(safe_basename "$PWD")"
  fi

  if is_true "$show_all"; then
    local app_dir="$FB_HOME/$app_name"
    if [[ ! -d "$app_dir" ]]; then
      log_warn "No environments found for $app_name."
      return 1
    fi
    local envs
    envs="$(find "$app_dir" -maxdepth 2 -type f -name config.yml -o -type f -name ports.json -o -type f -name tunnel.token -o -type f -name cloudflared.pid 2>/dev/null | awk -F'/' '{print $(NF-1)}' | sort -u)"
    if [[ -z "$envs" ]]; then
      log_warn "No environments found for $app_name."
      return 1
    fi
    while IFS= read -r env; do
      [[ -z "$env" ]] && continue
      if [[ -n "$hosts_list" ]]; then
        cmd_app_status --app "$app_name" --env "$env" --hosts "$hosts_list" || true
      else
        cmd_app_status --app "$app_name" --env "$env" || true
      fi
    done <<<"$envs"
    return 0
  fi

  log_info "App status: $app_name/$env_name"

  if [[ "$env_override" != "true" ]]; then
    local app_dir="$FB_HOME/$app_name"
    if [[ -d "$app_dir" ]]; then
      local envs
      envs="$(find "$app_dir" -maxdepth 2 -type f -name config.yml -o -type f -name ports.json -o -type f -name tunnel.token -o -type f -name cloudflared.pid 2>/dev/null | awk -F'/' '{print $(NF-1)}' | sort -u)"
      local env_count
      env_count="$(echo "$envs" | awk 'NF{c++} END{print c+0}')"
      if [[ "$env_count" -gt 1 ]]; then
        if [[ "$show_all" != "true" ]]; then
          while IFS= read -r env; do
            [[ -z "$env" ]] && continue
            if [[ -n "$hosts_list" ]]; then
              cmd_app_status --app "$app_name" --env "$env" --hosts "$hosts_list" || true
            else
              cmd_app_status --app "$app_name" --env "$env" || true
            fi
          done <<<"$envs"
          return 0
        fi
        local docker_ports
        docker_ports="$(docker_published_ports_for_app "$app_name" "$PWD" || true)"
        if [[ -n "$docker_ports" ]]; then
          local chosen_env=""
          while IFS= read -r env; do
            [[ -z "$env" ]] && continue
            local ports_file
            ports_file="$(ports_json_path "$app_name" "$env")"
            if [[ -f "$ports_file" ]]; then
              local ps pa
              read -r ps pa <<<"$(read_ports_json "$ports_file" || true)"
              if [[ -n "$ps" ]] && echo "$docker_ports" | grep -qx "$ps"; then
                chosen_env="$env"
                break
              fi
            fi
            local cfg
            cfg="$(cloudflare_config_path "$app_name" "$env")"
            if [[ -f "$cfg" ]]; then
              local cfg_ports
              cfg_ports="$(awk '/service: http:\/\/localhost:/{print $2}' "$cfg" | awk -F: '{print $3}' | sort -u)"
              if [[ -n "$cfg_ports" ]] && comm -12 <(echo "$cfg_ports") <(echo "$docker_ports") >/dev/null 2>&1; then
                chosen_env="$env"
                break
              fi
            fi
          done <<<"$envs"
          if [[ -n "$chosen_env" ]]; then
            env_name="$chosen_env"
          else
            log_warn "Multiple environments found; use --env to select."
          fi
        else
          log_warn "Multiple environments found; use --env to select."
        fi
      fi
    fi
  fi

  local config_path
  config_path="$(cloudflare_config_path "$app_name" "$env_name")"
  local ports_path
  ports_path="$(ports_json_path "$app_name" "$env_name")"
  local token_path
  token_path="$(cloudflare_token_path "$app_name" "$env_name")"
  local pid_path
  pid_path="$(cloudflare_pid_path "$app_name" "$env_name")"
  if [[ ! -f "$config_path" && ! -f "$ports_path" && ! -f "$token_path" && ! -f "$pid_path" ]]; then
    log_warn "No local state found for $app_name/$env_name."
    log_warn "Run: fb bootstrap --env $env_name --domain <domain>"
    local docker_ports
    docker_ports="$(docker_published_ports_for_app "$app_name" "$PWD" || true)"
    if [[ -n "$docker_ports" ]]; then
      log_info "Ports published by Docker (current directory only): $(echo "$docker_ports" | paste -sd, -)"
    fi
    return 1
  fi

  local config_site config_api
  config_site="$(config_get "ports.$env_name.site")"
  config_api="$(config_get "ports.$env_name.api")"
  resolve_ports "$app_name" "$env_name" "" "" "$config_site" "$config_api"

  local domain
  domain="$(config_get "domains.$env_name")"
  if [[ -n "$domain" ]]; then
    resolve_domain_for_env "$domain" "$env_name"
  fi
  local cf_config_path
  cf_config_path="$(cloudflare_config_path "$app_name" "$env_name")"
  local resolved_domain=""
  if [[ -n "${DOMAIN_NAME:-}" ]]; then
    resolved_domain="$DOMAIN_NAME"
  elif [[ -f "$cf_config_path" ]]; then
    resolved_domain="$(awk -F': ' '/hostname:/{print $2; exit}' "$cf_config_path")"
  fi
  local config_path="$CONFIG_FILE"
  if [[ -n "$config_path" ]]; then
    log_info "Config: $config_path"
    local cfg_app cfg_domain cfg_site cfg_api cfg_api_host cfg_www_host
    cfg_app="$(config_app_name || true)"
    cfg_domain="$(config_get "domains.$env_name")"
    cfg_site="$(config_get "ports.$env_name.site")"
    cfg_api="$(config_get "ports.$env_name.api")"
    cfg_api_host="$(config_get "hostnames.api")"
    cfg_www_host="$(config_get "hostnames.www")"
    local summary_parts=()
    if [[ -n "$cfg_app" ]]; then
      summary_parts+=("app=$cfg_app")
    fi
    if [[ -n "$resolved_domain" ]]; then
      summary_parts+=("domain=$resolved_domain")
    fi
    if [[ -n "$cfg_site" || -n "$cfg_api" ]]; then
      summary_parts+=("ports=${cfg_site:-?}/${cfg_api:-?}")
    fi
    if [[ -n "$cfg_api_host" || -n "$cfg_www_host" ]]; then
      local hosts_summary=""
      if [[ -n "$cfg_api_host" ]]; then
        hosts_summary="api=$cfg_api_host"
      fi
      if [[ -n "$cfg_www_host" ]]; then
        if [[ -n "$hosts_summary" ]]; then
          hosts_summary="$hosts_summary,www=$cfg_www_host"
        else
          hosts_summary="www=$cfg_www_host"
        fi
      fi
      summary_parts+=("hostnames=$hosts_summary")
    fi
    if [[ "${#summary_parts[@]}" -gt 0 ]]; then
      log_info "Config values: ${summary_parts[*]}"
    fi
  fi

  local include_root="true"
  local include_api="true"
  local include_www="true"
  if [[ -n "$hosts_list" ]]; then
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
  else
    local cfg_api cfg_www
    cfg_api="$(config_get "hostnames.api")"
    cfg_www="$(config_get "hostnames.www")"
    if [[ -n "$cfg_api" ]] && ! is_true "$cfg_api"; then
      include_api="false"
    fi
    if [[ -n "$cfg_www" ]] && ! is_true "$cfg_www"; then
      include_www="false"
    fi
  fi

  local pid_file
  pid_file="$(cloudflare_pid_path "$app_name" "$env_name")"
  if cloudflare_tunnel_running "$pid_file"; then
    log_info "cloudflared running (pid $(cat "$pid_file"))."
  else
    log_warn "cloudflared not running."
  fi

  local tunnel_id=""
  local config
  config="$cf_config_path"
  if [[ -f "$config" ]]; then
    tunnel_id="$(awk -F': ' '/^tunnel:/{print $2}' "$config")"
  fi
  if [[ -n "$tunnel_id" ]]; then
    log_info "Tunnel ID: $tunnel_id"
  else
    log_warn "Tunnel ID not found."
  fi

  log_info "Resolved ports: site=$SITE_PORT api=$API_PORT (source=$PORTS_SOURCE)"
  if [[ -n "${DOMAIN_NAME:-}" ]]; then
    if is_true "$include_root"; then
      log_info "Live: https://$DOMAIN_NAME"
    fi
    if is_true "$include_api"; then
      log_info "Live API: https://$API_HOSTNAME_OVERRIDE"
    fi
    if is_true "$include_www"; then
      log_info "Live WWW: https://$WWW_HOSTNAME_OVERRIDE"
    fi
  elif [[ -f "$config" ]]; then
    local hostnames
    hostnames="$(awk -F': ' '/hostname:/{print $2}' "$config" | awk 'NF')"
    if [[ -n "$hostnames" ]]; then
      while IFS= read -r host; do
        [[ -z "$host" ]] && continue
        log_info "Live: https://$host"
      done <<<"$hostnames"
    fi
  fi

  local docker_ports
  docker_ports="$(docker_published_ports_for_app "$app_name" "$PWD" || true)"
  if [[ -n "$docker_ports" ]]; then
    log_info "Ports published by Docker (current directory only): $(echo "$docker_ports" | paste -sd, -)"
  fi

  local ports_file
  ports_file="$(ports_json_path "$app_name" "$env_name")"
  if [[ -f "$ports_file" ]]; then
    log_info "Ports override: $ports_file"
  fi
}

cmd_app() {
  local sub="${1:-}"
  case "$sub" in
    list)
      shift
      cmd_list "$@"
      ;;
    down)
      shift
      cmd_app_down "$@"
      ;;
    status)
      shift
      cmd_app_status "$@"
      ;;
    help|-h|--help|"")
      app_help
      ;;
    *)
      die "Unknown app command: $sub"
      ;;
  esac
}
