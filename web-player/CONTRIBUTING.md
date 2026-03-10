# Contributing

## Development setup

1. Copy env file:

```bash
cp .env.example .env
```

2. Start locally:

```bash
docker compose up -d
```

3. Open:

- http://localhost:8095

## Coding guidelines

- Keep API responses JSON and include stable `error_code` for failures.
- Reuse helpers from `helpers.php` instead of duplicating endpoint logic.
- Keep frontend behavior in `index.php` and backend behavior in `api.php`/endpoint files.

## Validation before PR

1. Run syntax checks:

```bash
for f in *.php; do php -l "$f"; done
```

2. Validate compose config:

```bash
docker compose config
```

3. Smoke test endpoints:

- `GET /api.php?next=1`
- `POST /watch.php?id=<assetId>`
- `POST /favorite.php?id=<assetId>&favorite=1`
- `POST /hide.php?id=<assetId>`

## Pull requests

- Keep PRs focused and small.
- Include user-visible behavior changes in `CHANGELOG.md`.
- Update README when endpoint contracts or environment variables change.

## License

This component is licensed under the MIT License. See the repository root LICENSE.
