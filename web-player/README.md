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
- Set `MUTATION_TOKEN` and send it as `X-Mutation-Token` for `watch.php`, `favorite.php`, and `hide.php`.
- QR rendering is client-side using `qrcode.js` (no external QR image API).

## UI Actions

- Favorite/unfavorite current video.
- Hide Forever: archives the current video to Immich locked/archived state.
- Hiding is destructive for slideshow visibility; unhide from Immich website/app only.

## License

Apache License 2.0. See root `LICENSE`.
