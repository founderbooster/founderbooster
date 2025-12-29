#!/usr/bin/env bash
set -euo pipefail
umask 022

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="full"

usage() {
  cat <<'EOF'
Usage: ./install.sh [--full|--bin-only|--runtime-only]

Options:
  --full          Install fb binary and runtime assets (default)
  --bin-only      Install fb binary only
  --runtime-only  Install runtime assets only
  -h, --help      Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    --full)
      MODE="full"
      ;;
    --bin-only)
      MODE="bin-only"
      ;;
    --runtime-only)
      MODE="runtime-only"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

select_bin_dir() {
  local dir
  for dir in "/usr/local/bin" "/opt/homebrew/bin" "$HOME/.local/bin"; do
    if [[ ! -d "$dir" ]]; then
      mkdir -p "$dir" 2>/dev/null || true
    fi
    if [[ -w "$dir" ]]; then
      echo "$dir"
      return 0
    fi
  done
  return 1
}

install_bin() {
  local bin_dir
  bin_dir="$(select_bin_dir)" || {
    echo "ERROR: Could not find a writable bin directory." >&2
    echo "Try running with sudo or add ~/.local/bin to PATH." >&2
    exit 1
  }
  cp "$SCRIPT_DIR/cmd/fb" "$bin_dir/fb"
  chmod +x "$bin_dir/fb"
  BIN_PATH="$bin_dir/fb"
  echo "Installed fb to $BIN_PATH"
  if [[ "$bin_dir" == "$HOME/.local/bin" ]]; then
    echo "Note: add $HOME/.local/bin to PATH to run fb easily."
  fi
}

install_runtime() {
  local base_dir="$HOME/.founderbooster"
  local runtime_dir="$base_dir/runtime"
  mkdir -p "$runtime_dir"
  rm -rf "$runtime_dir/lib" "$runtime_dir/templates"
  cp -R "$SCRIPT_DIR/lib" "$runtime_dir/lib"
  cp -R "$SCRIPT_DIR/templates" "$runtime_dir/templates"
  if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
    cp "$SCRIPT_DIR/VERSION" "$base_dir/VERSION"
  fi
  echo "Installed runtime to $runtime_dir"
}

smoke_check() {
  local bin_path="$1"
  if [[ -z "$bin_path" ]]; then
    bin_path="$(command -v fb || true)"
  fi
  if [[ -z "$bin_path" ]]; then
    echo "Smoke check skipped: fb not found on PATH."
    return 0
  fi
  if ! "$bin_path" --version >/dev/null 2>&1; then
    echo "WARN: 'fb --version' failed. Ensure runtime exists at ~/.founderbooster/runtime." >&2
  fi
}

BIN_PATH=""
case "$MODE" in
  bin-only)
    install_bin
    ;;
  runtime-only)
    install_runtime
    ;;
  full)
    install_bin
    install_runtime
    ;;
esac

smoke_check "$BIN_PATH"
