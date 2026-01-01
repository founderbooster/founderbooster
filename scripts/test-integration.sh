#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0
TOTAL=0
PASSED=0

if [[ "${FB_INTEGRATION:-}" != "1" ]]; then
  echo "Integration tests are opt-in. Run with FB_INTEGRATION=1 ./scripts/test-integration.sh" >&2
  exit 1
fi

if [[ -t 1 ]]; then
  COLOR_RESET="\033[0m"
  COLOR_GREEN="\033[0;32m"
  COLOR_RED="\033[0;31m"
  COLOR_BOLD="\033[1m"
else
  COLOR_RESET=""
  COLOR_GREEN=""
  COLOR_RED=""
  COLOR_BOLD=""
fi

log() { printf '%b\n' "$*"; }
has_shell_error() {
  local text="$1"
  printf '%s\n' "$text" | grep -Eq '(^|/).*: line [0-9]+:'
}

log "🧪 ${COLOR_BOLD}Integration Tests${COLOR_RESET}"
log "Location: tests/integration"
log "Keep temp output: KEEP_TMP=1 FB_INTEGRATION=1 ./scripts/test-integration.sh"
log ""

for test_file in "$ROOT_DIR/tests/integration/"*.sh; do
  if [[ ! -f "$test_file" ]]; then
    echo "No integration tests found in tests/integration/." >&2
    exit 1
  fi
  test_name="$(basename "$test_file")"
  if [[ "$test_name" == _* ]]; then
    continue
  fi
  TOTAL=$((TOTAL + 1))
  log "🔹 ${COLOR_BOLD}${test_name}${COLOR_RESET}"
  if output="$(bash "$test_file" 2>&1)"; then
    if has_shell_error "$output"; then
      FAILED=1
      if [[ -n "$output" ]]; then
        printf '%s\n' "$output" | sed 's/^/  /'
      fi
      log "  ${COLOR_RED}FAIL${COLOR_RESET} ❌"
    else
      PASSED=$((PASSED + 1))
      if [[ -n "$output" ]]; then
        printf '%s\n' "$output" | sed 's/^/  /'
      fi
      log "  ${COLOR_GREEN}PASS${COLOR_RESET} ✅"
    fi
  else
    FAILED=1
    if [[ -n "$output" ]]; then
      printf '%s\n' "$output" | sed 's/^/  /'
    fi
    log "  ${COLOR_RED}FAIL${COLOR_RESET} ❌"
  fi
done

log "📊 ${COLOR_BOLD}Summary${COLOR_RESET}"
log "  Total:  $TOTAL"
log "  Passed: ${COLOR_GREEN}$PASSED${COLOR_RESET}"
log "  Failed: ${COLOR_RED}$((TOTAL - PASSED))${COLOR_RESET}"

if [[ "$FAILED" -ne 0 ]]; then
  log "${COLOR_RED}Integration tests failed.${COLOR_RESET}" >&2
  exit 1
fi

log "${COLOR_GREEN}Integration tests passed.${COLOR_RESET} 🎉"
