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

safe_basename() {
  local path="$1"
  basename "$path"
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
