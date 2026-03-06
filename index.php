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

    $captureDate = '';
    $dateCandidates = [
        $exif['dateTimeOriginal'] ?? null,
        $exif['dateTime'] ?? null,
        $item['fileCreatedAt'] ?? null,
        $item['localDateTime'] ?? null,
        $item['createdAt'] ?? null,
    ];
    foreach ($dateCandidates as $candidate) {
        if (is_string($candidate) && trim($candidate) !== '') {
            $captureDate = trim($candidate);
            break;
        }
    }

    return [
        'asset_id' => $id,
        'duration' => $duration,
        'duration_raw' => is_scalar($durationRaw) ? (string) $durationRaw : gettype($durationRaw),
        'is_favorite' => !empty($item['isFavorite']) ? 1 : 0,
        'capture_date' => $captureDate,
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

function sqlitePathDiagnostics(string $path): array
{
    $dir = dirname($path);
    $dirExists = is_dir($dir);
    $fileExists = file_exists($path);

    return [
        'path' => $path,
        'dir' => $dir,
        'dir_exists' => $dirExists,
        'dir_writable' => $dirExists ? is_writable($dir) : false,
        'file_exists' => $fileExists,
        'file_writable' => $fileExists ? is_writable($path) : null,
        'uid' => function_exists('getmyuid') ? getmyuid() : null,
        'gid' => function_exists('getmygid') ? getmygid() : null,
    ];
}

/**
 * Open SQLite at exactly the configured path.
 * Creates parent directory and file if possible, otherwise throws with diagnostics.
 */
function openSqliteAtPath(string $path, string $requestId): array
{
    $dir = dirname($path);
    $diag = sqlitePathDiagnostics($path);

    if (!is_dir($dir)) {
        $created = @mkdir($dir, 0777, true);
        $diag['mkdir_attempted'] = true;
        $diag['mkdir_ok'] = $created;
        clearstatcache();
        $diag = array_merge($diag, sqlitePathDiagnostics($path));
    }

    if (!file_exists($path) && is_dir($dir) && is_writable($dir)) {
        $touchOk = @touch($path);
        $diag['touch_attempted'] = true;
        $diag['touch_ok'] = $touchOk;
        clearstatcache();
        $diag = array_merge($diag, sqlitePathDiagnostics($path));
    }

    try {
        $pdo = new PDO('sqlite:' . $path);
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $pdo->exec('PRAGMA journal_mode = WAL');
        $pdo->exec('PRAGMA synchronous = NORMAL');

        kioskLog('SQLite opened successfully', [
            'request_id' => $requestId,
            'path' => $path,
            'diag' => $diag,
        ]);

        return [
            'pdo' => $pdo,
            'path' => $path,
            'diagnostics' => [array_merge(['selected' => true], $diag)],
        ];
    } catch (Throwable $e) {
        $diag['open_error'] = $e->getMessage();
        kioskLog('SQLite open failed for configured path', [
            'request_id' => $requestId,
            'path' => $path,
            'diag' => $diag,
        ]);
        throw new RuntimeException(
            'Unable to open SQLite at configured SQLITE_PATH: ' . $path . ' | diagnostics=' . json_encode($diag)
        );
    }
}

function initSchema(PDO $pdo): void
{
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS videos (
            asset_id TEXT PRIMARY KEY,
            duration REAL NOT NULL,
            duration_raw TEXT,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            capture_date TEXT,
            file_name TEXT,
            original_path TEXT,
            city TEXT,
            country TEXT,
            latitude REAL,
            longitude REAL,
            faces_count INTEGER NOT NULL DEFAULT 0,
            watched_count INTEGER NOT NULL DEFAULT 0,
            metadata_json TEXT,
            updated_at TEXT NOT NULL
        )'
    );

    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_videos_duration ON videos(duration)');

    $columns = $pdo->query('PRAGMA table_info(videos)')->fetchAll(PDO::FETCH_ASSOC);
    $hasCaptureDate = false;
    foreach ($columns as $column) {
        if (($column['name'] ?? '') === 'capture_date') {
            $hasCaptureDate = true;
            break;
        }
    }
    if (!$hasCaptureDate) {
        $pdo->exec('ALTER TABLE videos ADD COLUMN capture_date TEXT');
    }

    $hasWatchedCount = false;
    foreach ($columns as $column) {
        if (($column['name'] ?? '') === 'watched_count') {
            $hasWatchedCount = true;
            break;
        }
    }
    if (!$hasWatchedCount) {
        $pdo->exec('ALTER TABLE videos ADD COLUMN watched_count INTEGER NOT NULL DEFAULT 0');
    }

    $hasIsFavorite = false;
    foreach ($columns as $column) {
        if (($column['name'] ?? '') === 'is_favorite') {
            $hasIsFavorite = true;
            break;
        }
    }
    if (!$hasIsFavorite) {
        $pdo->exec('ALTER TABLE videos ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0');
    }

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
            asset_id, duration, duration_raw, is_favorite, capture_date, file_name, original_path, city, country, latitude, longitude, faces_count, watched_count, metadata_json, updated_at
        ) VALUES (
            :asset_id, :duration, :duration_raw, :is_favorite, :capture_date, :file_name, :original_path, :city, :country, :latitude, :longitude, :faces_count, :watched_count, :metadata_json, :updated_at
        )
        ON CONFLICT(asset_id) DO UPDATE SET
            duration=excluded.duration,
            duration_raw=excluded.duration_raw,
            is_favorite=excluded.is_favorite,
            capture_date=excluded.capture_date,
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
        ':is_favorite' => (int) ($video['is_favorite'] ?? 0),
        ':capture_date' => $video['capture_date'],
        ':file_name' => $video['file_name'],
        ':original_path' => $video['original_path'],
        ':city' => $video['city'],
        ':country' => $video['country'],
        ':latitude' => $video['latitude'],
        ':longitude' => $video['longitude'],
        ':faces_count' => $video['faces_count'],
        ':watched_count' => 0,
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

