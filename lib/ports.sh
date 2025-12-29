#!/usr/bin/env bash
set -euo pipefail

hash_app_base() {
  local app="$1"
  local hex
  if command -v shasum >/dev/null 2>&1; then
    hex="$(echo -n "$app" | shasum -a 1 | awk '{print $1}')"
  else
    hex="$(echo -n "$app" | sha1sum | awk '{print $1}')"
  fi
  local short="${hex:0:8}"
  local mod=$((16#$short % 20000))
  echo $((20000 + mod))
}

env_offset_site() {
  local env="$1"
  case "$env" in
    prod) echo 0 ;;
    dev) echo 10 ;;
    staging) echo 20 ;;
    *) return 1 ;;
  esac
}

env_offset_api() {
  local env="$1"
  case "$env" in
    prod) echo 1 ;;
    dev) echo 11 ;;
    staging) echo 21 ;;
    *) return 1 ;;
  esac
}

ports_json_path() {
  local app="$1"
  local env="$2"
  echo "$FB_HOME/$app/$env/ports.json"
}

read_ports_json() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  local site api
  site="$(awk -F'[:,}]' '/"site"/{gsub(/[^0-9]/,"",$2); print $2}' "$file")"
  api="$(awk -F'[:,}]' '/"api"/{gsub(/[^0-9]/,"",$2); print $2}' "$file")"
  if [[ -n "$site" && -n "$api" ]]; then
    echo "$site $api"
    return 0
  fi
  return 1
}

write_ports_json() {
  local file="$1"
  local site="$2"
  local api="$3"
  ensure_dir "$(dirname "$file")"
  umask 077
  printf '{"site":%s,"api":%s}\n' "$site" "$api" >"$file"
}

port_in_use() {
  local port="$1"
  lsof -n -P -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

port_owner() {
  local port="$1"
  lsof -n -P -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true
}

docker_published_ports_for_app() {
  local app="$1"
  local workdir="${2:-$PWD}"
  if ! command -v docker >/dev/null 2>&1; then
    return 1
  fi
  if command -v jq >/dev/null 2>&1; then
    local compose_ports
    compose_ports="$( (cd "$workdir" && docker compose config --format json 2>/dev/null) \
      | jq -r '
        .services // {} | to_entries[]? | .value.ports[]? |
        if type=="string" then
          split(":") as $parts |
          if ($parts|length) >= 2 then
            ($parts[-2] | split("/")[0])
          else empty end
        elif type=="object" then
          .published // empty
        else empty end
      ' | awk 'NF' | sort -u )"
    if [[ -n "$compose_ports" ]]; then
      echo "$compose_ports"
      return 0
    fi
  fi
  local project=""
  if command -v jq >/dev/null 2>&1; then
    local compose_json
    compose_json="$(docker compose ls --format json 2>/dev/null || true)"
    if [[ -n "$compose_json" ]]; then
      project="$(printf '%s' "$compose_json" | jq -r --arg dir "$workdir" '.[] | select(.WorkingDir==$dir) | .Name' | head -n1)"
      if [[ "$project" == "null" ]]; then
        project=""
      fi
    fi
  fi
  local lines
  if [[ -n "$project" ]]; then
    if ! lines="$(docker ps --filter "label=com.docker.compose.project=$project" --format '{{.Names}}\t{{.Ports}}' 2>/dev/null)"; then
      return 1
    fi
  elif ! lines="$(docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null)"; then
    return 1
  fi
  if [[ -z "$lines" ]]; then
    return 1
  fi
  local matches="$lines"
  if [[ -z "$project" ]]; then
    matches="$(echo "$lines" | awk -v app="$app" 'BEGIN{IGNORECASE=1} $1 ~ app {print $0}')"
    if [[ -z "$matches" ]]; then
      return 1
    fi
  fi
  echo "$matches" | awk '
    {
      ports=$0
      sub(/^[^\t]*\t/,"",ports)
      n=split(ports, a, ",")
      for (i=1; i<=n; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i])
        gsub(/^.*:/, "", a[i])
        gsub(/->.*$/, "", a[i])
        if (a[i] ~ /^[0-9]+$/) {
          print a[i]
        }
      }
    }
  ' | sort -u
}

