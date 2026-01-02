# macOS Prerequisites

These commands install the core dependencies needed for FounderBooster on macOS.

## Core requirements

```bash
brew install cloudflared jq
```

## Auto mode only (Docker + Compose)

Install Docker Desktop from:
https://www.docker.com/products/docker-desktop/

## Cloudflare API token

Create a Cloudflare API token with these permissions:

- Account: Cloudflare Tunnel = Edit
- Zone: DNS = Edit
- Zone: Zone = Read
- Zone: Cache Rules / Rulesets = Edit (optional for --no-cache)

Steps:

1) Log in to Cloudflare and go to:
   https://dash.cloudflare.com/profile/api-tokens
2) Click "Create Token" (custom token).
3) Add the permissions above and scope to the account + zone you plan to use.
4) Create the token and export it:

```bash
export CLOUDFLARE_API_TOKEN=your_token_here
```
