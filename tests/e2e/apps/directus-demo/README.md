# Directus Demo — Powered by FounderBooster

Launch a real Directus app from your laptop to **dev and prod domains simultaneously**, without editing Docker files or learning infrastructure.

This repo demonstrates how founders can run Directus locally and make it publicly accessible using **FounderBooster (`fb`)**, with dev and prod environments running side-by-side.

---

## What you get

- **Dev** exposed at: `https://dev.<your-domain>`
- **Prod** exposed at: `https://<your-domain>`
- Secure public access with automatic DNS + SSL
- Zero Docker Compose changes
- Automatic port detection per environment
- Dev and prod running **in parallel on the same machine**

---

## Prerequisites

- Docker Desktop running
- `fb` installed
- `cloudflared`, `jq`
- `CLOUDFLARE_API_TOKEN` exported

> You do **not** need to configure tunnels or DNS manually.

---

## Mental model (important)

- **One directory = one environment**
- **One environment = one public domain**
- FounderBooster handles routing, tunnels, and isolation automatically

This design allows dev and prod to run at the same time without port conflicts.

---

## Repo layout

This repo uses a **single Docker Compose file**.

To run multiple environments, check out the repo into **separate directories** so each environment has its own Docker project and runtime state.

Example layout:

    ~/code/directus-demos/dev/directus-demo
    ~/code/directus-demos/prod/directus-demo

---

## Setup

Clone the repo twice (once per environment):

    git clone https://github.com/founderbooster/directus-demo ~/code/directus-demos/dev/directus-demo
    git clone https://github.com/founderbooster/directus-demo ~/code/directus-demos/prod/directus-demo

Check out branches:

    cd ~/code/directus-demos/dev/directus-demo
    git checkout main

    cd ~/code/directus-demos/prod/directus-demo
    git checkout prod

---

## Quickstart — dev

    export CLOUDFLARE_API_TOKEN=...
    cd ~/code/directus-demos/dev/directus-demo

    fb bootstrap --env dev --domain example.com

Expected URLs:

- https://dev.example.com
- https://api-dev.example.com

---

## Quickstart — prod

    export CLOUDFLARE_API_TOKEN=...
    cd ~/code/directus-demos/prod/directus-demo

    fb bootstrap --env prod --domain example.com

Expected URLs:

- https://example.com
- https://api.example.com

---

## Running dev + prod in parallel

FounderBooster automatically detects published Docker ports per environment and isolates them internally. This allows multiple environments to run side-by-side without editing compose files or hard-coding ports.

---

## Useful commands

    fb app list
    fb app status
    fb app down directus-demo/dev
    fb app down directus-demo/prod --purge

---

## Troubleshooting

If you need to pin ports manually:

    fb bootstrap --site-port 9055 --api-port 9055 --env prod --domain example.com

---

## How it works (brief)

FounderBooster securely exposes your local Docker services to the public internet using a managed edge tunnel and automatic DNS + SSL configuration. Your app continues to run locally; no code or container changes are required.

---

## Notes

This repo is intentionally minimal and app-agnostic.  
Directus runs locally via Docker.  
FounderBooster handles public access.

---

## Learn more

- FounderBooster CLI: `fb --help`
- Core idea: **From localhost to live — without changing your app.**
