#!/usr/bin/env bash
set -euo pipefail

resolve_context() {
  local app_flag="$1"
  local env_flag="$2"
  local domain_flag="$3"
  local site_flag="$4"
  local api_flag="$5"
  local auto_ports="$6"
  local default_app="$7"
  local default_env="$8"
  local default_api="$9"
  local default_www="${10}"

  fb_config_init

  APP_NAME="$app_flag"
  ENV_NAME="${env_flag:-$default_env}"
  DOMAIN_NAME="$domain_flag"

  if [[ -z "$APP_NAME" ]]; then
    APP_NAME="$(config_app_name)"
  fi
  if [[ -z "$APP_NAME" ]]; then
    if [[ -n "$default_app" ]]; then
      APP_NAME="$default_app"
    else
      APP_NAME="$(safe_basename "$PWD")"
    fi
  fi

  if [[ -z "$DOMAIN_NAME" ]]; then
    DOMAIN_NAME="$(config_get "domains.$ENV_NAME")"
  fi
  if [[ -z "$DOMAIN_NAME" ]]; then
    die "Domain is required. Set -d (or --domain) or founderbooster.yml domains.$ENV_NAME."
  fi

  local original_domain="$DOMAIN_NAME"
  resolve_domain_for_env "$DOMAIN_NAME" "$ENV_NAME"
  if [[ "$DOMAIN_NAME" != "$original_domain" ]]; then
    log_info "Using env subdomain: $DOMAIN_NAME (from $original_domain)"
  fi

  local config_site config_api
  config_site="$(config_get "ports.$ENV_NAME.site")"
  config_api="$(config_get "ports.$ENV_NAME.api")"
  resolve_ports "$APP_NAME" "$ENV_NAME" "$site_flag" "$api_flag" "$config_site" "$config_api"

  HOSTNAME_API="${default_api:-true}"
  HOSTNAME_WWW="${default_www:-true}"
  local cfg_api cfg_www
  cfg_api="$(config_get "hostnames.api")"
  cfg_www="$(config_get "hostnames.www")"
  if [[ -n "$cfg_api" ]]; then
    if is_true "$cfg_api"; then
      HOSTNAME_API="true"
    else
      HOSTNAME_API="false"
    fi
  fi
  if [[ -n "$cfg_www" ]]; then
    if is_true "$cfg_www"; then
      HOSTNAME_WWW="true"
    else
      HOSTNAME_WWW="false"
    fi
  fi

  AUTO_PORTS="$auto_ports"
}

resolve_domain_for_env() {
  local domain="$1"
  local env="$2"
  DOMAIN_NAME="$domain"
  DOMAIN_ROOT="$domain"
  API_HOSTNAME_OVERRIDE=""
  WWW_HOSTNAME_OVERRIDE=""
  local -a parts
  IFS='.' read -r -a parts <<<"$DOMAIN_NAME"
  local count="${#parts[@]}"
  local subdomain=""
  local root_domain="$DOMAIN_NAME"
  if ((count >= 3)); then
    subdomain="${parts[0]}"
    root_domain="${DOMAIN_NAME#${subdomain}.}"
  fi

  if [[ "$env" != "prod" ]]; then
    if [[ "$DOMAIN_NAME" == "${env}."* ]]; then
      subdomain="$env"
      root_domain="${DOMAIN_NAME#${env}.}"
      DOMAIN_ROOT="$root_domain"
    elif ((count <= 2)); then
      DOMAIN_ROOT="$DOMAIN_NAME"
      DOMAIN_NAME="${env}.${DOMAIN_NAME}"
      subdomain="$env"
      root_domain="$DOMAIN_ROOT"
    fi
  fi

  if [[ -n "$subdomain" ]]; then
    API_HOSTNAME_OVERRIDE="api-${subdomain}.${root_domain}"
    WWW_HOSTNAME_OVERRIDE="www-${subdomain}.${root_domain}"
  else
    API_HOSTNAME_OVERRIDE="api.${DOMAIN_NAME}"
    WWW_HOSTNAME_OVERRIDE="www.${DOMAIN_NAME}"
  fi
}

build_ingress_rules() {
  local domain="$1"
  local site_port="$2"
  local api_port="$3"
  local include_root="$4"
  local include_api="$5"
  local include_www="$6"
  local api_hostname="${7:-}"
  local www_hostname="${8:-}"
  local rules=""
  if [[ -z "$api_hostname" ]]; then
    api_hostname="api.$domain"
  fi
  if [[ -z "$www_hostname" ]]; then
    www_hostname="www.$domain"
  fi

  if is_true "$include_root"; then
    rules+="  - hostname: $domain"$'\n'
    rules+="    service: http://127.0.0.1:$site_port"$'\n'
  fi

  if is_true "$include_api"; then
    rules+="  - hostname: $api_hostname"$'\n'
    rules+="    service: http://127.0.0.1:$api_port"$'\n'
  fi

  if is_true "$include_www"; then
    rules+="  - hostname: $www_hostname"$'\n'
    rules+="    service: http://127.0.0.1:$site_port"$'\n'
  fi

  printf '%s' "$rules"
}

api_hostname_for_domain() {
  local domain="$1"
  local -a parts
  IFS='.' read -r -a parts <<<"$domain"
  local count="${#parts[@]}"
  if ((count >= 3)); then
    local sub="${parts[0]}"
    local zone="${domain#${sub}.}"
    echo "api-${sub}.${zone}"
    return 0
  fi
  echo "api.$domain"
}
