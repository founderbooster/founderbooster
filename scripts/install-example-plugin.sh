#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PLUGIN_DIR="$HOME/.founderbooster/plugins"
mkdir -p "$PLUGIN_DIR"
cp "$ROOT_DIR/plugins/examples/fb-plugin-hello" "$PLUGIN_DIR/fb-plugin-hello"
chmod +x "$PLUGIN_DIR/fb-plugin-hello"

echo "Installed example plugin to $PLUGIN_DIR/fb-plugin-hello"
echo "Try: fb hello world"
