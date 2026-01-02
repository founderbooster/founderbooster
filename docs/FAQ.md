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
