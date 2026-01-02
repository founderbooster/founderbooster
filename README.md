# FounderBooster (`fb`)

Open-source CLI that exposes a locally running app to your own domain using Cloudflare Tunnel — without hosting it, changing your app, or opening inbound ports.

It does not provide a PaaS or impose a framework.
No manual Cloudflare dashboard setup.
No certificate files to copy or manage.

---

## What FounderBooster Is

- An OSS CLI for exposing a local app on your own domain
- App-agnostic (works with any stack)
- Cloudflare-powered (tunnels + DNS + SSL)
- Useful for launches, demos, internal previews, and early users

## What FounderBooster Does / Does Not Touch

Does:
- Create or update DNS records for the app hostnames it manages
- Create or reuse a Cloudflare tunnel for the app/env
- Write local state under `~/.founderbooster/<app>/<env>/`

Does not:
- Modify other DNS records in your zone
- Edit your app code or Docker files
- Provide HA or production hosting (reliability depends on Cloudflare Tunnel + your machine uptime)
- Require inbound firewall or router changes

---

## What FounderBooster Is NOT

- ❌ Not a SaaS framework
- ❌ Not an app template
- ❌ Not a hosting provider
- ❌ Not a reverse proxy you need to operate or secure

Your app stays your app.

---

## Quickstart

Run fb bootstrap from your app directory. FounderBooster detects your running app and maps it to your domain.

Auto mode (Docker, detects published ports):
```bash
cd <your-app-repo>
export CLOUDFLARE_API_TOKEN=...
fb bootstrap -d <your-domain>
```

Manual mode (known ports):
```bash
cd <your-app-repo>
# start your app running at http://localhost:<port>
export CLOUDFLARE_API_TOKEN=...
fb bootstrap -d <your-domain> -s <port>
```

## How it works

FounderBooster acts as a control plane over Cloudflare and your local runtime: it creates or reuses a Cloudflare tunnel, updates DNS + SSL, and stores local state per app/env.

For a high-level view of traffic flow and security boundaries, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
For usage details, see [docs/USAGE.md](docs/USAGE.md). For common questions, see [docs/FAQ.md](docs/FAQ.md).


### Common Commands

```bash
fb bootstrap
fb doctor
fb version
fb self uninstall

# optional (Early Access only)
fb self update
fb license status
fb activate <license-key>
```

### Plugins (optional)

Plugins are external executables dispatched by subcommand name and are not required for core usage. The core CLI never depends on paid plugins to function. See [docs/PLUGINS.md](docs/PLUGINS.md).

---

## Requirements

FounderBooster runs on macOS and Linux. See the platform setup guides:

- macOS: [docs/MACOS_PREREQS.md](docs/MACOS_PREREQS.md)
- Linux: [docs/LINUX_PREREQS.md](docs/LINUX_PREREQS.md)

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
All installation methods result in the same open-source core functionality.
GitHub tags are source snapshots; release binaries and updates are driven by
https://downloads.founderbooster.com/manifest.json.

## License & Early Access

FounderBooster is fully open source (MIT).  
All core workflows — including Auto and Manual `fb bootstrap` — are always usable **without a license**.

**Early Access** is optional and intended for users who want convenience features and to invest early in the roadmap.

It includes:

- Prebuilt, signed binaries
- One-line installer and `fb self update`
- Early access to advanced plugins and workflows
- Priority fixes and early feedback loop
- **All plugins and plugin workflows released during the Early Access period**

Early Access applies only to features shipped while Early Access is active.  
Future major capabilities may be released as separate plugins or tiers.

### License Activation (Early Access only)

```bash
fb license status
fb activate <license-key>
```

Activation in v0.1 uses an offline, signed license key.
No network calls are required for validation.

Learn more: https://founderbooster.com/early-access

## License

[MIT](LICENSE)
