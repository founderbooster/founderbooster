# FounderBooster Port-First Demo

This demo shows Manual Mode (port-first): expose an already-running local app without Docker.
You provide the port, and FounderBooster connects your live local service to a public domain.

## Prerequisites

- FounderBooster installed
- A Cloudflare account + domain on Cloudflare
- `CLOUDFLARE_API_TOKEN` exported
- Python 3 installed (already present on most macOS/Linux systems)

## Run locally

```bash
chmod +x scripts/run-local.sh
./scripts/run-local.sh
```

Confirm the local endpoints:

- http://localhost:3000
- http://localhost:3000/health
- http://localhost:3000/api/hello

## Expose publicly with FounderBooster (Manual Mode)

```bash
fb bootstrap --domain yourdomain.com --env prod --site-port 3000
```

FounderBooster will expose only the exact hostname you provide (no `api-*` or `www-*` hostnames unless explicitly requested).

Manual mode is used whenever you provide ports explicitly.

## Expected result

- https://yourdomain.com -> http://localhost:3000

## Stop / cleanup

```bash
fb app down --purge port-first-demo/prod
```

`--purge` removes local FB state only; Cloudflare DNS/tunnel remain unchanged.
To remove Cloudflare resources, delete the tunnel and DNS records for the hostnames.

## What this is / is not

- Not hosting
- Not a website builder
- Your app continues running locally
