<?php
declare(strict_types=1);

function envFlag(string $name, bool $default = false): bool
{
    $raw = getenv($name);
    if ($raw === false) {
        return $default;
    }

    $value = strtolower(trim((string) $raw));
    return in_array($value, ['1', 'true', 'yes', 'on'], true);
}

function kioskLog(string $message, array $context = []): void
{
    $encoded = $context === [] ? '' : ' ' . json_encode($context);
    error_log('[immich-video-kiosk][index] ' . $message . $encoded);
}

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
        return ((int) $m[1] * 3600) + ((int) $m[2] * 60) + (float) $m[3];
    }

    return 0.0;
}

function buildApiUrl(string $baseUrl, string $path): string
{
    return rtrim($baseUrl, '/') . '/' . ltrim($path, '/');
}

/**
 * Call Immich metadata search API with the given body.
 */
function immichMetadataSearch(string $immichUrl, string $apiKey, array $body): array
{
    $endpoint = buildApiUrl($immichUrl, '/api/search/metadata');
    $payload = json_encode($body, JSON_THROW_ON_ERROR);

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
        CURLOPT_TIMEOUT => 30,
    ]);

    $raw = curl_exec($ch);
    if ($raw === false) {
        $error = curl_error($ch);
        curl_close($ch);
        return [
            'ok' => false,
            'error' => 'curl_error: ' . $error,
            'status' => 0,
            'items' => [],
        ];
    }

    $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);

    if ($status < 200 || $status >= 300) {
        return [
            'ok' => false,
            'error' => 'http_status: ' . $status,
            'status' => $status,
            'items' => [],
        ];
    }

    $json = json_decode($raw, true);
    if (!is_array($json)) {
        return [
            'ok' => false,
            'error' => 'invalid_json',
            'status' => $status,
            'items' => [],
        ];
    }

    $items = $json['assets']['items'] ?? [];
    if (!is_array($items)) {
        $items = [];
    }

    return [
        'ok' => true,
        'error' => '',
        'status' => $status,
        'items' => $items,
    ];
}

function normalizeVideoItem(array $item): ?array
{
    $id = $item['id'] ?? null;
    if (!is_string($id) || $id === '') {
        return null;
    }

    $durationRaw = $item['duration'] ?? 0;
    $duration = parseDurationToSeconds($durationRaw);

    $exif = $item['exifInfo'] ?? null;
    if (!is_array($exif)) {
        $exif = [];
    }

    $people = $item['people'] ?? null;
    if (!is_array($people)) {
        $people = [];
    }

    $city = '';
    if (isset($exif['city']) && is_string($exif['city'])) {
        $city = $exif['city'];
    }

    $country = '';
    if (isset($exif['country']) && is_string($exif['country'])) {
        $country = $exif['country'];
    }

    $lat = null;
    if (isset($exif['latitude']) && is_numeric($exif['latitude'])) {
        $lat = (float) $exif['latitude'];
    }

    $lon = null;
    if (isset($exif['longitude']) && is_numeric($exif['longitude'])) {
        $lon = (float) $exif['longitude'];
    }

    return [
        'asset_id' => $id,
        'duration' => $duration,
        'duration_raw' => is_scalar($durationRaw) ? (string) $durationRaw : gettype($durationRaw),
        'file_name' => isset($item['originalFileName']) && is_string($item['originalFileName']) ? $item['originalFileName'] : '',
        'original_path' => isset($item['originalPath']) && is_string($item['originalPath']) ? $item['originalPath'] : '',
        'city' => $city,
        'country' => $country,
        'latitude' => $lat,
        'longitude' => $lon,
        'faces_count' => count($people),
        'metadata_json' => json_encode($item),
    ];
}

function openSqlite(string $path): PDO
{
    $dir = dirname($path);
    if (!is_dir($dir)) {
        mkdir($dir, 0777, true);
    }

    $pdo = new PDO('sqlite:' . $path);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->exec('PRAGMA journal_mode = WAL');
    $pdo->exec('PRAGMA synchronous = NORMAL');
    return $pdo;
}

