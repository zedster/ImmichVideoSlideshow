<?php
declare(strict_types=1);

/**
 * Parse Immich duration value into seconds.
 * Immich may return numeric seconds or HH:MM:SS(.fraction) strings.
 */
function parseDurationToSeconds(mixed $duration): float
{
    if (is_int($duration) || is_float($duration)) {
        return (float) $duration;
    }

    if (!is_string($duration)) {
        return 0.0;
    }

    $duration = trim($duration);
    if ($duration === '') {
        return 0.0;
    }

    if (is_numeric($duration)) {
        return (float) $duration;
    }

    if (preg_match('/^(\d+):(\d+):(\d+(?:\.\d+)?)$/', $duration, $m) === 1) {
        $hours = (int) $m[1];
        $minutes = (int) $m[2];
        $seconds = (float) $m[3];
        return ($hours * 3600) + ($minutes * 60) + $seconds;
    }

    return 0.0;
}

function buildApiUrl(string $baseUrl, string $path): string
{
    return rtrim($baseUrl, '/') . '/' . ltrim($path, '/');
}

function searchRandomVideo(string $immichUrl, string $apiKey): ?array
{
    $endpoint = buildApiUrl($immichUrl, '/api/search/metadata');
    $payload = json_encode([
        'type' => 'VIDEO',
        'size' => 1,
        'random' => true,
    ], JSON_THROW_ON_ERROR);

    $ch = curl_init($endpoint);
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => $payload,
        CURLOPT_HTTPHEADER => [
            'Accept: application/json',
            'Content-Type: application/json',
            'x-api-key: ' . $apiKey,
        ],
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 20,
    ]);

    $raw = curl_exec($ch);
    if ($raw === false) {
        curl_close($ch);
        return null;
    }

    $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);

    if ($status < 200 || $status >= 300) {
        return null;
    }

    $json = json_decode($raw, true);
    if (!is_array($json)) {
        return null;
    }

    $item = $json['assets']['items'][0] ?? null;
    if (!is_array($item) || empty($item['id'])) {
        return null;
    }

    return [
        'id' => (string) $item['id'],
        'duration' => parseDurationToSeconds($item['duration'] ?? 0),
    ];
}

$immichUrl = getenv('IMMICH_URL') ?: '';
$apiKey = getenv('IMMICH_API_KEY') ?: '';
$minDuration = (float) (getenv('MIN_DURATION') ?: '10');
if ($minDuration < 0) {
    $minDuration = 10;
}

if ($immichUrl === '' || $apiKey === '') {
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Missing IMMICH_URL or IMMICH_API_KEY environment variables.";
    exit;
}

$selected = null;
$maxAttempts = 20;

// Retry random selection to ensure the video is at least MIN_DURATION seconds.
for ($i = 0; $i < $maxAttempts; $i++) {
    $candidate = searchRandomVideo($immichUrl, $apiKey);
    if ($candidate === null) {
        continue;
    }

    if ($candidate['duration'] >= $minDuration) {
        $selected = $candidate;
        break;
    }
}

if ($selected === null) {
    http_response_code(503);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Could not find a qualifying video after {$maxAttempts} attempts.";
    exit;
}

$assetId = rawurlencode($selected['id']);
$videoSrc = '/video.php?id=' . $assetId;
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Immich Video Kiosk</title>
  <style>
    html, body {
      margin: 0;
      width: 100%;
      height: 100%;
      background: #000;
      overflow: hidden;
    }

    video {
      width: 100vw;
      height: 100vh;
      object-fit: contain;
      background: #000;
      display: block;
    }
  </style>
</head>
<body>
  <video id="player" autoplay muted playsinline>
    <source src="<?= htmlspecialchars($videoSrc, ENT_QUOTES, 'UTF-8') ?>" type="video/mp4">
  </video>

  <script>
    const player = document.getElementById('player');
    player.addEventListener('ended', () => {
      window.location.reload();
    });

    // Fallback: if autoplay is blocked for any reason, attempt to start manually.
    player.play().catch(() => {});
  </script>
</body>
</html>
