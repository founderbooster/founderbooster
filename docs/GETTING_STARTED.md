# Getting Started with FounderBooster

## What you’ll need
- A local app running on your machine
    - With Docker or Docker Compose (**optional**, enables auto-detection), or
    - Without Docker (any app listening on a local port)
- A domain you own
- A Cloudflare account (**free tier is sufficient**)
- macOS or Linux (Windows not supported yet)

Optional (Auto mode only):
- Docker or Docker Desktop

## What FounderBooster does
FounderBooster exposes your existing local app, adds DNS and secure access for this app only, and leaves your app and repo unchanged. It does not host or rebuild your app, and it does not touch unrelated DNS records.

## Install FounderBooster
Run the installer:

```bash
curl -fsSL https://downloads.founderbooster.com/install.sh | bash
```

Confirm the CLI is on your PATH:

```bash
fb --version
```

## Need a Cloudflare token?
Create a least-privilege token using the guided flow:

```bash
fb cloudflare token create
```

## Auto mode quickstart (Docker)
Auto mode is the default for Docker and docker-compose apps. FB detects published ports for you.

Example using the demo repo:

```bash
git clone https://github.com/founderbooster/directus-demo.git
cd directus-demo

export CLOUDFLARE_API_TOKEN=...
fb bootstrap -d yourdomain.com
```

## Manual mode quickstart (ports)
Manual mode is for apps that are already running locally when you know the ports. FB manages DNS and the tunnel only.

Example for a site on 3000:

```bash
export CLOUDFLARE_API_TOKEN=...
fb bootstrap -d yourdomain.com -s 3000
```

## Managing your app
Use these commands after you have bootstrapped at least once:

```bash
fb app list
fb app status
fb app down
fb app down --purge
```
`fb app down --purge` stops the tunnel and removes local FounderBooster state for that app and environment. Cloudflare remains unchanged. To fully remove it, delete the tunnel and DNS records in Cloudflare.

## Notes
- Your app runs on your laptop, so sleep mode stops it from being reachable.
- FounderBooster is designed for launches, demos, and early users, not HA production.
- Need help during early access? Email support@founderbooster.com with the command you ran and the last few lines of output.
