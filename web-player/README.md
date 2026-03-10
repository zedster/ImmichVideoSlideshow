# Immich Video Slideshow Web Player

PHP web slideshow player for videos stored in an Immich library.

## Requirements

- PHP 8+
- Immich API access

## Quick Start

1. Copy `.env.example` to `.env` and configure values.
2. Place files on a PHP-capable web server.
3. Open `index.php` in your browser.

## Docker (Optional)

```bash
docker compose up -d
```

## Security Notes

- Keep `DEBUG=false` in production.
- Mutation endpoints are POST-only.
- Set `MUTATION_TOKEN` and send it as `X-Mutation-Token` for `watch.php` and `favorite.php`.
- External QR generation is disabled by default; set `ENABLE_EXTERNAL_QR=true` only if you accept third-party URL disclosure.

## License

MIT License. See root `LICENSE`.