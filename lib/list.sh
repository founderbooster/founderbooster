#!/usr/bin/env bash
set -euo pipefail

list_help() {
  cat <<'EOF'
Usage: fb list

Alias: fb app list

List app/env directories that have a cloudflared config.

Examples:
  fb app list
  fb app down my-app/dev
  fb app down my-app --purge
EOF
}

cmd_list() {
  if [[ $# -gt 0 ]]; then
    list_help
    return 1
  fi

  if [[ ! -d "$FB_HOME" ]]; then
    log_warn "No environments found."
    return 0
  fi

  local configs
  configs="$(find "$FB_HOME" -type f -name config.yml 2>/dev/null | sort || true)"
  if [[ -z "$configs" ]]; then
    log_warn "No environments found."
    return 0
  fi

  while IFS= read -r config; do
    [[ -z "$config" ]] && continue
    local env_dir
    env_dir="$(dirname "$config")"
    local app
    app="$(basename "$(dirname "$env_dir")")"
    local env
    env="$(basename "$env_dir")"
    local pid_file
    pid_file="$(cloudflare_pid_path "$app" "$env")"
    local status="unpublished"
    local pid="-"
    if cloudflare_tunnel_running "$pid_file"; then
      status="published"
      pid="$(cat "$pid_file" 2>/dev/null || echo "-")"
    fi
    local compose_dir_file
    compose_dir_file="$(cloudflare_compose_dir_path "$app" "$env")"
    local compose_dir=""
    if [[ -f "$compose_dir_file" ]]; then
      compose_dir="$(cat "$compose_dir_file")"
    fi
    local compose_display="-"
    if [[ -n "$compose_dir" ]]; then
      compose_display="$compose_dir"
      if [[ -n "${HOME:-}" && "$compose_display" == "$HOME/"* ]]; then
        compose_display="~/${compose_display#$HOME/}"
      fi
    fi
    echo "  - $app/$env - type=app status=$status pid=$pid compose=$compose_display"
  done <<<"$configs"

  local any_running="false"
  while IFS= read -r config; do
    [[ -z "$config" ]] && continue
    local env_dir
    env_dir="$(dirname "$config")"
    local app
    app="$(basename "$(dirname "$env_dir")")"
    local env
    env="$(basename "$env_dir")"
    local pid_file
    pid_file="$(cloudflare_pid_path "$app" "$env")"
    if cloudflare_tunnel_running "$pid_file"; then
      any_running="true"
      break
    fi
  done <<<"$configs"
  if [[ "$any_running" == "true" ]]; then
    echo "Tip: fb app down <app>/<env> to unpublish; fb app down <app>/<env> --purge to delete forever"
  else
    echo "Tip: fb app up <app>/<env> to re-publish; fb app down <app>/<env> --purge to delete forever"
  fi
}
