# Linux Prerequisites

These commands install the core dependencies needed for FounderBooster on Linux.
Examples below target Ubuntu/Debian. Adjust for your distro as needed.

## Core requirements

```bash
sudo apt-get update
sudo apt-get install -y jq curl

# Cloudflare tunnel client
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloudflare.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
sudo apt-get update
sudo apt-get install -y cloudflared
```

## Auto mode only (Docker + Compose)

```bash
sudo apt-get install -y docker.io docker-compose-plugin
sudo usermod -aG docker "$USER"
```

Log out and back in after adding yourself to the docker group.

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