function countQualifyingVideos(PDO $pdo, float $minDuration, bool $onlyFavorites = false): int
{
    if ($onlyFavorites) {
        $stmt = $pdo->prepare('SELECT COUNT(*) FROM videos WHERE duration >= :min_duration AND is_favorite = 1');
    } else {
        $stmt = $pdo->prepare('SELECT COUNT(*) FROM videos WHERE duration >= :min_duration');
    }
    $stmt->execute([':min_duration' => $minDuration]);
    $result = $stmt->fetchColumn();
    return $result === false ? 0 : (int) $result;
}

function countFavoriteVideos(PDO $pdo): int
{
    $result = $pdo->query('SELECT COUNT(*) FROM videos WHERE is_favorite = 1')->fetchColumn();
    return $result === false ? 0 : (int) $result;
}

function selectRandomVideo(PDO $pdo, float $minDuration, bool $onlyFavorites = false): ?array
{
    if ($onlyFavorites) {
        $stmt = $pdo->prepare(
            'SELECT asset_id, duration, duration_raw, is_favorite, capture_date, file_name, original_path, city, country, latitude, longitude, faces_count, watched_count
             FROM videos
             WHERE duration >= :min_duration AND is_favorite = 1
             ORDER BY RANDOM()
             LIMIT 1'
        );
    } else {
        $stmt = $pdo->prepare(
            'SELECT asset_id, duration, duration_raw, is_favorite, capture_date, file_name, original_path, city, country, latitude, longitude, faces_count, watched_count
             FROM videos
             WHERE duration >= :min_duration
             ORDER BY RANDOM()
             LIMIT 1'
        );
    }
    $stmt->execute([':min_duration' => $minDuration]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    return is_array($row) ? $row : null;
}

function jsString(string $value): string
{
    return json_encode($value, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
}

function startSyncStatusOutput(string $requestId, string $sqlitePath): void
{
    while (ob_get_level() > 0) {
        ob_end_clean();
    }
    header('Content-Type: text/html; charset=utf-8');
    echo '<!doctype html><html lang="en"><head><meta charset="utf-8">';
    echo '<meta name="viewport" content="width=device-width, initial-scale=1">';
    echo '<title>Immich Sync Status</title>';
    echo '<style>html,body{margin:0;background:#000;color:#d6ffd6;font:14px/1.45 monospace}';
    echo '.wrap{padding:16px}.title{font-size:16px;margin-bottom:8px}.log{white-space:pre-wrap;max-height:80vh;overflow:auto;border:1px solid #2f7f2f;padding:12px;background:#051005}';
    echo '.dim{color:#8ebf8e}</style></head><body><div class="wrap">';
    echo '<div class="title">Syncing Immich metadata into SQLite</div>';
    echo '<div class="dim">request_id: ' . htmlspecialchars($requestId, ENT_QUOTES, 'UTF-8') . '</div>';
    echo '<div class="dim">sqlite_path: ' . htmlspecialchars($sqlitePath, ENT_QUOTES, 'UTF-8') . '</div>';
    echo '<div id="totals" class="dim">running_total: 0</div>';
    echo '<div id="log" class="log"></div>';
    echo '<script>const logEl=document.getElementById("log");';
    echo 'const totalsEl=document.getElementById("totals");';
    echo 'function addLog(line){logEl.textContent+=line+"\\n";logEl.scrollTop=logEl.scrollHeight;}';
    echo 'function setRunningTotal(total){totalsEl.textContent="running_total: "+total;}';
    echo '</script>';
    @flush();
}

function syncStatusLog(string $message, ?int $runningTotal = null): void
{
    echo '<script>addLog(' . jsString($message) . ');</script>' . "\n";
    if ($runningTotal !== null) {
        echo '<script>setRunningTotal(' . $runningTotal . ');</script>' . "\n";
    }
    @flush();
}

function finishSyncStatusOutput(bool $success): void
{
    $msg = $success ? 'Sync complete. Reloading slideshow...' : 'Sync finished with errors. Reloading slideshow...';
    echo '<script>addLog(' . jsString($msg) . ');';
    echo 'setTimeout(()=>{const p=new URLSearchParams(window.location.search);const next=new URL(window.location.origin+window.location.pathname);if(p.get("favOnly")==="1"){next.searchParams.set("favOnly","1");}window.location.href=next.toString();},1200);';
    echo '</script></div></body></html>';
    @flush();
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
    int $maxPages,
    ?callable $progress = null
): array {
    $insertedOrUpdated = 0;
    $pagesFetched = 0;
    $errors = [];
    $seenPageHashes = [];

    for ($page = 1; $page <= $maxPages; $page++) {
        if ($progress !== null) {
            $progress("Fetching page {$page} (size={$pageSize})...", $insertedOrUpdated);
        }
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
            if ($progress !== null) {
                $progress("Page {$page} failed: " . ($result['error'] ?? 'unknown_error'), $insertedOrUpdated);
            }
            break;
        }

        $items = $result['items'] ?? [];
        if (!is_array($items) || $items === []) {
            if ($progress !== null) {
                $progress("No more items at page {$page}; stopping.", $insertedOrUpdated);
            }
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
            if ($progress !== null) {
                $progress("Page {$page} repeated previous content; stopping.", $insertedOrUpdated);
            }
            break;
        }
        $seenPageHashes[$pageHash] = true;

        $rowCountBefore = $insertedOrUpdated;
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

        if ($progress !== null) {
            $delta = $insertedOrUpdated - $rowCountBefore;
            $progress("Page {$page} complete: upserted {$delta} rows.", $insertedOrUpdated);
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
$showSyncStatus = envFlag('SHOW_SYNC_STATUS', true);
$defaultOnlyFavorites = envFlag('ONLY_FAVORITES', false);
$showQrCode = envFlag('SHOW_QR_CODE', true);
$onlyFavorites = $defaultOnlyFavorites;
if (isset($_GET['favOnly'])) {
    $onlyFavorites = ((string) $_GET['favOnly']) === '1';
}
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
    'only_favorites' => $onlyFavorites,
    'show_qr_code' => $showQrCode,
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
$sqliteDiagnostics = [];
$forcedSync = isset($_GET['sync']) && $_GET['sync'] === '1';

if ($useSqlite && extension_loaded('pdo_sqlite')) {
    try {
        $sqliteOpen = openSqliteAtPath($sqlitePath, $requestId);
        /** @var PDO $pdo */
        $pdo = $sqliteOpen['pdo'];
        $sqlitePath = (string) $sqliteOpen['path'];
        $sqliteDiagnostics = $sqliteOpen['diagnostics'] ?? [];
        initSchema($pdo);

        $totalBefore = countVideos($pdo);
        $qualifyingBefore = countQualifyingVideos($pdo, $minDuration, $onlyFavorites);
        $needsSync = $forcedSync || ($syncOnStartup && ($totalBefore === 0 || $qualifyingBefore === 0));

        if ($needsSync && $showSyncStatus) {
            startSyncStatusOutput($requestId, $sqlitePath);
            syncStatusLog("Initial DB state: total={$totalBefore}, qualifying={$qualifyingBefore}, min_duration={$minDuration}");
            $syncStats = syncVideosFromImmich(
                $pdo,
                $immichUrl,
                $apiKey,
                $requestId,
                $syncPageSize,
                $syncMaxPages,
                static function (string $line, int $runningTotal): void {
                    syncStatusLog($line, $runningTotal);
                }
            );
            $totalAfter = countVideos($pdo);
            $qualifyingAfter = countQualifyingVideos($pdo, $minDuration, $onlyFavorites);
            syncStatusLog("Sync summary: pages={$syncStats['pages_fetched']}, upserted={$syncStats['rows_upserted']}, errors=" . count($syncStats['errors'] ?? []));
            syncStatusLog("DB after sync: total={$totalAfter}, qualifying={$qualifyingAfter}");
            finishSyncStatusOutput(count($syncStats['errors'] ?? []) === 0);
            exit;
        }

        if ($needsSync) {
            $syncStats = syncVideosFromImmich($pdo, $immichUrl, $apiKey, $requestId, $syncPageSize, $syncMaxPages);
        }

        $selected = selectRandomVideo($pdo, $minDuration, $onlyFavorites);
        $dbStats = [
            'sqlite_enabled' => true,
            'sqlite_path' => $sqlitePath,
            'db_total_videos' => countVideos($pdo),
            'db_qualifying_videos' => countQualifyingVideos($pdo, $minDuration, $onlyFavorites),
            'db_favorite_videos' => countFavoriteVideos($pdo),
            'last_sync_at' => getSyncState($pdo, 'last_sync_at'),
        ];

        if ($selected === null && !$forcedSync) {
            $syncStats = syncVideosFromImmich($pdo, $immichUrl, $apiKey, $requestId, $syncPageSize, $syncMaxPages);
            $selected = selectRandomVideo($pdo, $minDuration, $onlyFavorites);
            $dbStats['db_total_videos'] = countVideos($pdo);
            $dbStats['db_qualifying_videos'] = countQualifyingVideos($pdo, $minDuration, $onlyFavorites);
            $dbStats['db_favorite_videos'] = countFavoriteVideos($pdo);
            $dbStats['last_sync_at'] = getSyncState($pdo, 'last_sync_at');
        }
    } catch (Throwable $e) {
        kioskLog('SQLite mode failed and cannot continue', [
            'request_id' => $requestId,
            'error' => $e->getMessage(),
            'sqlite_path' => $sqlitePath,
            'sqlite_diagnostics' => $sqliteDiagnostics,
        ]);
        http_response_code(500);
        header('Content-Type: text/plain; charset=utf-8');
        echo "SQLite initialization failed.\n";
        echo "Configured SQLITE_PATH: {$sqlitePath}\n";
        echo "Reason: " . $e->getMessage() . "\n";
        echo "Diagnostics: " . json_encode($sqliteDiagnostics) . "\n";
        exit;
    }
} elseif ($useSqlite) {
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    echo "SQLite is required but pdo_sqlite extension is not loaded.\n";
    echo "Configured SQLITE_PATH: {$sqlitePath}\n";
    exit;
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

            if ($onlyFavorites && ((int) ($candidate['is_favorite'] ?? 0) !== 1)) {
                continue;
            }

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
        'only_favorites' => $onlyFavorites,
        'use_sqlite' => $useSqlite,
        'sync_stats' => $syncStats,
        'db_stats' => $dbStats,
        'sqlite_diagnostics' => $sqliteDiagnostics,
        'attempt_trace' => $attemptTrace,
    ]);

    http_response_code(503);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Could not find a qualifying video.\n";
    echo "request_id: {$requestId}\n";
    echo "min_duration: {$minDuration}\n";
    echo "only_favorites: " . ($onlyFavorites ? 'true' : 'false') . "\n";
    echo "use_sqlite: " . ($useSqlite ? 'true' : 'false') . "\n";
    echo "sqlite_path: {$sqlitePath}\n";
    if ($sqliteDiagnostics !== []) {
        echo "sqlite_diagnostics: " . json_encode($sqliteDiagnostics) . "\n";
    }
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
$assetIdPlain = (string) ($selected['asset_id'] ?? $selected['id'] ?? '');
$immichAssetUrl = rtrim($immichUrl, '/') . '/photos/' . rawurlencode($assetIdPlain);
$qrImageUrl = 'https://api.qrserver.com/v1/create-qr-code/?size=160x160&data=' . rawurlencode($immichAssetUrl);
$captureDateValue = (string) ($selected['capture_date'] ?? '');
$captureYear = '';
if ($captureDateValue !== '') {
    $timestamp = strtotime($captureDateValue);
    if ($timestamp !== false) {
        $captureYear = gmdate('Y', $timestamp);
    } elseif (preg_match('/\b(\d{4})\b/', $captureDateValue, $m) === 1) {
        $captureYear = $m[1];
    }
}
$cityValue = trim((string) ($selected['city'] ?? ''));
$countryValue = trim((string) ($selected['country'] ?? ''));
$locationLabel = '';
if ($cityValue !== '' && $countryValue !== '') {
    $locationLabel = $cityValue . ', ' . $countryValue;
} elseif ($cityValue !== '') {
    $locationLabel = $cityValue;
} elseif ($countryValue !== '') {
    $locationLabel = $countryValue;
}
$metadataPayload = [
    'asset_id' => (string) ($selected['asset_id'] ?? $selected['id'] ?? ''),
    'file_name' => (string) ($selected['file_name'] ?? ''),
    'is_favorite' => (string) ((int) ($selected['is_favorite'] ?? 0)),
    'capture_date' => (string) ($selected['capture_date'] ?? ''),
    'duration' => (string) ($selected['duration'] ?? ''),
    'duration_raw' => (string) ($selected['duration_raw'] ?? ''),
    'city' => (string) ($selected['city'] ?? ''),
    'country' => (string) ($selected['country'] ?? ''),
    'latitude' => isset($selected['latitude']) ? (string) $selected['latitude'] : '',
    'longitude' => isset($selected['longitude']) ? (string) $selected['longitude'] : '',
    'faces_count' => (string) ($selected['faces_count'] ?? ''),
    'watched_count' => (string) ($selected['watched_count'] ?? ''),
    'immich_asset_url' => $immichAssetUrl,
    'qr_image_url' => $qrImageUrl,
    'original_path' => (string) ($selected['original_path'] ?? ''),
];
$statsPayload = [
    'use_sqlite' => $useSqlite ? 'true' : 'false',
    'only_favorites' => $onlyFavorites ? 'true' : 'false',
    'min_duration' => (string) $minDuration,
    'db_total_videos' => isset($dbStats['db_total_videos']) ? (string) $dbStats['db_total_videos'] : '',
    'db_qualifying_videos' => isset($dbStats['db_qualifying_videos']) ? (string) $dbStats['db_qualifying_videos'] : '',
    'db_favorite_videos' => isset($dbStats['db_favorite_videos']) ? (string) $dbStats['db_favorite_videos'] : '',
    'last_sync_at' => isset($dbStats['last_sync_at']) ? (string) $dbStats['last_sync_at'] : '',
];
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

    .mute-toggle {
      border: 1px solid #666;
      background: rgba(0, 0, 0, 0.65);
      color: #fff;
      font: 13px/1.2 sans-serif;
      padding: 8px 10px;
      cursor: pointer;
    }

    .action-bar {
      position: fixed;
      right: 12px;
      top: 12px;
      z-index: 9999;
      display: flex;
      gap: 8px;
      align-items: center;
    }

    .action-btn {
      border: 1px solid #666;
      background: rgba(0, 0, 0, 0.65);
      color: #fff;
      font: 13px/1.2 sans-serif;
      padding: 8px 10px;
      cursor: pointer;
    }

    .action-btn.favorite-active {
      border-color: #ff5d7b;
      color: #ff5d7b;
      font-weight: 700;
    }

    .metadata-panel {
      position: fixed;
      right: 12px;
      top: 52px;
      z-index: 9998;
      max-width: 45vw;
      max-height: 65vh;
      overflow: auto;
      background: rgba(0, 0, 0, 0.75);
      border: 1px solid #666;
      color: #fff;
      padding: 10px 12px;
      font: 12px/1.4 monospace;
      white-space: pre-wrap;
      display: none;
    }

    .metadata-panel.visible {
      display: block;
    }

    .stats-panel {
      position: fixed;
      right: 12px;
      top: 52px;
      z-index: 9998;
      max-width: 45vw;
      max-height: 65vh;
      overflow: auto;
      background: rgba(0, 0, 0, 0.75);
      border: 1px solid #666;
      color: #fff;
      padding: 10px 12px;
      font: 12px/1.4 monospace;
      white-space: pre-wrap;
      display: none;
    }

    .stats-panel.visible {
      display: block;
    }

    .video-caption {
      position: fixed;
      left: 14px;
      bottom: 10vh;
      z-index: 9997;
      color: #fff;
      font: 900 34px/1.12 sans-serif;
      letter-spacing: 0.3px;
      -webkit-text-stroke: 1.5px #000;
      text-shadow:
        -1px -1px 0 #000,
         1px -1px 0 #000,
        -1px  1px 0 #000,
         1px  1px 0 #000,
         0 2px 4px rgba(0, 0, 0, 0.8);
      pointer-events: none;
      user-select: none;
      white-space: pre-line;
    }

    .immich-link-panel {
      position: fixed;
      left: 14px;
      top: 12px;
      z-index: 9996;
      background: rgba(0, 0, 0, 0.65);
      border: 1px solid #666;
      color: #fff;
      padding: 8px;
      text-align: center;
      max-width: 180px;
    }

    .immich-link-panel img {
      width: 150px;
      height: 150px;
      display: block;
      margin: 0 auto 6px;
      background: #fff;
    }

    .immich-link-panel a {
      color: #fff;
      font: 12px/1.2 sans-serif;
      text-decoration: underline;
      word-break: break-word;
    }
  </style>
</head>
<body>
  <video id="player" autoplay muted playsinline controls>
    <source src="<?= htmlspecialchars($videoSrc, ENT_QUOTES, 'UTF-8') ?>" type="video/mp4">
  </video>
  <div class="action-bar">
    <button id="skipBtn" class="action-btn" type="button" title="Skip" aria-label="Skip">⏭</button>
    <button id="favoriteFilterToggle" class="action-btn" type="button" title="Favorites only" aria-label="Favorites only">⭐</button>
    <button id="statsToggle" class="action-btn" type="button" title="Stats" aria-label="Stats">📊</button>
    <button id="metaToggle" class="action-btn" type="button" title="Metadata" aria-label="Metadata">ⓘ</button>
    <button id="favoriteToggle" class="action-btn" type="button" title="Toggle favorite">♡</button>
    <button id="muteToggle" class="mute-toggle" type="button" title="Mute toggle" aria-label="Mute toggle">🔇</button>
  </div>
  <?php if ($showQrCode): ?>
  <div class="immich-link-panel">
    <img src="<?= htmlspecialchars($qrImageUrl, ENT_QUOTES, 'UTF-8') ?>" alt="QR code to open asset in Immich">
    <a href="<?= htmlspecialchars($immichAssetUrl, ENT_QUOTES, 'UTF-8') ?>" target="_blank" rel="noopener noreferrer">Open in Immich</a>
  </div>
  <?php endif; ?>
  <?php if ($captureYear !== '' || $locationLabel !== ''): ?>
  <div class="video-caption"><?= htmlspecialchars(
      trim($captureYear . ($locationLabel !== '' ? "\n" . $locationLabel : '')),
      ENT_QUOTES,
      'UTF-8'
  ) ?></div>
  <?php endif; ?>
  <div id="metadataPanel" class="metadata-panel"></div>
  <div id="statsPanel" class="stats-panel"></div>
  <?php if ($debug): ?>
  <div class="debug-box"><?= htmlspecialchars(
      "DEBUG MODE\n" .
      "request_id: {$requestId}\n" .
      "use_sqlite: " . ($useSqlite ? 'true' : 'false') . "\n" .
      "sqlite_path: {$sqlitePath}\n" .
      "asset_id: " . (string) ($selected['asset_id'] ?? $selected['id'] ?? '') . "\n" .
      "duration: " . (string) ($selected['duration'] ?? '') . "s\n" .
      "min_duration: {$minDuration}s\n" .
      "db_total_videos: " . (string) ($dbStats['db_total_videos'] ?? '-') . "\n" .
      "db_qualifying_videos: " . (string) ($dbStats['db_qualifying_videos'] ?? '-') . "\n" .
      "last_sync_at: " . (string) ($dbStats['last_sync_at'] ?? '-') . "\n" .
      "sqlite_diagnostics: " . json_encode($sqliteDiagnostics, JSON_UNESCAPED_SLASHES) . "\n" .
      "sync_stats: " . json_encode($syncStats, JSON_UNESCAPED_SLASHES) . "\n" .
      "video_src: {$videoSrc}\n" .
      "attempt_trace: " . json_encode($attemptTrace, JSON_UNESCAPED_SLASHES),
      ENT_QUOTES,
      'UTF-8'
  ) ?></div>
  <?php endif; ?>

  <script>
    const player = document.getElementById('player');
    const skipBtn = document.getElementById('skipBtn');
    const favoriteFilterToggle = document.getElementById('favoriteFilterToggle');
    const statsToggle = document.getElementById('statsToggle');
    const metaToggle = document.getElementById('metaToggle');
    const favoriteToggle = document.getElementById('favoriteToggle');
    const muteToggle = document.getElementById('muteToggle');
    const metadataPanel = document.getElementById('metadataPanel');
    const statsPanel = document.getElementById('statsPanel');
    const metadata = <?= json_encode($metadataPayload, JSON_UNESCAPED_SLASHES) ?>;
    const stats = <?= json_encode($statsPayload, JSON_UNESCAPED_SLASHES) ?>;
    const muteStorageKey = 'immichVideoKioskMuted';
    const metadataStorageKey = 'immichVideoKioskShowMetadata';
    let isFavorite = metadata.is_favorite === '1';
    let onlyFavoritesMode = stats.only_favorites === 'true';

    const readMutedPreference = () => {
      try {
        const raw = window.localStorage.getItem(muteStorageKey);
        if (raw === null) {
          return true;
        }
        return raw === '1';
      } catch (e) {
        return true;
      }
    };

    const saveMutedPreference = (muted) => {
      try {
        window.localStorage.setItem(muteStorageKey, muted ? '1' : '0');
      } catch (e) {}
    };

    const readMetadataPreference = () => {
      try {
        return window.localStorage.getItem(metadataStorageKey) === '1';
      } catch (e) {
        return false;
      }
    };

    const saveMetadataPreference = (visible) => {
      try {
        window.localStorage.setItem(metadataStorageKey, visible ? '1' : '0');
      } catch (e) {}
    };

    const updateMuteButton = () => {
      muteToggle.textContent = player.muted ? '🔇' : '🔊';
      muteToggle.title = player.muted ? 'Unmute' : 'Mute';
      muteToggle.setAttribute('aria-label', player.muted ? 'Unmute' : 'Mute');
    };

    const formatMetadata = (data) => {
      return [
        `asset_id: ${data.asset_id || '-'}`,
        `file_name: ${data.file_name || '-'}`,
        `is_favorite: ${data.is_favorite === '1' ? 'yes' : 'no'}`,
        `capture_date: ${data.capture_date || '-'}`,
        `duration: ${data.duration || '-'}s`,
        `duration_raw: ${data.duration_raw || '-'}`,
        `faces_count: ${data.faces_count || '0'}`,
        `watched_count: ${data.watched_count || '0'}`,
        `city: ${data.city || '-'}`,
        `country: ${data.country || '-'}`,
        `latitude: ${data.latitude || '-'}`,
        `longitude: ${data.longitude || '-'}`,
        `original_path: ${data.original_path || '-'}`
      ].join('\n');
    };

    const formatStats = (data) => {
      return [
        `use_sqlite: ${data.use_sqlite}`,
        `only_favorites: ${data.only_favorites}`,
        `min_duration: ${data.min_duration}s`,
        `total_videos: ${data.db_total_videos || '-'}`,
        `matching_duration: ${data.db_qualifying_videos || '-'}`,
        `favorites: ${data.db_favorite_videos || '-'}`,
        `last_sync_at: ${data.last_sync_at || '-'}`
      ].join('\n');
    };

    const updateFavoriteButton = () => {
      favoriteToggle.textContent = isFavorite ? '♥' : '♡';
      favoriteToggle.classList.toggle('favorite-active', isFavorite);
      favoriteToggle.title = isFavorite ? 'Unfavorite' : 'Favorite';
    };

    const updateFavoriteFilterButton = () => {
      favoriteFilterToggle.classList.toggle('favorite-active', onlyFavoritesMode);
      favoriteFilterToggle.title = onlyFavoritesMode ? 'Showing favorites only' : 'Show favorites only';
      favoriteFilterToggle.setAttribute('aria-label', favoriteFilterToggle.title);
    };

    muteToggle.addEventListener('click', () => {
      player.muted = !player.muted;
      saveMutedPreference(player.muted);
      updateMuteButton();
    });

    skipBtn.addEventListener('click', () => {
      const url = new URL(window.location.href);
      url.searchParams.set('skip', Date.now().toString());
      window.location.href = url.toString();
    });

    favoriteFilterToggle.addEventListener('click', () => {
      onlyFavoritesMode = !onlyFavoritesMode;
      const url = new URL(window.location.href);
      url.searchParams.set('favOnly', onlyFavoritesMode ? '1' : '0');
      window.location.href = url.toString();
    });

    metaToggle.addEventListener('click', () => {
      const next = !metadataPanel.classList.contains('visible');
      metadataPanel.classList.toggle('visible', next);
      statsPanel.classList.remove('visible');
      saveMetadataPreference(next);
    });

    statsToggle.addEventListener('click', () => {
      statsPanel.classList.toggle('visible');
      metadataPanel.classList.remove('visible');
      saveMetadataPreference(false);
    });

    favoriteToggle.addEventListener('click', async () => {
      const next = !isFavorite;
      favoriteToggle.disabled = true;
      try {
        const encodedId = encodeURIComponent(metadata.asset_id || '');
        const resp = await fetch(`/favorite.php?id=${encodedId}&favorite=${next ? '1' : '0'}`, {
          method: 'POST',
          keepalive: true
        });
        const body = await resp.json().catch(() => ({}));
        if (!resp.ok || body.ok !== true) {
          throw new Error(body.error || `HTTP ${resp.status}`);
        }
        isFavorite = next;
        metadata.is_favorite = isFavorite ? '1' : '0';
        metadataPanel.textContent = formatMetadata(metadata);
        updateFavoriteButton();
      } catch (err) {
        console.error('Favorite toggle failed', err);
      } finally {
        favoriteToggle.disabled = false;
      }
    });

    metadataPanel.textContent = formatMetadata(metadata);
    statsPanel.textContent = formatStats(stats);
    metadataPanel.classList.toggle('visible', readMetadataPreference());
    updateFavoriteButton();
    updateFavoriteFilterButton();

    player.addEventListener('volumechange', () => {
      saveMutedPreference(player.muted);
      updateMuteButton();
    });
    player.addEventListener('ended', () => {
      const encodedId = encodeURIComponent(metadata.asset_id || '');
      fetch(`/watch.php?id=${encodedId}`, { method: 'POST', keepalive: true }).catch(() => {});
      setTimeout(() => {
        window.location.reload();
      }, 120);
    });

    player.muted = readMutedPreference();
    updateMuteButton();
    player.play().catch(() => {
      // If autoplay is blocked while unmuted, retry muted for compatibility.
      if (!player.muted) {
        player.muted = true;
        saveMutedPreference(true);
        updateMuteButton();
        player.play().catch(() => {});
      }
    });
  </script>
</body>
</html>
