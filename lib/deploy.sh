#!/usr/bin/env bash
set -euo pipefail

run_docker_compose() {
  local env="$1"
  if fb_compose_file >/dev/null 2>&1; then
    local project="${COMPOSE_PROJECT_NAME:-}"
    if [[ -z "$project" ]]; then
      project="$(fb_compose_project_name "${APP_NAME:-}" "$env")"
    fi
    if [[ -n "$project" ]]; then
      log_info "Running docker compose up -d (project: $project)"
      COMPOSE_PROJECT_NAME="$project" docker compose up -d
    else
      log_info "Running docker compose up -d"
      docker compose up -d
    fi
    if [[ -n "${APP_NAME:-}" ]]; then
      cloudflare_write_compose_dir "$APP_NAME" "$env" "$PWD"
    fi
    return 0
  fi
  return 1
}

deploy_app() {
  local env="$1"
  if run_docker_compose "$env"; then
    return 0
  fi
  log_warn "No docker-compose.yml or docker-compose.yaml found."
  log_warn "Deploy manually."
  return 1
}
