# FAQ

## How does auto mode choose ports?

Auto mode tries to detect published ports from Docker.

- If it finds 1 port, it uses that for both site and api.
- If it finds 2 ports, it uses the first for site and the second for api.
- If it finds more than 2 ports, it does not guess. It warns and asks you to pass `-s` and `-i`.

If auto-detect cannot find ports, it falls back to deterministic ports based on app/env.

## What should I do if my compose file exposes multiple ports?

Pick the two ports you want and run:

```
fb bootstrap -s <site-port> -i <api-port> -d <domain>
```

If your app is already running, manual mode is recommended:

```
fb bootstrap -s <site-port> -i <api-port> -d <domain>
```

## Why does manual mode default to prod?

When you pass `-s`/`-i`, FB treats it as manual mode and defaults `-e` to `prod` unless you specify it.

## Why does auto mode only expose the root hostname by default?

To avoid unexpected hostnames, auto mode defaults to `root` only. Use `-H` to add `api` or `www`.

## How do I capture machine-readable output from fb bootstrap?

At the end of a successful `fb bootstrap`, FB prints stable `FB_` key/value lines to stdout for automation.

Example:

```
FB_APP=directus-demo
FB_ENV=dev
FB_ZONE_APEX=founderbooster.online
FB_TUNNEL_NAME=directus-demo-dev-ebb7
FB_TUNNEL_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
FB_FQDNS=ttl.founderbooster.online,api.ttl.founderbooster.online
FB_STATE_DIR=/Users/jack/.founderbooster/directus-demo/dev
```

If you want to suppress these lines, pass `--no-machine` or `--no-print-env`.

## Where is the durable state stored?

After a successful `fb bootstrap`, FB writes `state.json` to `~/.founderbooster/<app>/<env>/`. This file is a stable interface for plugins and automation and contains non-secret metadata like app/env, zone apex, FQDNs, tunnel name/id, and timestamps.

## What is the app lifecycle?

Lifecycle commands map to these states:

- Publish: `fb bootstrap`
- Unpublish (paused): `fb app down <app>/<env>` (removes DNS + stops tunnel, keeps local state)
- Re-publish: `fb app up <app>/<env>`
- Purge: `fb app down <app>/<env> --purge` (deletes local state; bootstrap required again)

TTL-based auto-unpublish is optional Early Access (`fb ttl ...`) and not required for core usage.

## Publish vs runtime (why 502 happens)

Publishing controls exposure (DNS + tunnel + connector). Your app runtime (Docker or a local process) is separate.
If the tunnel is up but the app is not running, visitors will see a 502.

Flags:

- Unpublish only (default): `fb app down <app>/<env>`
- Unpublish + stop runtime: `fb app down <app>/<env> --stop-runtime`
- Explicit unpublish-only aliases: `--unpublish-only` or `--tunnel-only`
- Re-publish: `fb app up <app>/<env>`

If you need the old default behavior (down stops runtime), set:
`FOUNDERBOOSTER_APP_DOWN_LEGACY_DEFAULT=1`
