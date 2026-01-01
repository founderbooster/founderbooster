#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "ASSERT_CONTAINS failed: missing '$needle'" >&2
    exit 1
  fi
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    echo "ASSERT_EQ failed: expected='$expected' actual='$actual' $msg" >&2
    exit 1
  fi
}

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/version.sh"

export FB_HOME="$TMP_DIR/fb-home"
mkdir -p "$FB_HOME"

# cmd_version prefers FB_HOME/VERSION
printf '0.9.9\n' >"$FB_HOME/VERSION"
assert_eq "0.9.9" "$(cmd_version)" "cmd_version reads FB_HOME/VERSION"
pretty_out="$(cmd_version_pretty)"
assert_contains "$pretty_out" "0.9.9"

# Prepare fake installed binary
BIN_DIR="$TMP_DIR/bin"
mkdir -p "$BIN_DIR"
cat >"$BIN_DIR/fb" <<'SH'
#!/usr/bin/env bash
echo "fb stub"
SH
chmod +x "$BIN_DIR/fb"
export PATH="$BIN_DIR:$PATH"

# Create app state to trigger warnings
mkdir -p "$FB_HOME/app1/dev"
printf 'tunnel: 1234\n' >"$FB_HOME/app1/dev/config.yml"

out="$(cmd_self_uninstall 2>&1)"
assert_contains "$out" "Detected app environments"
assert_contains "$out" "fb app down --purge"
if [[ -d "$FB_HOME" ]]; then
  echo "ASSERT_TRUE failed: FB_HOME should be removed" >&2
  exit 1
fi
if [[ -f "$BIN_DIR/fb" ]]; then
  echo "ASSERT_TRUE failed: fb binary should be removed" >&2
  exit 1
fi

echo "self_test.sh OK"
