#!/usr/bin/env bash
set -euo pipefail

doctor_help() {
  cat <<'EOF'
Usage: fb doctor [options]

Options:
  --ports            Show resolved ports and check usage
  --dns              Show DNS records for the resolved domain
  --install          Verify installed binary and version file
  -a, --app NAME         Override app name
  -e, --env ENV          Environment (dev|staging|prod)
  -d, --domain DOMAIN    Override domain
  -s, --site-port PORT   Override site port
  -i, --api-port PORT    Override api port
  -H, --hosts LIST       Comma list: root,api,www
EOF
}

cmd_doctor() {
  local check_ports="false"
  local check_dns="false"
  local check_install="false"
  local app_name=""
  local env_name="dev"
  local domain=""
  local site_port=""
  local api_port=""
  local hosts_list=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ports)
        check_ports="true"
        shift
        ;;
      --dns)
        check_dns="true"
        shift
        ;;
      --install)
        check_install="true"
        shift
        ;;
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
        shift 2
        ;;
      -i|--api-port)
        api_port="$2"
        shift 2
        ;;
      -H|--hosts)
        hosts_list="$2"
        shift 2
        ;;
      -h|--help)
        doctor_help
        return 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  require_cmd curl
  require_cmd jq
  require_cmd lsof
  require_cmd cloudflared

  log_info "Prerequisites OK."

  if ! is_true "$check_ports"; then
    if ! is_true "$check_dns"; then
      if ! is_true "$check_install"; then
        return 0
      fi
    fi
  fi

  fb_config_init
  if [[ -z "$app_name" ]]; then
    app_name="$(config_app_name)"
  fi
  if [[ -z "$app_name" ]]; then
    app_name="$(safe_basename "$PWD")"
  fi
  if [[ -z "$domain" ]]; then
    domain="$(config_get "domains.$env_name")"
  fi
  local config_site config_api
  config_site="$(config_get "ports.$env_name.site")"
  config_api="$(config_get "ports.$env_name.api")"
  resolve_ports "$app_name" "$env_name" "$site_port" "$api_port" "$config_site" "$config_api"

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

  if is_true "$check_ports"; then
    if [[ "${FB_BOOTSTRAP:-}" != "true" ]]; then
      log_info "Resolved ports: site=$SITE_PORT api=$API_PORT (source=$PORTS_SOURCE)"
    fi
    if port_in_use "$SITE_PORT"; then
      log_warn "Site port $SITE_PORT is in use:"
      port_owner "$SITE_PORT"
    elif [[ "${FB_BOOTSTRAP:-}" != "true" ]]; then
      log_info "Site port $SITE_PORT is free."
    fi
    if port_in_use "$API_PORT"; then
      log_warn "API port $API_PORT is in use:"
      port_owner "$API_PORT"
    elif [[ "${FB_BOOTSTRAP:-}" != "true" ]]; then
      log_info "API port $API_PORT is free."
    fi

    local docker_ports
    docker_ports="$(docker_published_ports_for_app "$app_name" || true)"
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
        rec_site="$(echo "$docker_ports" | head -n1)"
        rec_api="$(echo "$docker_ports" | sed -n '2p')"
        if [[ -z "$rec_api" ]]; then
          rec_api="$rec_site"
        fi
        log_warn "Docker publishes ports for containers matching '$app_name' that do not include the resolved ports."
        log_info "Ports published by Docker: $docker_ports_list"
        log_info "If your app listens on one of these, rerun: fb bootstrap -s $rec_site -i $rec_api (or --site-port/--api-port)"
      fi
    fi
  fi

  if is_true "$check_dns"; then
    if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
      die "CLOUDFLARE_API_TOKEN is required for --dns checks."
    fi
    if [[ -z "$domain" ]]; then
      domain="$(config_get "domains.$env_name")"
    fi
    if [[ -z "$domain" ]]; then
      die "Domain is required for --dns checks."
    fi
    resolve_domain_for_env "$domain" "$env_name"
    domain="$DOMAIN_NAME"
    cf_ensure_zone "$domain"
    local target_domain="$domain"
    local api_hostname
    api_hostname="$API_HOSTNAME_OVERRIDE"
    local www_hostname
    www_hostname="$WWW_HOSTNAME_OVERRIDE"

    local record
    if is_true "$include_root"; then
      record="$(cf_get_dns_record "$CF_ZONE_ID" "$target_domain")"
      if [[ -z "$record" ]]; then
        log_warn "DNS record missing: $target_domain"
      else
        log_info "DNS record: $target_domain -> $(echo "$record" | jq -r '.content') (proxied=$(echo "$record" | jq -r '.proxied'))"
      fi
    fi

    if is_true "$include_api"; then
      record="$(cf_get_dns_record "$CF_ZONE_ID" "$api_hostname")"
      if [[ -z "$record" ]]; then
        log_warn "DNS record missing: $api_hostname"
      else
        log_info "DNS record: $api_hostname -> $(echo "$record" | jq -r '.content') (proxied=$(echo "$record" | jq -r '.proxied'))"
      fi
    fi

    if is_true "$include_www"; then
      record="$(cf_get_dns_record "$CF_ZONE_ID" "$www_hostname")"
      if [[ -z "$record" ]]; then
        log_warn "DNS record missing: $www_hostname"
      else
        log_info "DNS record: $www_hostname -> $(echo "$record" | jq -r '.content') (proxied=$(echo "$record" | jq -r '.proxied'))"
      fi
    fi
  fi

  if is_true "$check_install"; then
    local bin_path
    bin_path="$(command -v fb || true)"
    if [[ -n "$bin_path" ]]; then
      log_info "fb binary: $bin_path"
    else
      log_warn "fb binary not found in PATH."
    fi
    local version_file="$FB_HOME/VERSION"
    if [[ -f "$version_file" ]]; then
      log_info "Installed version: $(cat "$version_file")"
    else
      log_warn "Version file missing: $version_file"
    fi
  fi
}
