# Usage

## Modes

FounderBooster supports Auto mode (default, Docker-first) and Manual mode (port-first). Auto mode detects published
Docker ports. Manual mode requires `-s` and optionally `-i` and defaults to `prod` if you omit `-e`.
In Manual mode, `-e` mainly shapes the public hostname and isolates local state; see `docs/MODES.md`.

## Environments and domains

FounderBooster uses `-e` to shape domains by default:

- `-e prod -d example.com` -> `https://example.com` and `https://api.example.com`
- `-e dev -d example.com` -> `https://dev.example.com` and `https://api-dev.example.com`
- `-e dev -d dev.example.com` -> `https://dev.example.com` and `https://api-dev.example.com`

For subdomains like `demo.example.com`, the API hostname becomes `api-demo.example.com`
(and `www-demo.example.com` if enabled). This avoids 4+ level subdomains in MVP.

FounderBooster typically uses shallow hostnames like `api-dev.example.com` to reduce SSL/DNS friction; domains purchased
via Cloudflare usually work out of the box, while domains from other registrars in most cases require pointing
nameservers to Cloudflare first. See [docs/DNS_AND_TUNNEL_FLOW.md](docs/DNS_AND_TUNNEL_FLOW.md) for a high-level explanation.

If you run multiple environments in parallel (dev/staging), keep each env in a
separate repo/branch directory. FounderBooster auto-detects Docker published ports
and saves them per env in `~/.founderbooster/<app>/<env>/ports.json`.

## Optional App Configuration

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

## Expert Mode (planned)

Advanced multi-service routing and custom ingress configuration will be introduced as an optional plugin in a future
release.