resolve_ports() {
  local app="$1"
  local env="$2"
  local site_flag="$3"
  local api_flag="$4"
  local config_site="$5"
  local config_api="$6"
  local json_site=""
  local json_api=""

  local json_file
  json_file="$(ports_json_path "$app" "$env")"
  if read_ports_json "$json_file" >/dev/null 2>&1; then
    read -r json_site json_api <<<"$(read_ports_json "$json_file")"
  fi

  if [[ -n "$config_site" && -n "$config_api" ]]; then
    SITE_PORT="$config_site"
    API_PORT="$config_api"
    PORTS_SOURCE="config"
    validate_ports "$SITE_PORT" "$API_PORT" "$PORTS_SOURCE"
    return 0
  fi

  if [[ -n "$site_flag" || -n "$api_flag" ]]; then
    if [[ -z "$site_flag" ]]; then
      die "--site-port is required when overriding ports."
    fi
    if [[ -z "$api_flag" ]]; then
      api_flag="$site_flag"
    fi
    SITE_PORT="$site_flag"
    API_PORT="$api_flag"
    PORTS_SOURCE="flags"
    validate_ports "$SITE_PORT" "$API_PORT" "$PORTS_SOURCE"
    return 0
  fi

  if [[ -n "$json_site" && -n "$json_api" ]]; then
    SITE_PORT="$json_site"
    API_PORT="$json_api"
    PORTS_SOURCE="ports.json"
    if ! validate_ports "$SITE_PORT" "$API_PORT" "$PORTS_SOURCE"; then
      log_warn "Ignoring invalid ports.json and falling back to deterministic ports."
      SITE_PORT=""
      API_PORT=""
    else
      return 0
    fi
  fi

  local base offset_site offset_api
  base="$(hash_app_base "$app")"
  if ! offset_site="$(env_offset_site "$env")"; then
    die "Unknown env '$env' for port offsets. Use dev, staging, or prod."
  fi
  if ! offset_api="$(env_offset_api "$env")"; then
    die "Unknown env '$env' for port offsets. Use dev, staging, or prod."
  fi
  SITE_PORT=$((base + offset_site))
  API_PORT=$((base + offset_api))
  PORTS_SOURCE="deterministic"
  validate_ports "$SITE_PORT" "$API_PORT" "$PORTS_SOURCE"
}

validate_ports() {
  local site="$1"
  local api="$2"
  local source="$3"
  if [[ ! "$site" =~ ^[0-9]+$ || ! "$api" =~ ^[0-9]+$ ]]; then
    if [[ "$source" == "ports.json" ]]; then
      return 1
    fi
    die "Invalid port values from $source."
  fi
  if [[ "$site" == "$api" ]]; then
    if [[ "${FB_BOOTSTRAP:-}" != "true" ]]; then
      log_info "Single-port app detected: localhost:$site (source=$source)."
    fi
  fi
  return 0
}

select_auto_ports() {
  local app="$1"
  local env="$2"
  local start_site="$3"
  local base
  base="$(hash_app_base "$app")"
  local min="$base"
  local max=$((base + 99))
  local site
  for ((site=start_site; site<=max; site++)); do
    local api=$((site + 1))
    if ((api > max)); then
      break
    fi
    if ! port_in_use "$site" && ! port_in_use "$api"; then
      echo "$site $api"
      return 0
    fi
  done
  return 1
}

ensure_ports_available() {
  local app="$1"
  local env="$2"
  local auto_ports="$3"

  if [[ "$PORTS_SOURCE" == "flags" ]]; then
    if port_in_use "$SITE_PORT" || port_in_use "$API_PORT"; then
      log_warn "Ports already in use; continuing because ports were explicitly set."
    fi
    return 0
  fi

  if ! port_in_use "$SITE_PORT" && ! port_in_use "$API_PORT"; then
    return 0
  fi

  if is_true "$auto_ports"; then
    local base
    base="$(hash_app_base "$app")"
    local offset
    offset="$(env_offset_site "$env")"
    local start_site=$((base + offset))
    local selected
    if selected="$(select_auto_ports "$app" "$env" "$start_site")"; then
      read -r SITE_PORT API_PORT <<<"$selected"
      PORTS_SOURCE="auto"
      write_ports_json "$(ports_json_path "$app" "$env")" "$SITE_PORT" "$API_PORT"
      log_warn "Ports in use; auto-selected $SITE_PORT/$API_PORT and saved ports.json"
      return 0
    fi
    die "No available port pair found in [$base, $((base+99))]."
  fi

  log_error "Port conflict detected."
  log_error "Site port $SITE_PORT and/or API port $API_PORT is already in use."
  log_error "Run: fb doctor --ports to inspect usage."
  log_error "Remediation: stop the owning process, set ports in founderbooster.yml, or use --auto-ports."
  exit 1
}
