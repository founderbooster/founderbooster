#!/usr/bin/env bash
set -euo pipefail

app_help() {
  cat <<'EOF'
Usage: fb app <command>

Commands:
  list            List app/env environments
  up              Re-publish a bootstrapped app/env
  down            Stop a tunnel and optionally stop the app stack
  status          Show status for an app/env
EOF
}

app_up_help() {
  cat <<'EOF'
Usage: fb app up [options] [app[/env]]

Options:
  -a, --app NAME          App name (defaults to repo or config)
  -e, --env ENV           Environment (default: dev)
  --start-runtime     Attempt to start local runtime (docker compose up -d)

Examples:
  fb app up
  fb app up my-app
  fb app up my-app/dev
  fb app up --app my-app --env dev
EOF
}

app_down_help() {
  cat <<'EOF'
Usage: fb app down [options] [app[/env]]

Options:
  -a, --app NAME          App name (defaults to repo or config)
  -e, --env ENV           Environment (default: dev)
  --tunnel-only       Alias for --unpublish-only
  --unpublish-only    Stop connector + remove DNS only
  --stop-runtime      Also stop local runtime (docker compose down)
  --purge             Remove local app state (~/.founderbooster/<app>/<env>/)
  --force             Force delete shared tunnel on purge

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
  -a, --app NAME          App name (defaults to repo or config)
  -e, --env ENV           Environment (default: dev)
  --all               Show status for all environments of an app
  -H, --hosts LIST        Comma list: root,api,www
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
  local workdir="${3:-$PWD}"
  if [[ -f "$workdir/docker-compose.yml" || -f "$workdir/docker-compose.yaml" ]]; then
    local project="${COMPOSE_PROJECT_NAME:-}"
    if [[ -z "$project" ]]; then
      project="$(fb_compose_project_name "$app" "$env")"
    fi
    if [[ -n "$project" ]]; then
      log_info "Running docker compose down (project: $project)"
      local output
      if output="$(cd "$workdir" && COMPOSE_PROJECT_NAME="$project" docker compose down 2>&1)"; then
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
    if output="$(cd "$workdir" && docker compose down 2>&1)"; then
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

state_json_path() {
  local app="$1"
  local env="$2"
  echo "$FB_HOME/$app/$env/state.json"
}

state_json_valid() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return 1
  fi
  jq -e . "$file" >/dev/null 2>&1
}

state_json_get() {
  local file="$1"
  local key="$2"
  jq -r "$key // empty" "$file" 2>/dev/null || true
}

state_json_get_array() {
  local file="$1"
  local key="$2"
  jq -r "$key[]?" "$file" 2>/dev/null || true
}

state_json_get_bool() {
  local file="$1"
  local key="$2"
  jq -r "$key // false" "$file" 2>/dev/null || echo "false"
}

read_config_hostnames() {
  local config="$1"
  if [[ -f "$config" ]]; then
    awk -F': ' '/hostname:/{print $2}' "$config" | awk 'NF'
  fi
}

read_config_tunnel_id() {
  local config="$1"
  if [[ -f "$config" ]]; then
    awk -F': ' '/^tunnel:/{print $2; exit}' "$config" | awk 'NF'
  fi
}

update_config_tunnel_id() {
  local config="$1"
  local tunnel_id="$2"
  if [[ ! -f "$config" || -z "$tunnel_id" ]]; then
    return 1
  fi
  local tmp="${config}.tmp"
  awk -v tid="$tunnel_id" '
    NR==1 && $1=="tunnel:" {$2=tid; print; next}
    NR==1 && $0 ~ /^tunnel:/ {print "tunnel: " tid; next}
    {print}
  ' "$config" >"$tmp"
  mv -f "$tmp" "$config"
}

normalize_fqdns_list() {
  awk 'NF' | sort -u
}

runtime_is_running() {
  local pid_file="$1"
  local config_path="$2"
  if [[ ! -f "$pid_file" ]]; then
    return 1
  fi
  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    return 1
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    return 1
  fi
  local cmd=""
  cmd="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  if [[ -z "$cmd" ]]; then
    return 1
  fi
  if [[ "$cmd" != *cloudflared* ]]; then
    return 1
  fi
  if [[ -n "$config_path" && "$cmd" != *"--config $config_path"* ]]; then
    return 1
  fi
  return 0
}

