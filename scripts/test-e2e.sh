#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0
TOTAL=0
PASSED=0

if [[ "${FB_E2E:-}" != "1" ]]; then
  echo "E2E tests are opt-in. Run with FB_E2E=1 ./scripts/test-e2e.sh" >&2
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

log "🧪 ${COLOR_BOLD}E2E Tests${COLOR_RESET}"
log "Location: tests/e2e"
log "Keep temp output: KEEP_TMP=1 FB_E2E=1 ./scripts/test-e2e.sh"
log "Skip teardown: E2E_SKIP_TEARDOWN=1 FB_E2E=1 ./scripts/test-e2e.sh"
log "Domain vars: set E2E_DOMAIN or per-test E2E_AUTO_DOMAIN/E2E_MANUAL_DOMAIN"
log "Default apps: tests/e2e/apps/directus-demo (auto), tests/e2e/apps/port-first-demo (manual)"
log ""

for test_file in "$ROOT_DIR/tests/e2e/"*.sh; do
  if [[ ! -f "$test_file" ]]; then
    echo "No e2e tests found in tests/e2e/." >&2
    exit 1
  fi
  test_name="$(basename "$test_file")"
  if [[ "$test_name" == _* ]]; then
    continue
  fi
  TOTAL=$((TOTAL + 1))
  log "🔹 ${COLOR_BOLD}${test_name}${COLOR_RESET}"
  tmp_out="$(mktemp)"
  (
    while true; do
      sleep 10
      if [[ -f "$tmp_out.pid" ]]; then
        pid="$(cat "$tmp_out.pid" 2>/dev/null || true)"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
          log "  INFO: still running ${test_name}..."
        else
          break
        fi
      else
        break
      fi
    done
  ) &
  heartbeat_pid=$!
  bash "$test_file" >"$tmp_out" 2>&1 &
  test_pid=$!
  printf '%s\n' "$test_pid" >"$tmp_out.pid"
  wait "$test_pid"
  status=$?
  rm -f "$tmp_out.pid"
  if kill -0 "$heartbeat_pid" 2>/dev/null; then
    kill "$heartbeat_pid" 2>/dev/null || true
  fi
  output="$(cat "$tmp_out")"
  rm -f "$tmp_out"
  if [[ "$status" -eq 0 ]]; then
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
  log "${COLOR_RED}E2E tests failed.${COLOR_RESET}" >&2
  exit 1
fi

log "${COLOR_GREEN}E2E tests passed.${COLOR_RESET} 🎉"