function initSchema(PDO $pdo): void
{
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS videos (
            asset_id TEXT PRIMARY KEY,
            duration REAL NOT NULL,
            duration_raw TEXT,
            file_name TEXT,
            original_path TEXT,
            city TEXT,
            country TEXT,
            latitude REAL,
            longitude REAL,
            faces_count INTEGER NOT NULL DEFAULT 0,
            metadata_json TEXT,
            updated_at TEXT NOT NULL
        )'
    );

    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_videos_duration ON videos(duration)');

    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS sync_state (
            key TEXT PRIMARY KEY,
            value TEXT
        )'
    );
}

function upsertVideo(PDO $pdo, array $video): void
{
    $stmt = $pdo->prepare(
        'INSERT INTO videos (
            asset_id, duration, duration_raw, file_name, original_path, city, country, latitude, longitude, faces_count, metadata_json, updated_at
        ) VALUES (
            :asset_id, :duration, :duration_raw, :file_name, :original_path, :city, :country, :latitude, :longitude, :faces_count, :metadata_json, :updated_at
        )
        ON CONFLICT(asset_id) DO UPDATE SET
            duration=excluded.duration,
            duration_raw=excluded.duration_raw,
            file_name=excluded.file_name,
            original_path=excluded.original_path,
            city=excluded.city,
            country=excluded.country,
            latitude=excluded.latitude,
            longitude=excluded.longitude,
            faces_count=excluded.faces_count,
            metadata_json=excluded.metadata_json,
            updated_at=excluded.updated_at'
    );

    $stmt->execute([
        ':asset_id' => $video['asset_id'],
        ':duration' => $video['duration'],
        ':duration_raw' => $video['duration_raw'],
        ':file_name' => $video['file_name'],
        ':original_path' => $video['original_path'],
        ':city' => $video['city'],
        ':country' => $video['country'],
        ':latitude' => $video['latitude'],
        ':longitude' => $video['longitude'],
        ':faces_count' => $video['faces_count'],
        ':metadata_json' => $video['metadata_json'],
        ':updated_at' => gmdate('c'),
    ]);
}

function setSyncState(PDO $pdo, string $key, string $value): void
{
    $stmt = $pdo->prepare(
        'INSERT INTO sync_state (key, value) VALUES (:key, :value)
         ON CONFLICT(key) DO UPDATE SET value=excluded.value'
    );
    $stmt->execute([':key' => $key, ':value' => $value]);
}

function getSyncState(PDO $pdo, string $key): ?string
{
    $stmt = $pdo->prepare('SELECT value FROM sync_state WHERE key = :key');
    $stmt->execute([':key' => $key]);
    $value = $stmt->fetchColumn();
    return $value === false ? null : (string) $value;
}

function countVideos(PDO $pdo): int
{
    $result = $pdo->query('SELECT COUNT(*) FROM videos')->fetchColumn();
    return $result === false ? 0 : (int) $result;
}

function countQualifyingVideos(PDO $pdo, float $minDuration): int
{
    $stmt = $pdo->prepare('SELECT COUNT(*) FROM videos WHERE duration >= :min_duration');
    $stmt->execute([':min_duration' => $minDuration]);
    $result = $stmt->fetchColumn();
    return $result === false ? 0 : (int) $result;
}

