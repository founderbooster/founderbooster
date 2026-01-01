#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    echo "ASSERT_EQ failed: expected='$expected' actual='$actual' $msg" >&2
    exit 1
  fi
}

assert_true() {
  local condition="$1"
  local msg="${2:-}"
  if ! eval "$condition"; then
    echo "ASSERT_TRUE failed: $condition $msg" >&2
    exit 1
  fi
}

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

export FB_HOME="$TMP_DIR/fb-home"

source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/ports.sh"

app="directus-demo"

base1="$(hash_app_base "$app")"
base2="$(hash_app_base "$app")"
assert_eq "$base1" "$base2" "hash_app_base should be deterministic"
assert_true '[[ '"$base1"' -ge 20000 && '"$base1"' -le 39999 ]]' "hash_app_base should be in range"

assert_eq "0" "$(env_offset_site prod)" "prod site offset"
assert_eq "1" "$(env_offset_api prod)" "prod api offset"
assert_eq "10" "$(env_offset_site dev)" "dev site offset"
assert_eq "11" "$(env_offset_api dev)" "dev api offset"
assert_eq "20" "$(env_offset_site staging)" "staging site offset"
assert_eq "21" "$(env_offset_api staging)" "staging api offset"

ports_file="$TMP_DIR/ports.json"
write_ports_json "$ports_file" 1234 5678
read -r site api <<<"$(read_ports_json "$ports_file")"
assert_eq "1234" "$site" "read_ports_json site"
assert_eq "5678" "$api" "read_ports_json api"

SITE_PORT=""
API_PORT=""
PORTS_SOURCE=""
resolve_ports "$app" "dev" "" "" "9000" "9001"
assert_eq "9000" "$SITE_PORT" "config ports should win"
assert_eq "9001" "$API_PORT" "config ports should win"
assert_eq "config" "$PORTS_SOURCE" "config source"

SITE_PORT=""
API_PORT=""
PORTS_SOURCE=""
resolve_ports "$app" "dev" "9100" "" "" ""
assert_eq "9100" "$SITE_PORT" "flag site port"
assert_eq "9100" "$API_PORT" "flag api defaults to site"
assert_eq "flags" "$PORTS_SOURCE" "flag source"

SITE_PORT=""
API_PORT=""
PORTS_SOURCE=""
write_ports_json "$(ports_json_path "$app" "dev")" 9200 9201
resolve_ports "$app" "dev" "" "" "" ""
assert_eq "9200" "$SITE_PORT" "ports.json site"
assert_eq "9201" "$API_PORT" "ports.json api"
assert_eq "ports.json" "$PORTS_SOURCE" "ports.json source"

SITE_PORT=""
API_PORT=""
PORTS_SOURCE=""
rm -f "$(ports_json_path "$app" "staging")"
resolve_ports "$app" "staging" "" "" "" ""
expected_base="$(hash_app_base "$app")"
expected_site=$((expected_base + 20))
expected_api=$((expected_base + 21))
assert_eq "$expected_site" "$SITE_PORT" "deterministic site"
assert_eq "$expected_api" "$API_PORT" "deterministic api"
assert_eq "deterministic" "$PORTS_SOURCE" "deterministic source"

echo "ports_test.sh OK"