stop_connector_for_env() {
  local app="$1"
  local env="$2"
  local pid_file="$3"
  local config_path="$4"
  if runtime_is_running "$pid_file" "$config_path"; then
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
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
        return 0
      fi
      log_info "Stopped cloudflared (pid $pid)."
      rm -f "$pid_file"
      return 0
    fi
  fi
  local existing_pid=""
  if [[ -n "$config_path" ]] && existing_pid="$(cloudflare_find_pid_by_config "$config_path")"; then
    if kill -0 "$existing_pid" 2>/dev/null; then
      kill "$existing_pid" 2>/dev/null || true
      rm -f "$pid_file"
      log_info "Stopped cloudflared (pid $existing_pid)."
      return 0
    fi
  fi
  cloudflare_stop_tunnel "$app" "$env" || true
  return 0
}

start_app_stack() {
  local app="$1"
  local env="$2"
  local workdir="${3:-$PWD}"
  if [[ -f "$workdir/docker-compose.yml" || -f "$workdir/docker-compose.yaml" ]]; then
    local project="${COMPOSE_PROJECT_NAME:-}"
    if [[ -z "$project" ]]; then
      project="$(fb_compose_project_name "$app" "$env")"
    fi
    if [[ -n "$project" ]]; then
      log_info "Running docker compose up -d (project: $project)"
      if ! (cd "$workdir" && COMPOSE_PROJECT_NAME="$project" docker compose up -d >/dev/null 2>&1); then
        log_warn "Docker compose up failed."
        return 1
      fi
      return 0
    fi
    log_info "Running docker compose up -d"
    if ! (cd "$workdir" && docker compose up -d >/dev/null 2>&1); then
      log_warn "Docker compose up failed."
      return 1
    fi
    return 0
  fi
  return 1
}

read_compose_dir_fallback() {
  local app="$1"
  local env="$2"
  local compose_dir_file
  compose_dir_file="$(cloudflare_compose_dir_path "$app" "$env")"
  local compose_dir=""
  if [[ -f "$compose_dir_file" ]]; then
    compose_dir="$(cat "$compose_dir_file" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  fi
  if [[ -z "$compose_dir" ]] && app_repo_matches "$app"; then
    compose_dir="$PWD"
  fi
  if [[ -n "$compose_dir" ]]; then
    fb_abs_path "$compose_dir"
  fi
}

