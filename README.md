# Immich Video Kiosk

Small Dockerized PHP app that continuously plays random Immich videos in a fullscreen browser slideshow.

## 1) Generate an Immich API key

1. Open Immich in your browser.
2. Go to your user account settings.
3. Open the API keys section.
4. Create a new key and copy it.

Note: Menu labels can vary slightly by Immich version, but API key creation is in your account/user settings.

## 2) Configure environment variables

Copy `.env.example` to `.env` and set your values:

```bash
cp .env.example .env
```

Required variables:

- `IMMICH_URL` - Base URL of your Immich server, e.g. `http://immich:2283`
- `IMMICH_API_KEY` - Your Immich API key
- `MIN_DURATION` - Minimum video length in seconds (default `10`)
- `RANDOM_BATCH_SIZE` - Fallback live mode batch size if SQLite cache is disabled/unavailable (default `20`)
- `USE_SQLITE_CACHE` - Enable local SQLite metadata cache and random DB selection (default `true`)
- `SQLITE_PATH` - SQLite database path inside container (default `/var/www/html/data/videos.sqlite`)
- `SYNC_ON_STARTUP` - Automatically sync metadata when DB is empty/no qualifying videos (default `true`)
- `SHOW_SYNC_STATUS` - Show live sync/import status page and auto-reload when done (default `true`)
- `ONLY_FAVORITES` - Default to favorites-only playback (`true` or `false`, default `false`)
- `SHOW_QR_CODE` - Show/hide QR + "Open in Immich" panel (default `true`)
- `SYNC_PAGE_SIZE` - Number of videos to request per sync page from Immich (default `200`)
- `SYNC_MAX_PAGES` - Maximum pages to scan per sync run (default `200`)
- `DEBUG` - Set to `true` to show debug overlay in `index.php` and enable PHP error display (default `false`)

## 3) Run

```bash
docker compose up -d
```

This uses the stock `php:8.2-apache` image and mounts `index.php`, `video.php`, `watch.php`, and `favorite.php` into Apache.
It also mounts `./data` for persistent SQLite cache storage.
SQLite must be writable at `SQLITE_PATH`; the app now errors clearly if it cannot create/open that exact path.

## 4) Open slideshow

Browse to:

- http://localhost:8095

## Logs and debug output

- Application logs are written with `error_log()` and go to container logs.
- View logs with:

```bash
docker compose logs -f
```

- Set `DEBUG=true` in `.env` for on-screen debug details (request ID, selected asset, duration, attempts).
- Keep `DEBUG=false` for normal kiosk usage.

## Force a metadata resync

- Open:
  - `http://localhost:8095/?sync=1`

This triggers a fresh metadata sync from Immich into SQLite (videos + duration + exif/location + faces count), then picks a random qualifying video from DB.
If `SHOW_SYNC_STATUS=true`, you will see a live progress log page during sync and it will auto-reload back to slideshow when complete.

## How it works

- `index.php` syncs video metadata from `POST /api/search/metadata` into local SQLite.
- Cached fields include:
  - `id`, `duration`, `originalFileName`, `originalPath`
  - `is_favorite` (heart toggle, synced to Immich favorite state)
  - `watched_count` (incremented when a video reaches `ended`)
  - location fields from `exifInfo` (when present)
  - faces count from `people` (when present)
- Playback selection is:
  - `SELECT ... WHERE duration >= MIN_DURATION ORDER BY RANDOM() LIMIT 1`
- If SQLite is disabled/unavailable, it falls back to live random batch API selection.
- The browser plays `/video.php?id=<assetId>` fullscreen.
- UI controls include `Skip`, `Stats`, `Metadata`, `Favorite` (heart), and `Mute`.
- `⭐` control toggles favorites-only playback mode (`favOnly=1` in URL).
- Favorite heart updates local DB and attempts to update Immich favorite state via API.
- A QR code and `Open in Immich` link are shown for the currently playing asset.
- `video.php` proxies Immich playback from:
  - `GET /api/assets/{id}/video/playback`
- `video.php` sends `x-api-key` server-side, so the API key is never exposed to the browser.
- When playback ends, the page reloads and selects another random qualifying video.
