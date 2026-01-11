# Plugins

FounderBooster plugins are external executables that extend `fb` without modifying the OSS core. Plugins can be
open-source or proprietary.

## Naming and discovery

When you run `fb <name> ...`, the CLI looks for an executable named `fb-plugin-<name>` in this order:

1) `~/.founderbooster/plugins/fb-plugin-<name>`
2) Any directory on your `PATH`

If a plugin is found, `fb` executes it and passes all arguments through unchanged.

## Example

Install the example plugin:

```bash
./scripts/install-example-plugin.sh
```

Then run:

```bash
fb hello world
```

The example plugin prints its arguments and a couple of context variables passed by `fb`:

- `FOUNDERBOOSTER_VERSION`
- `FOUNDERBOOSTER_STATE_ROOT`
- `FOUNDERBOOSTER_CWD`

## Plugin install/update (Early Access)

FounderBooster supports an optional plugin installer for Early Access users. It downloads plugin manifests from
`downloads.founderbooster.com` (or your configured downloads base URL) and installs plugins into:
`~/.founderbooster/plugins/`.

Install a plugin:
```bash
fb activate <license-key>
fb plugin install ttl
```

Update plugins:
```bash
fb plugin update ttl
fb plugin update --all
```

You can also update plugins while updating core:
```bash
fb self update --with-plugins
```

List/remove plugins:
```bash
fb plugin list
fb plugin remove ttl
```
