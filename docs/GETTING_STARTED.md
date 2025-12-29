# Getting Started with FounderBooster

## What you’ll need
- A local app that runs via Docker (docker compose or docker run)
- A domain you own
- A Cloudflare account
- Docker Desktop running
- macOS or Linux (Windows not supported yet)

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
fb bootstrap --domain yourdomain.com --env dev
```

## Manual mode quickstart (ports)
Manual mode is for apps that are already running locally when you know the ports. FB manages DNS and the tunnel only.

Example for a site on 3000:

```bash
export CLOUDFLARE_API_TOKEN=...
fb bootstrap --domain yourdomain.com --site-port 3000
```

By default, Manual mode exposes only the root domain. To add API or WWW hostnames, pass `--hosts root,api,www`.
In Manual (port-first) mode, `--env` primarily controls the public hostname and isolates FounderBooster state. Your app process remains your responsibility.
If you’re in Manual mode and only need one shareable URL, you can treat everything as `prod` and ignore env entirely.
If you omit `--env` in Manual mode, FB defaults to `prod`.

## Managing your app
Use these commands after you have bootstrapped at least once:

```bash
fb app status
```

```bash
fb app down
```

```bash
fb app down --purge
```

`fb app down --purge` stops the tunnel and removes local FounderBooster state for that app and environment. Cloudflare remains unchanged. To fully remove it, delete the tunnel and DNS records in Cloudflare.

## Notes
- Your app runs on your laptop, so sleep mode stops it from being reachable.
- FounderBooster is designed for launches, demos, and early users, not HA production.
- Need help during early access? Email support@founderbooster.com with the command you ran and the last few lines of output.
