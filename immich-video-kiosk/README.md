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

## 3) Run

```bash
docker compose up -d
```

This uses the stock `php:8.2-apache` image and mounts `index.php` and `video.php` into Apache.

## 4) Open slideshow

Browse to:

- http://localhost:8095

## How it works

- `index.php` calls `POST /api/search/metadata` with:
  - `{"type":"VIDEO","size":1,"random":true}`
- It retries up to 20 times until it finds a video with `duration >= MIN_DURATION`.
- The browser plays `/video.php?id=<assetId>` fullscreen.
- `video.php` proxies Immich playback from:
  - `GET /api/assets/{id}/video/playback`
- `video.php` sends `x-api-key` server-side, so the API key is never exposed to the browser.
- When playback ends, the page reloads and selects another random qualifying video.
