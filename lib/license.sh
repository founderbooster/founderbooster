#!/usr/bin/env bash
set -euo pipefail

license_path() {
  echo "$FB_HOME/license.key"
}

get_license_key() {
  if [[ -n "${FOUNDERBOOSTER_LICENSE_KEY:-}" ]]; then
    echo "$FOUNDERBOOSTER_LICENSE_KEY"
    return 0
  fi
  local path
  path="$(license_path)"
  if [[ -f "$path" ]]; then
    cat "$path"
    return 0
  fi
  return 1
}

valid_license_key() {
  local key="$1"
  if ! is_signed_license_key "$key"; then
    return 1
  fi
  verify_signed_license "$key"
  return $?
}

has_early_access() {
  local key
  if key="$(get_license_key 2>/dev/null)"; then
    if valid_license_key "$key"; then
      return 0
    fi
  fi
  return 1
}

is_signed_license_key() {
  local key="$1"
  [[ "$key" =~ ^FB1-[A-Za-z0-9_-]+-[A-Za-z0-9_-]+$ ]]
}

license_pubkey_pem() {
  if [[ -n "${FOUNDERBOOSTER_LICENSE_PUBKEY_PATH:-}" && -f "$FOUNDERBOOSTER_LICENSE_PUBKEY_PATH" ]]; then
    cat "$FOUNDERBOOSTER_LICENSE_PUBKEY_PATH"
    return 0
  fi
  if [[ -n "${FOUNDERBOOSTER_LICENSE_PUBKEY:-}" ]]; then
    printf '%s\n' "$FOUNDERBOOSTER_LICENSE_PUBKEY"
    return 0
  fi
  local repo_key="$FB_ROOT/lib/license_pubkey.pem"
  if [[ -f "$repo_key" ]]; then
    cat "$repo_key"
    return 0
  fi
  return 1
}

base64url_decode() {
  local input="$1"
  local padded="$input"
  local mod=$(( ${#input} % 4 ))
  if [[ "$mod" -eq 2 ]]; then
    padded="${input}=="
  elif [[ "$mod" -eq 3 ]]; then
    padded="${input}="
  elif [[ "$mod" -eq 1 ]]; then
    return 1
  fi
  printf '%s' "$padded" | tr '_-' '/+' | openssl base64 -d -A
}

verify_signed_license() {
  local key="$1"
  local payload_b64 sig_b64
  payload_b64="${key#FB1-}"
  sig_b64="${payload_b64#*-}"
  payload_b64="${payload_b64%%-*}"

  if ! command -v openssl >/dev/null 2>&1; then
    log_error "openssl is required to verify license keys."
    log_error "Install openssl (macOS: brew install openssl; Debian/Ubuntu: apt-get install openssl)."
    return 1
  fi

  local tmp_dir payload_file sig_file pubkey_file
  tmp_dir="$(mktemp -d)"
  payload_file="$tmp_dir/payload.bin"
  sig_file="$tmp_dir/sig.bin"
  pubkey_file="$tmp_dir/pubkey.pem"

  if ! base64url_decode "$payload_b64" >"$payload_file" 2>/dev/null; then
    rm -rf "$tmp_dir"
    return 1
  fi
  if ! base64url_decode "$sig_b64" >"$sig_file" 2>/dev/null; then
    rm -rf "$tmp_dir"
    return 1
  fi
  if ! license_pubkey_pem >"$pubkey_file" 2>/dev/null; then
    rm -rf "$tmp_dir"
    return 1
  fi

  if openssl dgst -sha256 -verify "$pubkey_file" -signature "$sig_file" "$payload_file" >/dev/null 2>&1; then
    rm -rf "$tmp_dir"
    return 0
  fi
  rm -rf "$tmp_dir"
  return 1
}

warn_early_access_needed() {
  log_warn "This feature requires an Early Access license."
  cat <<EOF
FounderBooster is open source and remains fully usable without a license.
Some advanced workflows require Early Access.
$EARLY_ACCESS_URL
EOF
  return 1
}

require_license() {
  local key
  if key="$(get_license_key 2>/dev/null)"; then
    if valid_license_key "$key"; then
      return 0
    fi
    die "License key format is invalid. Run: fb activate <license-key>"
  fi
  log_error "This feature requires an Early Access license."
  cat <<EOF >&2
FounderBooster is open source and remains fully usable without a license.
Self-update and prebuilt binaries require Early Access.
$EARLY_ACCESS_URL
EOF
  exit 1
}

cmd_activate() {
  local key="${1:-}"
  if [[ -z "$key" ]]; then
    die "Usage: fb activate <license-key>"
  fi
  if ! is_signed_license_key "$key"; then
    die "License key format is invalid. Expected FB1-<payload>-<signature>."
  fi
  if ! verify_signed_license "$key"; then
    die "License key could not be verified."
  fi
  local path
  path="$(license_path)"
  ensure_dir "$(dirname "$path")"
  umask 077
  printf '%s\n' "$key" >"$path"
  log_info "License verified / Early Access unlocked"
}

cmd_license_status() {
  if has_early_access; then
    log_info "License status: Early Access"
    log_info "Early Access features unlocked"
    return 0
  fi
  log_info "License status: OSS mode"
  log_info "Core functionality included"
  log_info "Some advanced workflows require Early Access"
  log_info "$EARLY_ACCESS_URL"
  return 1
}
