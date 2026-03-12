# Contributing

Thanks for contributing to Immich Video Slideshow.

## Development Areas

- `tvos-app/` for the native tvOS player
- `web-player/` for the PHP web slideshow player

## Workflow

1. Create a focused branch for your change.
2. Keep pull requests small and scoped.
3. Update documentation for any behavior/config changes.
4. Add or update tests where practical.

## Before Opening a PR

1. Verify app behavior manually for the changed platform.
2. Run basic syntax checks for PHP changes:

```bash
cd web-player
for f in *.php; do php -l "$f"; done
```

3. For docker changes, validate compose:

```bash
cd web-player
docker compose config
```

## License

By contributing, you agree your contributions are licensed under the Apache License 2.0.
