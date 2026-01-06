#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_helpers.sh"

integration_init
source_libs

app="app1"
env="dev"
compose_dir="$TMP_DIR/app-repo"
other_dir="$TMP_DIR/other-repo"
mkdir -p "$compose_dir" "$other_dir"
printf 'services: {}\n' >"$compose_dir/docker-compose.yml"

mkdir -p "$FB_HOME/$app/$env"
printf '%s\n' "$compose_dir" >"$FB_HOME/$app/$env/compose.dir"

capture_file="$TMP_DIR/docker_pwd"
cat >"$STUB_BIN/docker" <<SH
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1" == "compose" && "\$2" == "down" ]]; then
  pwd >"$capture_file"
  echo "No resource found to remove"
  exit 0
fi
exit 0
SH
chmod +x "$STUB_BIN/docker"

cf_ensure_zone() { CF_ZONE_ID="zone-123"; CF_ACCOUNT_ID="acct-123"; }
cf_delete_dns_record() { return 0; }

cd "$other_dir"
output="$(cmd_app_down --app "$app" --env "$env" --stop-runtime 2>&1)"
OUTPUT_DUMP="$output"

assert_true "[[ -f \"$capture_file\" ]]" "docker compose down should run"
assert_true "[[ \"$(cat "$capture_file")\" == \"$compose_dir\" ]]" "compose down should use recorded dir"

echo "app_down_compose_dir.sh OK"
