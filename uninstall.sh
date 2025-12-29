#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="$PREFIX/bin"

rm -f "$BIN_DIR/fb"
echo "Removed fb from $BIN_DIR/fb"
