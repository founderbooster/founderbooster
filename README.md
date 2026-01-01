# FounderBooster (`fb`)

Open-source CLI that exposes a local app on your own domain using Cloudflare Tunnel + DNS + SSL.
It does not host your app, provide a PaaS, or impose a framework.
No manual Cloudflare dashboard setup required.
No copying cert.pem.

---

## What FounderBooster Is

- An OSS CLI for exposing a local app on your own domain
- App-agnostic (works with any stack)
- Cloudflare-powered (tunnels + DNS + SSL)
- Useful for launches, demos, and early users

## What FounderBooster Does / Does Not Touch

Does:
- Create or update DNS records for the app hostnames it manages
- Create or reuse a Cloudflare tunnel for the app/env
- Write local state under `~/.founderbooster/<app>/<env>/`

Does not:
- Modify other DNS records in your zone
- Edit your app code or Docker files
- Provide HA or production hosting (reliability depends on Cloudflare Tunnel + your machine uptime)

---

## What FounderBooster Is NOT

- ❌ Not a SaaS framework
- ❌ Not an app template
- ❌ Not a hosting provider
- ❌ Not coupled to any product (SitesInsight, PayOpsCopilot, etc.)

Your app stays your app.

---

## Quickstart

Auto mode (Docker, detects published ports):
```bash
cd <your-app-repo>
export CLOUDFLARE_API_TOKEN=...
fb bootstrap --domain <your-domain> --env dev
```

Manual mode (known ports):
```bash
cd <your-app-repo>
# start your app running at http://localhost:<part>
export CLOUDFLARE_API_TOKEN=...
fb bootstrap --domain <your-domain> --site-port <port>
```

## Try a Demo (Optional)

See [DEMO.md](DEMO.md).

## Tests

See [TESTING.md](TESTING.md).

## How it works

FounderBooster creates or reuses a Cloudflare tunnel, updates DNS + SSL, and stores local state per app/env.

For a high-level view of traffic flow and security boundaries, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

### Modes

FounderBooster supports Auto mode (default, Docker-first) and Manual mode (port-first). Auto mode detects published
Docker ports. Manual mode requires `--site-port` and optionally `--api-port` and defaults to `prod` if you omit `--env`.
In Manual mode, `--env` mainly shapes the public hostname and isolates local state; see `docs/MODES.md`.

### Environments and domains

FounderBooster uses `--env` to shape domains by default:

- `--env prod --domain example.com` → `https://example.com` and `https://api.example.com`
- `--env dev --domain example.com` → `https://dev.example.com` and `https://api-dev.example.com`
- `--env dev --domain dev.example.com` → `https://dev.example.com` and `https://api-dev.example.com`

For subdomains like `demo.example.com`, the API hostname becomes `api-demo.example.com`
(and `www-demo.example.com` if enabled). This avoids 4+ level subdomains in MVP.

FounderBooster typically uses shallow hostnames like `api-dev.example.com` to reduce SSL/DNS friction; domains purchased
via Cloudflare usually work out of the box, while domains from other registrars in most cases require pointing
nameservers to Cloudflare first. See [docs/DNS_AND_TUNNEL_FLOW.md](docs/DNS_AND_TUNNEL_FLOW.md) for a high-level explanation.

If you run multiple environments in parallel (dev/staging), keep each env in a
separate repo/branch directory. FounderBooster auto-detects Docker published ports
and saves them per env in `~/.founderbooster/<app>/<env>/ports.json`.

### Optional App Configuration

Apps may include a founderbooster.yml at repo root.

```yaml
app: myapp
domains:
  prod: myapp.com
ports:
  prod:
    site: 8080
    api: 8000
```

If omitted, FounderBooster uses deterministic defaults.

### Common Commands

```bash
fb bootstrap
fb doctor
fb version
fb --version
fb self update
fb self uninstall
fb license status
fb activate <license-key>
```

### Plugins (optional)

Plugins are external executables dispatched by subcommand name and are not required for core usage. See
[docs/PLUGINS.md](docs/PLUGINS.md).

---

## Requirements

Core requirements:
- macOS
- cloudflared (`brew install cloudflared`)
- jq (`brew install jq`)
- Cloudflare account + API token

Auto mode only:
- Docker
- Docker Compose

---

## Installation

Build from source (OSS):
```bash
git clone https://github.com/founderbooster/founderbooster.git
cd founderbooster
./install.sh
```

`./install.sh` does a dev-friendly local install (binary + runtime assets). You can use `--bin-only` or `--runtime-only`
if you want to install just one piece.

Optional installer convenience:
```bash
curl -fsSL https://downloads.founderbooster.com/install.sh | bash
```

The installer is optional and not required to use the OSS core.
GitHub tags are source snapshots; release binaries and updates are driven by
https://downloads.founderbooster.com/manifest.json.

## License / Early Access

OSS is fully usable without a license. Core flows (Auto + Manual `fb bootstrap`) are fully OSS in v0.1.0. Early Access is
optional and includes prebuilt binaries, the one-line installer, automatic updates, and early access to advanced
plugin workflows.

```bash
fb license status
fb activate <license-key>
```

Activation in v0.1.0 uses `fb activate <license-key>`.

## Expert Mode (planned)

Advanced multi-service routing and custom ingress configuration will be introduced as an optional plugin in a future
release.

## Why pay if OSS?

## Early Access

FounderBooster is fully open source (MIT). Core workflows are always usable without a license.

**Early Access** is a one-time purchase intended for users who want convenience and to invest early in the roadmap. It includes:

- Prebuilt, signed binaries
- One-line installer and `fb self update`
- Priority fixes and early feedback loop
- **All plugins and plugin workflows released during the Early Access period**

Early Access applies to features shipped while Early Access is active.  
Future major capabilities may be released as separate plugins or tiers.

Learn more: https://founderbooster.com/early-access

## License

[MIT](LICENSE)
