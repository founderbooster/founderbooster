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
