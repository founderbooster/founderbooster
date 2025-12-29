#!/usr/bin/env bash
set -euo pipefail

find_plugin() {
  local name="$1"
  local plugin_name="fb-plugin-$name"
  local local_path="$FB_HOME/plugins/$plugin_name"
  if [[ -x "$local_path" ]]; then
    echo "$local_path"
    return 0
  fi
  if command -v "$plugin_name" >/dev/null 2>&1; then
    command -v "$plugin_name"
    return 0
  fi
  return 1
}

try_plugin_dispatch() {
  local name="$1"
  shift || true
  local plugin_path
  if ! plugin_path="$(find_plugin "$name" 2>/dev/null)"; then
    return 1
  fi
  export FOUNDERBOOSTER_VERSION
  FOUNDERBOOSTER_VERSION="$(cmd_version)"
  export FOUNDERBOOSTER_STATE_ROOT="$FB_HOME"
  export FOUNDERBOOSTER_CWD="$PWD"
  exec "$plugin_path" "$@"
}
