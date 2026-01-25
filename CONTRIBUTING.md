# Contributing

Thanks for your interest in contributing!

## Development setup

### Prerequisites

- Crystal (see `shard.yml` for the minimum version)
- `shards`
- Optional (for integration/e2e tests): `just`, `python3`, `pipx`, `uv`

### Install dependencies

```bash
shards install
```

## Common commands

This project uses `just`.

```bash
just fmt
just fmt-check
just lint
just test
just test-all
```

## Pull requests

- Keep changes focused and small.
- Run formatting, lint, and unit tests before opening a PR.
- If you change behavior, add/adjust specs.

## Reporting security issues

If you believe you've found a security issue, please avoid filing a public issue. Contact the maintainers privately.