cmd_app_down() {
  local app_name=""
  local env_name="dev"
  local tunnel_only="false"
  local unpublish_only="false"
  local stop_runtime="false"
  local purge="false"
  local force="false"
  local repo_hint="false"

  local selector=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a|--app)
        if [[ -z "${2:-}" || "${2:0:1}" == "-" ]]; then
          die "Usage: fb app down [options] [app[/env]]"
        fi
        app_name="$2"
        shift 2
        ;;
      -e|--env)
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
      --unpublish-only)
        unpublish_only="true"
        shift
        ;;
      --stop-runtime)
        stop_runtime="true"
        shift
        ;;
      --purge)
        purge="true"
        shift
        ;;
      --force)
        force="true"
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
    if [[ -f "$PWD/docker-compose.yml" || -f "$PWD/docker-compose.yaml" ]]; then
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

  local state_dir="$FB_HOME/$app_name/$env_name"
  local state_file
  state_file="$(state_json_path "$app_name" "$env_name")"
  local zone_apex=""
  local tunnel_name=""
  local tunnel_id=""
  local shared_tunnel="unknown"
  local fqdns_list=""
  local config_path=""
  local pid_file=""
  if state_json_valid "$state_file"; then
    zone_apex="$(state_json_get "$state_file" '.zone_apex')"
    tunnel_name="$(state_json_get "$state_file" '.tunnel_name')"
    tunnel_id="$(state_json_get "$state_file" '.tunnel_id')"
    shared_tunnel="$(state_json_get_bool "$state_file" '.shared_tunnel')"
    fqdns_list="$(state_json_get_array "$state_file" '.fqdns' | normalize_fqdns_list)"
    config_path="$(state_json_get "$state_file" '.paths.config_yml')"
    pid_file="$(state_json_get "$state_file" '.paths.cloudflared_pid_file')"
  fi
  if [[ -z "$config_path" ]]; then
    config_path="$(cloudflare_config_path "$app_name" "$env_name")"
  fi
  if [[ -z "$pid_file" ]]; then
    pid_file="$(cloudflare_pid_path "$app_name" "$env_name")"
  fi

  stop_connector_for_env "$app_name" "$env_name" "$pid_file" "$config_path"
  if [[ -z "$fqdns_list" ]]; then
    fqdns_list="$(read_config_hostnames "$config_path" | normalize_fqdns_list)"
  fi
  local config_tunnel_id=""
  config_tunnel_id="$(read_config_tunnel_id "$config_path")"
  if [[ -n "$config_tunnel_id" ]]; then
    if [[ -n "$tunnel_id" && "$tunnel_id" != "$config_tunnel_id" ]]; then
      log_warn "Tunnel ID mismatch; using config.yml value."
    fi
    tunnel_id="$config_tunnel_id"
  fi
  if [[ -z "$tunnel_name" ]]; then
    local tunnel_name_file
    tunnel_name_file="$(cloudflare_tunnel_name_path "$app_name" "$env_name")"
    if [[ -f "$tunnel_name_file" ]]; then
      tunnel_name="$(cat "$tunnel_name_file")"
    fi
  fi
  if [[ -z "$tunnel_name" ]]; then
    tunnel_name="${app_name}-${env_name}"
  fi

  local legacy_default="false"
  if is_true "${FOUNDERBOOSTER_APP_DOWN_LEGACY_DEFAULT:-}"; then
    legacy_default="true"
  fi
  if is_true "$tunnel_only"; then
    unpublish_only="true"
  fi
  if [[ "$unpublish_only" != "true" && "$stop_runtime" != "true" && "$purge" != "true" && "$legacy_default" != "true" ]]; then
    log_warn "Default behavior changed: fb app down now unpublishes only. Use --stop-runtime to stop the app stack."
  fi
  if [[ "$unpublish_only" != "true" && "$stop_runtime" != "true" && "$purge" != "true" && "$legacy_default" == "true" ]]; then
    stop_runtime="true"
  fi
  if [[ "$unpublish_only" == "true" ]]; then
    stop_runtime="false"
  fi
  if [[ "$purge" == "true" && "$unpublish_only" != "true" ]]; then
    stop_runtime="true"
  fi

  local perform_unpublish="true"

  if [[ "$perform_unpublish" == "true" ]]; then
    if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
      log_warn "CLOUDFLARE_API_TOKEN not set; skipping DNS removal."
    elif [[ -z "$fqdns_list" ]]; then
      log_warn "No FQDNs found for $app_name/$env_name; skipping DNS removal."
    else
      if [[ -z "$zone_apex" ]]; then
        local first_fqdn
        first_fqdn="$(printf '%s\n' "$fqdns_list" | head -n1)"
        if [[ -n "$first_fqdn" ]]; then
          cf_ensure_zone "$first_fqdn"
          zone_apex="${CF_ZONE_NAME:-$first_fqdn}"
        fi
      else
        cf_ensure_zone "$zone_apex"
      fi
      if [[ -n "${CF_ZONE_ID:-}" ]]; then
        while IFS= read -r fqdn; do
          [[ -z "$fqdn" ]] && continue
          cf_delete_dns_record "$CF_ZONE_ID" "$fqdn"
        done <<<"$fqdns_list"
      fi
    fi
  fi

  if [[ "$stop_runtime" != "true" && "$purge" != "true" ]]; then
    log_info "✅ Stopped: $app_name/$env_name"
    log_info "App unpublished. Local runtime preserved."
    log_info "Next: fb app up ${app_name}/${env_name} to re-publish; fb app down ${app_name}/${env_name} --purge to delete forever"
    return 0
  fi

  local compose_dir=""
  compose_dir="$(read_compose_dir_fallback "$app_name" "$env_name" || true)"
  local stopped="false"
  if [[ "$stop_runtime" == "true" ]]; then
    if app_repo_matches "$app_name"; then
      if stop_app_stack "$app_name" "$env_name"; then
        stopped="true"
      fi
    fi
    if [[ "$stopped" != "true" && -n "$compose_dir" ]]; then
      if stop_app_stack "$app_name" "$env_name" "$compose_dir"; then
        stopped="true"
      fi
    fi
    if [[ "$stopped" != "true" ]]; then
      if ! app_repo_matches "$app_name"; then
        log_warn "Current directory does not match app '$app_name'; skipping app stop."
        log_warn "Run from the app repo or pass --stop-runtime."
      elif [[ -n "$compose_dir" ]]; then
        log_warn "No docker-compose.yml or docker-compose.yaml found in $compose_dir."
      else
        log_warn "No docker-compose.yml or docker-compose.yaml found."
      fi
    fi
  fi

  log_info "✅ Stopped: $app_name/$env_name"

  if is_true "$purge"; then
    if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
      log_warn "CLOUDFLARE_API_TOKEN not set; skipping tunnel delete."
    else
      if [[ -z "$zone_apex" && -n "$fqdns_list" ]]; then
        local first_fqdn
        first_fqdn="$(printf '%s\n' "$fqdns_list" | head -n1)"
        if [[ -n "$first_fqdn" ]]; then
          cf_ensure_zone "$first_fqdn"
          zone_apex="${CF_ZONE_NAME:-$first_fqdn}"
        fi
      elif [[ -n "$zone_apex" ]]; then
        cf_ensure_zone "$zone_apex"
      fi
      local resolved_tunnel_id="$tunnel_id"
      if [[ -z "$resolved_tunnel_id" && -n "$tunnel_name" && -n "${CF_ACCOUNT_ID:-}" ]]; then
        resolved_tunnel_id="$(cf_get_tunnel "$CF_ACCOUNT_ID" "$tunnel_name" || true)"
      fi
      if [[ -n "$resolved_tunnel_id" ]]; then
        if [[ -z "${CF_ACCOUNT_ID:-}" ]]; then
          log_warn "Cloudflare account not resolved; skipping tunnel delete."
        elif [[ "$shared_tunnel" == "true" && "$force" != "true" ]]; then
          log_warn "Shared tunnel detected; skipping delete (use --force to delete)."
        elif [[ "$shared_tunnel" == "unknown" && "$force" != "true" ]]; then
          log_warn "Shared tunnel unknown; skipping delete (use --force to delete)."
        else
          if ! cf_delete_tunnel "$CF_ACCOUNT_ID" "$resolved_tunnel_id"; then
            log_warn "Failed to delete tunnel $resolved_tunnel_id; continuing purge."
          fi
        fi
      fi
    fi
    if [[ -d "$state_dir" ]]; then
      rm -rf "$state_dir"
      log_info "Removed local state: $state_dir"
    else
      log_info "No local state found to remove: $state_dir."
    fi
    log_info "App purged. Recreate with: fb bootstrap"
  else
    log_info "App unpublished and runtime stopped."
    log_info "Next: start your app (e.g., docker compose up -d) then fb app up ${app_name}/${env_name} to re-publish"
  fi
}

