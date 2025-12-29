#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

if [[ -z "${INSTALL_DIR:-}" ]]; then
  INSTALL_DIR="/usr/local/bin"
fi

if [[ ! -w "$INSTALL_DIR" ]]; then
  if [[ "$INSTALL_DIR" == "/usr/local/bin" && -d "/opt/homebrew/bin" && -w "/opt/homebrew/bin" ]]; then
    INSTALL_DIR="/opt/homebrew/bin"
  fi
fi

bin_path="$INSTALL_DIR/fb"
if [[ -f "$bin_path" ]]; then
  rm -f "$bin_path"
  echo "Removed $bin_path"
else
  echo "fb binary not found at $bin_path"
fi

if [[ -d "$HOME/.founderbooster" ]]; then
  rm -rf "$HOME/.founderbooster"
  echo "Removed ~/.founderbooster"
fi

echo "FounderBooster uninstalled."