function selectRandomVideo(PDO $pdo, float $minDuration): ?array
{
    $stmt = $pdo->prepare(
        'SELECT asset_id, duration, duration_raw, file_name, original_path, city, country, latitude, longitude, faces_count
         FROM videos
         WHERE duration >= :min_duration
         ORDER BY RANDOM()
         LIMIT 1'
    );
    $stmt->execute([':min_duration' => $minDuration]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    return is_array($row) ? $row : null;
}

/**
 * Pull video metadata pages from Immich and upsert into SQLite.
 * This includes exif/location and people/faces when present in the response.
 */
function syncVideosFromImmich(
    PDO $pdo,
    string $immichUrl,
    string $apiKey,
    string $requestId,
    int $pageSize,
    int $maxPages
): array {
    $insertedOrUpdated = 0;
    $pagesFetched = 0;
    $errors = [];
    $seenPageHashes = [];

    for ($page = 1; $page <= $maxPages; $page++) {
        $result = immichMetadataSearch($immichUrl, $apiKey, [
            'type' => 'VIDEO',
            'size' => $pageSize,
            'page' => $page,
            'withExif' => true,
            'withPeople' => true,
        ]);

        if (($result['ok'] ?? false) !== true) {
            $errors[] = $result['error'] ?? 'unknown_error';
            kioskLog('Sync page failed', [
                'request_id' => $requestId,
                'page' => $page,
                'error' => $result['error'] ?? 'unknown_error',
            ]);
            break;
        }

        $items = $result['items'] ?? [];
        if (!is_array($items) || $items === []) {
            break;
        }

        $pagesFetched++;

        $ids = [];
        foreach ($items as $item) {
            if (is_array($item) && isset($item['id']) && is_string($item['id'])) {
                $ids[] = $item['id'];
            }
        }
        $pageHash = sha1(implode('|', $ids));
        if (isset($seenPageHashes[$pageHash])) {
            kioskLog('Sync stopped due to repeated page content', [
                'request_id' => $requestId,
                'page' => $page,
            ]);
            break;
        }
        $seenPageHashes[$pageHash] = true;

        foreach ($items as $item) {
            if (!is_array($item)) {
                continue;
            }
            $video = normalizeVideoItem($item);
            if ($video === null) {
                continue;
            }

            upsertVideo($pdo, $video);
            $insertedOrUpdated++;
        }
    }

    setSyncState($pdo, 'last_sync_at', gmdate('c'));

    return [
        'pages_fetched' => $pagesFetched,
        'rows_upserted' => $insertedOrUpdated,
        'errors' => $errors,
    ];
}

function searchRandomVideosLive(string $immichUrl, string $apiKey, int $batchSize): array
{
    $result = immichMetadataSearch($immichUrl, $apiKey, [
        'type' => 'VIDEO',
        'size' => $batchSize,
        'random' => true,
        'withExif' => true,
        'withPeople' => true,
    ]);

    if (($result['ok'] ?? false) !== true) {
        return [
            'ok' => false,
            'error' => $result['error'] ?? 'unknown_error',
            'items' => [],
        ];
    }

    $normalized = [];
    foreach (($result['items'] ?? []) as $item) {
        if (!is_array($item)) {
            continue;
        }
        $video = normalizeVideoItem($item);
        if ($video !== null) {
            $normalized[] = $video;
        }
    }

    return [
        'ok' => true,
        'error' => '',
        'items' => $normalized,
    ];
}

$immichUrl = getenv('IMMICH_URL') ?: '';
$apiKey = getenv('IMMICH_API_KEY') ?: '';
$minDuration = (float) (getenv('MIN_DURATION') ?: '10');
$batchSize = (int) (getenv('RANDOM_BATCH_SIZE') ?: '20');
$debug = envFlag('DEBUG', false);
$useSqlite = envFlag('USE_SQLITE_CACHE', true);
$sqlitePath = getenv('SQLITE_PATH') ?: '/var/www/html/data/videos.sqlite';
$syncPageSize = (int) (getenv('SYNC_PAGE_SIZE') ?: '200');
$syncMaxPages = (int) (getenv('SYNC_MAX_PAGES') ?: '200');
$syncOnStartup = envFlag('SYNC_ON_STARTUP', true);
$requestId = bin2hex(random_bytes(6));

ini_set('log_errors', '1');
error_reporting(E_ALL);
ini_set('display_errors', $debug ? '1' : '0');

if ($minDuration < 0) {
    $minDuration = 10;
}
if ($batchSize < 1) {
    $batchSize = 20;
}
if ($batchSize > 200) {
    $batchSize = 200;
}
if ($syncPageSize < 1) {
    $syncPageSize = 200;
}
if ($syncPageSize > 1000) {
    $syncPageSize = 1000;
}
if ($syncMaxPages < 1) {
    $syncMaxPages = 200;
}

kioskLog('Incoming slideshow request', [
    'request_id' => $requestId,
    'debug' => $debug,
    'min_duration' => $minDuration,
    'batch_size' => $batchSize,
    'use_sqlite' => $useSqlite,
    'sqlite_path' => $sqlitePath,
    'remote_addr' => $_SERVER['REMOTE_ADDR'] ?? '',
]);

if ($immichUrl === '' || $apiKey === '') {
    kioskLog('Missing required environment variables', ['request_id' => $requestId]);
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Missing IMMICH_URL or IMMICH_API_KEY environment variables.";
    exit;
}

$selected = null;
$attemptTrace = [];
$syncStats = null;
$dbStats = [];
$forcedSync = isset($_GET['sync']) && $_GET['sync'] === '1';

if ($useSqlite && extension_loaded('pdo_sqlite')) {
    try {
        $pdo = openSqlite($sqlitePath);
        initSchema($pdo);

        $totalBefore = countVideos($pdo);
        $qualifyingBefore = countQualifyingVideos($pdo, $minDuration);

        if ($forcedSync || ($syncOnStartup && ($totalBefore === 0 || $qualifyingBefore === 0))) {
            $syncStats = syncVideosFromImmich($pdo, $immichUrl, $apiKey, $requestId, $syncPageSize, $syncMaxPages);
        }

        $selected = selectRandomVideo($pdo, $minDuration);
        $dbStats = [
            'sqlite_enabled' => true,
            'db_total_videos' => countVideos($pdo),
            'db_qualifying_videos' => countQualifyingVideos($pdo, $minDuration),
            'last_sync_at' => getSyncState($pdo, 'last_sync_at'),
        ];

        if ($selected === null && !$forcedSync) {
            $syncStats = syncVideosFromImmich($pdo, $immichUrl, $apiKey, $requestId, $syncPageSize, $syncMaxPages);
            $selected = selectRandomVideo($pdo, $minDuration);
            $dbStats['db_total_videos'] = countVideos($pdo);
            $dbStats['db_qualifying_videos'] = countQualifyingVideos($pdo, $minDuration);
            $dbStats['last_sync_at'] = getSyncState($pdo, 'last_sync_at');
        }
    } catch (Throwable $e) {
        kioskLog('SQLite mode failed, falling back to live mode', [
            'request_id' => $requestId,
            'error' => $e->getMessage(),
        ]);
        $useSqlite = false;
        $attemptTrace[] = [
            'attempt' => 0,
            'status' => 'sqlite_error',
            'error' => $e->getMessage(),
        ];
    }
} elseif ($useSqlite) {
    $attemptTrace[] = [
        'attempt' => 0,
        'status' => 'sqlite_unavailable',
        'error' => 'pdo_sqlite_extension_not_loaded',
    ];
    $useSqlite = false;
}

if (!$useSqlite) {
    $maxAttempts = 20;
    $seenAssetIds = [];
    for ($i = 0; $i < $maxAttempts; $i++) {
        $attempt = $i + 1;
        $batch = searchRandomVideosLive($immichUrl, $apiKey, $batchSize);
        if (($batch['ok'] ?? false) !== true) {
            $attemptTrace[] = [
                'attempt' => $attempt,
                'status' => 'error',
                'error' => $batch['error'] ?? 'unknown_error',
            ];
            continue;
        }

        foreach ($batch['items'] as $candidate) {
            $candidateId = (string) ($candidate['asset_id'] ?? '');
            if ($candidateId === '' || isset($seenAssetIds[$candidateId])) {
                continue;
            }
            $seenAssetIds[$candidateId] = true;

            if (($candidate['duration'] ?? 0.0) >= $minDuration) {
                $selected = $candidate;
                $attemptTrace[] = [
                    'attempt' => $attempt,
                    'status' => 'selected',
                    'asset_id' => $candidate['asset_id'],
                    'file_name' => $candidate['file_name'],
                    'duration' => $candidate['duration'],
                    'duration_raw' => $candidate['duration_raw'],
                    'original_path' => $candidate['original_path'],
                ];
                break 2;
            }

            $attemptTrace[] = [
                'attempt' => $attempt,
                'status' => 'rejected_short',
                'asset_id' => $candidate['asset_id'],
                'file_name' => $candidate['file_name'],
                'duration' => $candidate['duration'],
                'duration_raw' => $candidate['duration_raw'],
                'original_path' => $candidate['original_path'],
            ];
        }
    }
}

if ($selected === null) {
    kioskLog('Failed to find qualifying video', [
        'request_id' => $requestId,
        'min_duration' => $minDuration,
        'use_sqlite' => $useSqlite,
        'sync_stats' => $syncStats,
        'db_stats' => $dbStats,
        'attempt_trace' => $attemptTrace,
    ]);

    http_response_code(503);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Could not find a qualifying video.\n";
    echo "request_id: {$requestId}\n";
    echo "min_duration: {$minDuration}\n";
    echo "use_sqlite: " . ($useSqlite ? 'true' : 'false') . "\n";
    if ($dbStats !== []) {
        echo "db_total_videos: " . ($dbStats['db_total_videos'] ?? 0) . "\n";
        echo "db_qualifying_videos: " . ($dbStats['db_qualifying_videos'] ?? 0) . "\n";
        echo "last_sync_at: " . ($dbStats['last_sync_at'] ?? '-') . "\n";
    }
    if (is_array($syncStats)) {
        echo "sync_pages_fetched: " . ($syncStats['pages_fetched'] ?? 0) . "\n";
        echo "sync_rows_upserted: " . ($syncStats['rows_upserted'] ?? 0) . "\n";
        $syncErrors = $syncStats['errors'] ?? [];
        echo "sync_errors: " . json_encode($syncErrors) . "\n";
    }
    echo "attempted metadata:\n";
    foreach ($attemptTrace as $row) {
        $line = sprintf(
            'attempt=%d status=%s asset_id=%s file_name=%s duration=%s raw=%s path=%s error=%s',
            (int) ($row['attempt'] ?? 0),
            (string) ($row['status'] ?? ''),
            (string) ($row['asset_id'] ?? '-'),
            (string) ($row['file_name'] ?? '-'),
            isset($row['duration']) ? (string) $row['duration'] : '-',
            (string) ($row['duration_raw'] ?? '-'),
            (string) ($row['original_path'] ?? '-'),
            (string) ($row['error'] ?? '-')
        );
        echo $line . "\n";
    }
    exit;
}

$assetId = rawurlencode((string) ($selected['asset_id'] ?? $selected['id'] ?? ''));
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

    .debug-box {
      position: fixed;
      left: 12px;
      top: 12px;
      max-width: 90vw;
      z-index: 9999;
      background: rgba(0, 0, 0, 0.75);
      color: #8ef58e;
      padding: 10px 12px;
      border: 1px solid #2f7f2f;
      font: 12px/1.4 monospace;
      white-space: pre-wrap;
    }
  </style>
</head>
<body>
  <video id="player" autoplay muted playsinline>
    <source src="<?= htmlspecialchars($videoSrc, ENT_QUOTES, 'UTF-8') ?>" type="video/mp4">
  </video>
  <?php if ($debug): ?>
  <div class="debug-box"><?= htmlspecialchars(
      "DEBUG MODE\n" .
      "request_id: {$requestId}\n" .
      "use_sqlite: " . ($useSqlite ? 'true' : 'false') . "\n" .
      "asset_id: " . (string) ($selected['asset_id'] ?? $selected['id'] ?? '') . "\n" .
      "duration: " . (string) ($selected['duration'] ?? '') . "s\n" .
      "min_duration: {$minDuration}s\n" .
      "db_total_videos: " . (string) ($dbStats['db_total_videos'] ?? '-') . "\n" .
      "db_qualifying_videos: " . (string) ($dbStats['db_qualifying_videos'] ?? '-') . "\n" .
      "last_sync_at: " . (string) ($dbStats['last_sync_at'] ?? '-') . "\n" .
      "sync_stats: " . json_encode($syncStats, JSON_UNESCAPED_SLASHES) . "\n" .
      "video_src: {$videoSrc}\n" .
      "attempt_trace: " . json_encode($attemptTrace, JSON_UNESCAPED_SLASHES),
      ENT_QUOTES,
      'UTF-8'
  ) ?></div>
  <?php endif; ?>

  <script>
    const player = document.getElementById('player');
    player.addEventListener('ended', () => {
      window.location.reload();
    });
    player.play().catch(() => {});
  </script>
</body>
</html>