cmd_app_up() {
  local app_name=""
  local env_name="dev"
  local selector=""
  local repo_hint="false"
  local start_runtime="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a|--app)
        if [[ -z "${2:-}" || "${2:0:1}" == "-" ]]; then
          die "Usage: fb app up [options] [app[/env]]"
        fi
        app_name="$2"
        shift 2
        ;;
      -e|--env)
        if [[ -z "${2:-}" || "${2:0:1}" == "-" ]]; then
          die "Usage: fb app up [options] [app[/env]]"
        fi
        env_name="$2"
        shift 2
        ;;
      --start-runtime)
        start_runtime="true"
        shift
        ;;
      -h|--help)
        app_up_help
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
    if [[ -f "$PWD/docker-compose.yml" || -f "$PWD/docker-compose.yaml" ]]; then
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
      die "Multiple environments found. Use: fb app up <app>/<env>"
    fi
  fi

  if [[ -z "$app_name" ]]; then
    app_name="$(safe_basename "$PWD")"
  fi

  local state_dir="$FB_HOME/$app_name/$env_name"
  if [[ ! -d "$state_dir" ]]; then
    die "No local state. Run fb bootstrap in your app repo."
  fi

  local state_file
  state_file="$(state_json_path "$app_name" "$env_name")"
  local zone_apex=""
  local tunnel_name=""
  local tunnel_id=""
  local shared_tunnel="false"
  local auto_mode=""
  local runtime_type=""
  local fqdns_list=""
  local config_path=""
  local token_path=""
  if state_json_valid "$state_file"; then
    zone_apex="$(state_json_get "$state_file" '.zone_apex')"
    tunnel_name="$(state_json_get "$state_file" '.tunnel_name')"
    tunnel_id="$(state_json_get "$state_file" '.tunnel_id')"
    shared_tunnel="$(state_json_get_bool "$state_file" '.shared_tunnel')"
    auto_mode="$(state_json_get_bool "$state_file" '.auto_mode')"
    runtime_type="$(state_json_get "$state_file" '.runtime_type')"
    fqdns_list="$(state_json_get_array "$state_file" '.fqdns' | normalize_fqdns_list)"
    config_path="$(state_json_get "$state_file" '.paths.config_yml')"
    token_path="$(state_json_get "$state_file" '.paths.tunnel_token_file')"
  fi

  if [[ -z "$config_path" ]]; then
    config_path="$(cloudflare_config_path "$app_name" "$env_name")"
  fi
  if [[ -z "$token_path" ]]; then
    token_path="$(cloudflare_token_path "$app_name" "$env_name")"
  fi

  if [[ ! -f "$config_path" ]]; then
    die "Missing config.yml for $app_name/$env_name. Run fb bootstrap in your app repo."
  fi

  local config_tunnel_id=""
  config_tunnel_id="$(read_config_tunnel_id "$config_path")"
  if [[ -n "$config_tunnel_id" ]]; then
    if [[ -n "$tunnel_id" && "$tunnel_id" != "$config_tunnel_id" ]]; then
      log_warn "Tunnel ID mismatch; using config.yml value."
    fi
    tunnel_id="$config_tunnel_id"
  fi
  if [[ -z "$tunnel_name" ]]; then
    local tunnel_name_file
    tunnel_name_file="$(cloudflare_tunnel_name_path "$app_name" "$env_name")"
    if [[ -f "$tunnel_name_file" ]]; then
      tunnel_name="$(cat "$tunnel_name_file")"
    fi
  fi
  if [[ -z "$tunnel_name" ]]; then
    tunnel_name="${app_name}-${env_name}"
  fi
  if [[ -z "$fqdns_list" ]]; then
    fqdns_list="$(read_config_hostnames "$config_path" | normalize_fqdns_list)"
  fi

  if [[ -z "$zone_apex" ]]; then
    local first_fqdn
    first_fqdn="$(printf '%s\n' "$fqdns_list" | head -n1)"
    if [[ -n "$first_fqdn" ]]; then
      cf_ensure_zone "$first_fqdn"
      zone_apex="${CF_ZONE_NAME:-$first_fqdn}"
    fi
  else
    cf_ensure_zone "$zone_apex"
  fi

  if [[ -n "$tunnel_name" ]]; then
    local resolved_tunnel_id=""
    resolved_tunnel_id="$(cf_get_tunnel "$CF_ACCOUNT_ID" "$tunnel_name" || true)"
    if [[ -z "$resolved_tunnel_id" ]]; then
      resolved_tunnel_id="$(cf_create_tunnel "$CF_ACCOUNT_ID" "$tunnel_name")"
    fi
    if [[ -n "$resolved_tunnel_id" ]]; then
      if [[ -n "$tunnel_id" && "$tunnel_id" != "$resolved_tunnel_id" ]]; then
        log_warn "Tunnel ID updated; syncing config.yml."
      fi
      tunnel_id="$resolved_tunnel_id"
      update_config_tunnel_id "$config_path" "$tunnel_id" || true
    fi
  fi

  if [[ -z "$tunnel_id" ]]; then
    die "Unable to resolve tunnel for $app_name/$env_name. Run fb bootstrap again."
  fi

  if [[ -n "$fqdns_list" ]]; then
    local target="${tunnel_id}.cfargotunnel.com"
    while IFS= read -r fqdn; do
      [[ -z "$fqdn" ]] && continue
      cf_ensure_dns_record "$CF_ZONE_ID" "$fqdn" "$target"
    done <<<"$fqdns_list"
  else
    log_warn "No FQDNs found; DNS records not updated."
  fi

  local token=""
  if [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
    token="$(cloudflare_get_token_or_file "$app_name" "$env_name" "$CF_ACCOUNT_ID" "$tunnel_id")"
  elif [[ -f "$token_path" ]]; then
    token="$(cat "$token_path")"
  else
    cloudflare_token_help
    die "Cloudflare tunnel token missing at $token_path."
  fi
  if [[ -z "$token" ]]; then
    die "Cloudflare tunnel token missing at $token_path."
  fi

  cloudflare_run_tunnel "$app_name" "$env_name" "$token"

  local compose_dir=""
  compose_dir="$(read_compose_dir_fallback "$app_name" "$env_name" || true)"
  local ports_json=""
  local ports_file
  ports_file="$(ports_json_path "$app_name" "$env_name")"
  if ports_vals="$(read_ports_json "$ports_file")"; then
    local ports_site ports_api
    ports_site="${ports_vals%% *}"
    ports_api="${ports_vals##* }"
    ports_json="\"site\":${ports_site},\"api\":${ports_api}"
  fi

  if command -v write_state_json >/dev/null 2>&1; then
    write_state_json "$state_dir" "$app_name" "$env_name" "$zone_apex" "$tunnel_name" "$tunnel_id" "$shared_tunnel" "$fqdns_list" "$compose_dir" "$ports_json" "$auto_mode" "$runtime_type"
  fi

  if [[ "$start_runtime" == "true" && -n "$compose_dir" ]]; then
    if ! start_app_stack "$app_name" "$env_name" "$compose_dir"; then
      log_warn "Runtime start failed; publish still active."
    fi
  fi

  if [[ -n "$ports_json" ]]; then
    local port_site
    port_site="$(echo "$ports_json" | sed -n 's/.*"site":\([0-9][0-9]*\).*/\1/p')"
    if [[ -n "$port_site" ]]; then
      if ! curl -s -o /dev/null "http://localhost:$port_site"; then
        log_warn "Published, but local backend appears stopped/unreachable; visitors may see 502."
      fi
    fi
  fi

  log_info "App re-published."
  if [[ -n "$fqdns_list" ]]; then
    local count=0
    while IFS= read -r fqdn; do
      [[ -z "$fqdn" ]] && continue
      log_info "  URL: https://$fqdn"
      count=$((count + 1))
      if [[ "$count" -ge 5 ]]; then
        break
      fi
    done <<<"$fqdns_list"
  fi
  log_info "Next: fb app down ${app_name}/${env_name} to unpublish"
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
      -a|--app)
        if [[ -z "${2:-}" || "${2:0:1}" == "-" ]]; then
          die "Usage: fb app status [options] [app[/env]]"
        fi
        app_name="$2"
        shift 2
        ;;
      -e|--env)
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
      -H|--hosts)
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
            cfg_ports="$(awk '/service: http:\/\//{print $2}' "$cfg" | awk -F: '{print $NF}' | sort -u)"
              if [[ -n "$cfg_ports" ]] && comm -12 <(echo "$cfg_ports") <(echo "$docker_ports") >/dev/null 2>&1; then
                chosen_env="$env"
                break
              fi
            fi
          done <<<"$envs"
          if [[ -n "$chosen_env" ]]; then
            env_name="$chosen_env"
          else
            log_warn "Multiple environments found; use -e (or --env) to select."
          fi
        else
          log_warn "Multiple environments found; use -e (or --env) to select."
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
    log_warn "Run: fb bootstrap -e $env_name -d <domain> (or --env/--domain)"
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
    up)
      shift
      cmd_app_up "$@"
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
