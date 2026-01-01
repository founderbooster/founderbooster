#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0
TOTAL=0
PASSED=0

if [[ -t 1 ]]; then
  COLOR_RESET="\033[0m"
  COLOR_GREEN="\033[0;32m"
  COLOR_RED="\033[0;31m"
  COLOR_YELLOW="\033[0;33m"
  COLOR_BOLD="\033[1m"
else
  COLOR_RESET=""
  COLOR_GREEN=""
  COLOR_RED=""
  COLOR_YELLOW=""
  COLOR_BOLD=""
fi

log() { printf '%b\n' "$*"; }

log "🧪 ${COLOR_BOLD}Unit Tests${COLOR_RESET}"
log "Location: tests/unit"
log ""

for test_file in "$ROOT_DIR/tests/unit/"*.sh; do
  if [[ ! -f "$test_file" ]]; then
    echo "No unit tests found in tests/unit/." >&2
    exit 1
  fi
  TOTAL=$((TOTAL + 1))
  test_name="$(basename "$test_file")"
  log "🔹 ${COLOR_BOLD}${test_name}${COLOR_RESET}"
  if output="$(bash "$test_file" 2>&1)"; then
    PASSED=$((PASSED + 1))
    if [[ -n "$output" ]]; then
      printf '%s\n' "$output" | sed 's/^/  /'
    fi
    log "  ${COLOR_GREEN}PASS${COLOR_RESET} ✅"
  else
    FAILED=1
    if [[ -n "$output" ]]; then
      printf '%s\n' "$output" | sed 's/^/  /'
    fi
    log "  ${COLOR_RED}FAIL${COLOR_RESET} ❌"
  fi
  # no blank line between tests
done

log "📊 ${COLOR_BOLD}Summary${COLOR_RESET}"
log "  Total:  $TOTAL"
log "  Passed: ${COLOR_GREEN}$PASSED${COLOR_RESET}"
log "  Failed: ${COLOR_RED}$((TOTAL - PASSED))${COLOR_RESET}"

if [[ "$FAILED" -ne 0 ]]; then
  log "${COLOR_RED}Unit tests failed.${COLOR_RESET}" >&2
  exit 1
fi

log "${COLOR_GREEN}Unit tests passed.${COLOR_RESET} 🎉"
