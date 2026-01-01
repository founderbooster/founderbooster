#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-3000}"

PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
else
  echo "Error: python3 or python is required." >&2
  exit 1
fi

echo "Local URLs:"
echo "  http://localhost:${PORT}"
echo "  http://localhost:${PORT}/health"
echo "  http://localhost:${PORT}/api/hello"
echo "Expose with FounderBooster (Manual / port-first):"
echo "fb bootstrap --domain yourdomain.com --env prod --site-port ${PORT}"

env PORT="${PORT}" "${PYTHON_BIN}" app/server.py
