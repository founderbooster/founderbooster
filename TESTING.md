# Testing

Run unit tests:
```bash
./scripts/test-unit.sh
```

Run integration tests (opt-in):
```bash
FB_INTEGRATION=1 ./scripts/test-integration.sh
```

Run E2E tests (opt-in, requires Cloudflare + Docker):
```bash
FB_E2E=1 \
  CLOUDFLARE_API_TOKEN=... \
  E2E_DOMAIN=e2e.example.com \
  E2E_AUTO_APP_DIR=/path/to/directus-demo \
  E2E_MANUAL_APP_DIR=/path/to/port-first-demo \
  E2E_MANUAL_START_CMD="./scripts/run-local.sh" \
  ./scripts/test-e2e.sh
```

Optional overrides:
```bash
E2E_ENV=dev
E2E_HOSTS=root
E2E_AUTO_DOMAIN=auto.e2e.example.com
E2E_MANUAL_DOMAIN=manual.e2e.example.com
E2E_MANUAL_PORT=3000
KEEP_TMP=1
```

Recommendation:
```bash
# Use distinct hostnames for auto vs manual to avoid tunnel collisions.
E2E_AUTO_DOMAIN=auto.e2e.example.com
E2E_MANUAL_DOMAIN=manual.e2e.example.com
```

CI note:
```bash
# Example: run with secrets and a docker-enabled runner.
FB_E2E=1 \
  CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" \
  E2E_DOMAIN=e2e.example.com \
  E2E_AUTO_DOMAIN=auto.e2e.example.com \
  E2E_MANUAL_DOMAIN=manual.e2e.example.com \
  E2E_AUTO_APP_DIR="$RUNNER_TEMP/directus-demo" \
  E2E_MANUAL_APP_DIR="$RUNNER_TEMP/port-first-demo" \
  E2E_MANUAL_START_CMD="./scripts/run-local.sh" \
  ./scripts/test-e2e.sh
```
