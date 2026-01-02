# Demo

Auto mode demo (Docker-based):
```bash
git clone https://github.com/founderbooster/directus-demo.git
cd directus-demo
export CLOUDFLARE_API_TOKEN=...
fb bootstrap -d <your-domain>
```

Manual mode demo (known ports):
```bash
git clone https://github.com/founderbooster/port-first-demo.git
cd port-first-demo

chmod +x scripts/run-local.sh
./scripts/run-local.sh

export CLOUDFLARE_API_TOKEN=...
fb bootstrap -d <your-domain> -s 3000
```
