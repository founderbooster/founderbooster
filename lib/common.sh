#!/usr/bin/env bash
set -euo pipefail

FB_HOME="${FOUNDERBOOSTER_HOME:-$HOME/.founderbooster}"
EARLY_ACCESS_URL="${EARLY_ACCESS_URL:-https://founderbooster.com/early-access}"

log_info() {
  echo "INFO: $*"
}

log_warn() {
  echo "WARN: $*" >&2
}

log_error() {
  echo "ERROR: $*" >&2
}

die() {
  log_error "$@"
  if [[ -n "${APP_NAME:-}" && -n "${ENV_NAME:-}" ]]; then
    echo "Next: fb app status ${APP_NAME}/${ENV_NAME}" >&2
  fi
  exit 1
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "Missing required command: $cmd"
  fi
}

ensure_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
  fi
}

is_true() {
  local val
  val="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$val" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

is_semver() {
  local val="$1"
  [[ "$val" =~ ^[0-9]+(\.[0-9]+)*$ ]]
}

safe_basename() {
  local path="$1"
  basename "$path"
}

fb_compose_file() {
  if [[ -f "$PWD/docker-compose.yml" ]]; then
    echo "$PWD/docker-compose.yml"
    return 0
  fi
  if [[ -f "$PWD/docker-compose.yaml" ]]; then
    echo "$PWD/docker-compose.yaml"
    return 0
  fi
  return 1
}

fb_compose_project_name() {
  local app="${1:-}"
  local env="${2:-}"
  if [[ -z "$app" ]]; then
    app="$(safe_basename "$PWD")"
  fi
  local raw="${app}-${env}"
  local name
  name="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g; s/--*/-/g; s/^-//; s/-$//')"
  if [[ -z "$name" ]]; then
    name="fb"
  fi
  echo "$name"
}

print_early_access_footer() {
  cat <<EOF
FounderBooster is open source.
Optional lifetime Early Access licenses are available for users who want prebuilt binaries, automatic updates, and early access to advanced features.
$EARLY_ACCESS_URL
EOF
}

downloads_base_url() {
  local base=""
  if [[ -f "$FB_HOME/download_base_url" ]]; then
    base="$(cat "$FB_HOME/download_base_url")"
  fi
  echo "${FB_DOWNLOAD_BASE_URL:-${DOWNLOAD_BASE_URL:-${base:-https://downloads.founderbooster.com}}}"
}

version_ge() {
  local a="$1"
  local b="$2"
  local IFS=.
  local -a va vb
  read -r -a va <<<"$a"
  read -r -a vb <<<"$b"
  local i max
  max="${#va[@]}"
  if (( ${#vb[@]} > max )); then
    max="${#vb[@]}"
  fi
  for ((i=0; i<max; i++)); do
    local ai="${va[i]:-0}"
    local bi="${vb[i]:-0}"
    if (( ai > bi )); then
      return 0
    fi
    if (( ai < bi )); then
      return 1
    fi
  done
  return 0
}
