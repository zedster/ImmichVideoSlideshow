<?php
declare(strict_types=1);

const DEFAULT_MIN_DURATION_SECONDS = 10.0;
const DEFAULT_RANDOM_BATCH_SIZE = 20;
const DEFAULT_SQLITE_PATH = '/var/www/html/data/videos.sqlite';
const DEFAULT_SYNC_PAGE_SIZE = 200;
const DEFAULT_SYNC_MAX_PAGES = 200;
const MAX_RANDOM_BATCH_SIZE = 200;
const MAX_SYNC_PAGE_SIZE = 1000;
const DEFAULT_LIVE_SELECTION_MAX_ATTEMPTS = 20;

const IMMICH_PATH_METADATA_SEARCH = '/api/search/metadata';
const IMMICH_PATH_ASSETS = '/api/assets';

const CURL_TIMEOUT_METADATA_SECONDS = 30;
const CURL_TIMEOUT_FAVORITE_SECONDS = 20;
const CURL_TIMEOUT_ARCHIVE_SECONDS = 20;

const ERROR_MISSING_IMMICH_ENV = 'E_MISSING_IMMICH_ENV';
const ERROR_SQLITE_INITIALIZATION_FAILED = 'E_SQLITE_INITIALIZATION_FAILED';
const ERROR_PDO_SQLITE_NOT_LOADED = 'E_PDO_SQLITE_NOT_LOADED';
const ERROR_NO_QUALIFYING_VIDEO = 'E_NO_QUALIFYING_VIDEO';
const ERROR_MISSING_ID = 'E_MISSING_ID';
const ERROR_INVALID_FAVORITE = 'E_INVALID_FAVORITE';
const ERROR_FAILED_UPDATE_IMMICH_FAVORITE = 'E_FAILED_UPDATE_IMMICH_FAVORITE';
const ERROR_FAILED_ARCHIVE_IMMICH_ASSET = 'E_FAILED_ARCHIVE_IMMICH_ASSET';
const ERROR_SQLITE_WRITE_FAILED = 'E_SQLITE_WRITE_FAILED';
const ERROR_METHOD_NOT_ALLOWED = 'E_METHOD_NOT_ALLOWED';
const ERROR_UNAUTHORIZED_MUTATION = 'E_UNAUTHORIZED_MUTATION';

const SCHEMA_MIGRATION_001_BASE_TABLES = 1;
const SCHEMA_MIGRATION_002_CAPTURE_DATE = 2;
const SCHEMA_MIGRATION_003_WATCHED_COUNT = 3;
const SCHEMA_MIGRATION_004_IS_FAVORITE = 4;
const SCHEMA_MIGRATION_005_CAMERA_COLUMNS = 5;
const SCHEMA_MIGRATION_006_VIDEO_BITRATE = 6;

function envFlag(string $name, bool $default = false): bool
{
    $raw = getenv($name);
    if ($raw === false) {
        return $default;
    }

    $value = strtolower(trim((string) $raw));
    return in_array($value, ['1', 'true', 'yes', 'on'], true);
}

function kioskLog(string $component, string $message, array $context = []): void
{
    $encoded = $context === [] ? '' : ' ' . json_encode($context);
    error_log('[immich-video-kiosk][' . $component . '] ' . $message . $encoded);
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

function jsonResponse(int $statusCode, array $payload): void
{
    http_response_code($statusCode);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($payload);
}

function jsonErrorResponse(int $statusCode, string $errorCode, string $message, array $extra = []): void
{
    jsonResponse(
        $statusCode,
        array_merge(
            [
                'ok' => false,
                'error_code' => $errorCode,
                'error' => $message,
            ],
            $extra
        )
    );
}

/**
 * Require POST for state-changing endpoints and optionally enforce a shared token.
 * Set MUTATION_TOKEN in environment to require X-Mutation-Token header.
 */
function enforceMutationRequestSecurity(): ?array
{
    $method = $_SERVER['REQUEST_METHOD'] ?? '';
    if ($method !== 'POST') {
        return [
            'status' => 405,
            'code' => ERROR_METHOD_NOT_ALLOWED,
            'message' => 'method_not_allowed',
        ];
    }

    $requiredToken = trim((string) (getenv('MUTATION_TOKEN') ?: ''));
    if ($requiredToken === '') {
        return null;
    }

    $providedToken = '';
    if (isset($_SERVER['HTTP_X_MUTATION_TOKEN']) && is_string($_SERVER['HTTP_X_MUTATION_TOKEN'])) {
        $providedToken = trim($_SERVER['HTTP_X_MUTATION_TOKEN']);
    } elseif (isset($_POST['mutation_token']) && is_string($_POST['mutation_token'])) {
        $providedToken = trim($_POST['mutation_token']);
    }

    if ($providedToken === '' || !hash_equals($requiredToken, $providedToken)) {
        return [
            'status' => 401,
            'code' => ERROR_UNAUTHORIZED_MUTATION,
            'message' => 'unauthorized_mutation',
        ];
    }

    return null;
}

/**
 * Call Immich metadata search API with the given body.
 */
function immichMetadataSearch(string $immichUrl, string $apiKey, array $body): array
{
    $endpoint = buildApiUrl($immichUrl, IMMICH_PATH_METADATA_SEARCH);
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
        CURLOPT_TIMEOUT => CURL_TIMEOUT_METADATA_SECONDS,
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

    $cameraMake = isset($exif['make']) && is_string($exif['make']) ? trim($exif['make']) : '';
    $cameraModel = isset($exif['model']) && is_string($exif['model']) ? trim($exif['model']) : '';
    $cameraLens = isset($exif['lensModel']) && is_string($exif['lensModel']) ? trim($exif['lensModel']) : '';

    $videoCodec = '';
    foreach (['videoCodec', 'codec', 'codecName'] as $k) {
        if (isset($exif[$k]) && is_string($exif[$k]) && trim($exif[$k]) !== '') {
            $videoCodec = trim($exif[$k]);
            break;
        }
    }

    $videoFps = null;
    foreach (['fps', 'videoFps', 'frameRate'] as $k) {
        if (isset($exif[$k]) && is_numeric($exif[$k])) {
            $videoFps = (float) $exif[$k];
            break;
        }
    }

    $videoWidth = null;
    foreach (['imageWidth', 'exifImageWidth', 'width'] as $k) {
        if (isset($exif[$k]) && is_numeric($exif[$k])) {
            $videoWidth = (int) $exif[$k];
            break;
        }
    }

    $videoHeight = null;
    foreach (['imageHeight', 'exifImageHeight', 'height'] as $k) {
        if (isset($exif[$k]) && is_numeric($exif[$k])) {
            $videoHeight = (int) $exif[$k];
            break;
        }
    }

    $videoBitrate = null;
    foreach (['bitrate', 'bitRate', 'avgBitrate', 'videoBitrate'] as $k) {
        if (isset($exif[$k]) && is_numeric($exif[$k])) {
            $videoBitrate = (int) $exif[$k];
            break;
        }
    }

    return [
        'asset_id' => $id,
        'duration' => $duration,
        'duration_raw' => is_scalar($durationRaw) ? (string) $durationRaw : gettype($durationRaw),
        'is_favorite' => !empty($item['isFavorite']) ? 1 : 0,
        'capture_date' => $captureDate,
        'camera_make' => $cameraMake,
        'camera_model' => $cameraModel,
        'camera_lens' => $cameraLens,
        'video_codec' => $videoCodec,
        'video_fps' => $videoFps,
        'video_width' => $videoWidth,
        'video_height' => $videoHeight,
        'video_bitrate' => $videoBitrate,
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

        kioskLog('api', 'SQLite opened successfully', [
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
        kioskLog('api', 'SQLite open failed for configured path', [
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
        'CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            applied_at TEXT NOT NULL
        )'
    );

    $recordMigration = static function (int $version, string $name) use ($pdo): void {
        $stmt = $pdo->prepare(
            'INSERT OR IGNORE INTO schema_migrations (version, name, applied_at)
             VALUES (:version, :name, :applied_at)'
        );
        $stmt->execute([
            ':version' => $version,
            ':name' => $name,
            ':applied_at' => gmdate('c'),
        ]);
    };

    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS videos (
            asset_id TEXT PRIMARY KEY,
            duration REAL NOT NULL,
            duration_raw TEXT,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            capture_date TEXT,
            camera_make TEXT,
            camera_model TEXT,
            camera_lens TEXT,
            video_codec TEXT,
            video_fps REAL,
            video_width INTEGER,
            video_height INTEGER,
            video_bitrate INTEGER,
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
    $recordMigration(SCHEMA_MIGRATION_002_CAPTURE_DATE, 'add_capture_date_column');

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
    $recordMigration(SCHEMA_MIGRATION_003_WATCHED_COUNT, 'add_watched_count_column');

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
    $recordMigration(SCHEMA_MIGRATION_004_IS_FAVORITE, 'add_is_favorite_column');

    $requiredColumns = [
        'camera_make' => 'TEXT',
        'camera_model' => 'TEXT',
        'camera_lens' => 'TEXT',
        'video_codec' => 'TEXT',
        'video_fps' => 'REAL',
        'video_width' => 'INTEGER',
        'video_height' => 'INTEGER',
        'video_bitrate' => 'INTEGER',
    ];
    $existing = [];
    foreach ($columns as $column) {
        if (isset($column['name']) && is_string($column['name'])) {
            $existing[$column['name']] = true;
        }
    }
    foreach ($requiredColumns as $name => $type) {
        if (!isset($existing[$name])) {
            $pdo->exec("ALTER TABLE videos ADD COLUMN {$name} {$type}");
        }
    }
    $recordMigration(SCHEMA_MIGRATION_005_CAMERA_COLUMNS, 'add_camera_codec_resolution_columns');
    $recordMigration(SCHEMA_MIGRATION_006_VIDEO_BITRATE, 'add_video_bitrate_column');

    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS sync_state (
            key TEXT PRIMARY KEY,
            value TEXT
        )'
    );
    $recordMigration(SCHEMA_MIGRATION_001_BASE_TABLES, 'create_videos_and_sync_state_tables');
}

function upsertVideo(PDO $pdo, array $video): void
{
    $stmt = $pdo->prepare(
        'INSERT INTO videos (
            asset_id, duration, duration_raw, is_favorite, capture_date, camera_make, camera_model, camera_lens, video_codec, video_fps, video_width, video_height, video_bitrate, file_name, original_path, city, country, latitude, longitude, faces_count, watched_count, metadata_json, updated_at
        ) VALUES (
            :asset_id, :duration, :duration_raw, :is_favorite, :capture_date, :camera_make, :camera_model, :camera_lens, :video_codec, :video_fps, :video_width, :video_height, :video_bitrate, :file_name, :original_path, :city, :country, :latitude, :longitude, :faces_count, :watched_count, :metadata_json, :updated_at
        )
        ON CONFLICT(asset_id) DO UPDATE SET
            duration=excluded.duration,
            duration_raw=excluded.duration_raw,
            is_favorite=excluded.is_favorite,
            capture_date=excluded.capture_date,
            camera_make=excluded.camera_make,
            camera_model=excluded.camera_model,
            camera_lens=excluded.camera_lens,
            video_codec=excluded.video_codec,
            video_fps=excluded.video_fps,
            video_width=excluded.video_width,
            video_height=excluded.video_height,
            video_bitrate=excluded.video_bitrate,
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
        ':camera_make' => $video['camera_make'],
        ':camera_model' => $video['camera_model'],
        ':camera_lens' => $video['camera_lens'],
        ':video_codec' => $video['video_codec'],
        ':video_fps' => $video['video_fps'],
        ':video_width' => $video['video_width'],
        ':video_height' => $video['video_height'],
        ':video_bitrate' => $video['video_bitrate'],
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

function countTotalWatchedVideos(PDO $pdo): int
{
    $result = $pdo->query('SELECT COALESCE(SUM(watched_count), 0) FROM videos')->fetchColumn();
    return $result === false ? 0 : (int) $result;
}

function topCameras(PDO $pdo, int $limit = 5): array
{
    $stmt = $pdo->prepare(
        'SELECT
            CASE
              WHEN TRIM(COALESCE(camera_make, \'\') || \' \' || COALESCE(camera_model, \'\')) = \'\' THEN \'Unknown\'
              ELSE TRIM(COALESCE(camera_make, \'\') || \' \' || COALESCE(camera_model, \'\'))
            END AS camera_name,
            COUNT(*) AS cnt
         FROM videos
         GROUP BY camera_name
         ORDER BY cnt DESC, camera_name ASC
         LIMIT :limit'
    );
    $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
    $stmt->execute();
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    return is_array($rows) ? $rows : [];
}

function topCodecs(PDO $pdo, int $limit = 5): array
{
    $stmt = $pdo->prepare(
        'SELECT
            CASE
              WHEN TRIM(COALESCE(video_codec, \'\')) = \'\' THEN \'Unknown\'
              ELSE TRIM(video_codec)
            END AS codec_name,
            COUNT(*) AS cnt
         FROM videos
         GROUP BY codec_name
         ORDER BY cnt DESC, codec_name ASC
         LIMIT :limit'
    );
    $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
    $stmt->execute();
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    return is_array($rows) ? $rows : [];
}

function selectRandomVideo(PDO $pdo, float $minDuration, bool $onlyFavorites = false): ?array
{
    if ($onlyFavorites) {
        $stmt = $pdo->prepare(
            'SELECT asset_id, duration, duration_raw, is_favorite, capture_date, camera_make, camera_model, camera_lens, video_codec, video_fps, video_width, video_height, video_bitrate, file_name, original_path, city, country, latitude, longitude, faces_count, watched_count
             FROM videos
             WHERE duration >= :min_duration AND is_favorite = 1
             ORDER BY RANDOM()
             LIMIT 1'
        );
    } else {
        $stmt = $pdo->prepare(
            'SELECT asset_id, duration, duration_raw, is_favorite, capture_date, camera_make, camera_model, camera_lens, video_codec, video_fps, video_width, video_height, video_bitrate, file_name, original_path, city, country, latitude, longitude, faces_count, watched_count
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
            kioskLog('api', 'Sync page failed', [
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
            kioskLog('api', 'Sync stopped due to repeated page content', [
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

function openSqliteStrict(string $path): PDO
{
    $diag = sqlitePathDiagnostics($path);
    if (!($diag['dir_exists'] ?? false) || !($diag['dir_writable'] ?? false)) {
        throw new RuntimeException('SQLITE_PATH directory is not writable: ' . json_encode($diag));
    }

    if (!file_exists($path)) {
        throw new RuntimeException('SQLite database file does not exist at configured SQLITE_PATH: ' . $path);
    }

    $pdo = new PDO('sqlite:' . $path);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    return $pdo;
}

function syncFavoriteToImmich(string $immichUrl, string $apiKey, string $assetId, bool $favorite): array
{
    $endpoint = buildApiUrl($immichUrl, IMMICH_PATH_ASSETS);
    $payload = json_encode([
        'ids' => [$assetId],
        'isFavorite' => $favorite,
    ], JSON_THROW_ON_ERROR);

    $methods = ['PUT', 'PATCH', 'POST'];
    $errors = [];
    foreach ($methods as $method) {
        $ch = curl_init($endpoint);
        curl_setopt_array($ch, [
            CURLOPT_CUSTOMREQUEST => $method,
            CURLOPT_POSTFIELDS => $payload,
            CURLOPT_HTTPHEADER => [
                'Accept: application/json',
                'Content-Type: application/json',
                'x-api-key: ' . $apiKey,
            ],
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => CURL_TIMEOUT_FAVORITE_SECONDS,
        ]);

        $raw = curl_exec($ch);
        if ($raw === false) {
            $errors[] = $method . ':curl_error:' . curl_error($ch);
            curl_close($ch);
            continue;
        }

        $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        curl_close($ch);
        if ($status >= 200 && $status < 300) {
            return ['ok' => true, 'status' => $status, 'method' => $method];
        }

        $errors[] = $method . ':http_status:' . $status;
    }

    return ['ok' => false, 'error' => implode('; ', $errors)];
}

function topLocations(PDO $pdo, int $limit = 5): array
{
    $stmt = $pdo->prepare(
        'SELECT
            CASE
              WHEN TRIM(COALESCE(city, \'\')) = \'\' AND TRIM(COALESCE(country, \'\')) = \'\' THEN \'Unknown\'
              WHEN TRIM(COALESCE(city, \'\')) = \'\' THEN TRIM(country)
              WHEN TRIM(COALESCE(country, \'\')) = \'\' THEN TRIM(city)
              ELSE TRIM(city) || \', \' || TRIM(country)
            END AS location_name,
            COUNT(*) AS cnt
         FROM videos
         GROUP BY location_name
         ORDER BY cnt DESC, location_name ASC
         LIMIT :limit'
    );
    $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
    $stmt->execute();
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    return is_array($rows) ? $rows : [];
}

function topResolutions(PDO $pdo, int $limit = 5): array
{
    $stmt = $pdo->prepare(
        'SELECT
            CASE
              WHEN COALESCE(video_width, 0) > 0 AND COALESCE(video_height, 0) > 0
                THEN CAST(video_width AS TEXT) || \'x\' || CAST(video_height AS TEXT)
              ELSE \'Unknown\'
            END AS resolution_name,
            COUNT(*) AS cnt
         FROM videos
         GROUP BY resolution_name
         ORDER BY cnt DESC, resolution_name ASC
         LIMIT :limit'
    );
    $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
    $stmt->execute();
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    return is_array($rows) ? $rows : [];
}

function topBitrates(PDO $pdo, int $limit = 5): array
{
    $stmt = $pdo->prepare(
        'SELECT
            CASE
              WHEN COALESCE(video_bitrate, 0) > 0
                THEN printf(\'%.2f Mbps\', video_bitrate / 1000000.0)
              ELSE \'Unknown\'
            END AS bitrate_name,
            COUNT(*) AS cnt
         FROM videos
         GROUP BY bitrate_name
         ORDER BY cnt DESC, bitrate_name ASC
         LIMIT :limit'
    );
    $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
    $stmt->execute();
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    return is_array($rows) ? $rows : [];
}

function archiveAssetToImmich(string $immichUrl, string $apiKey, string $assetId, bool $isArchived = true): array
{
    // Use explicit update verbs for archive updates to avoid no-op POST responses.
    $methods = ['PATCH', 'PUT'];
    $errors = [];

    $singleEndpoint = buildApiUrl($immichUrl, IMMICH_PATH_ASSETS . '/' . rawurlencode($assetId));
    $singlePayloads = [
        ['isArchived' => $isArchived],
        ['isArchived' => $isArchived, 'id' => $assetId],
    ];

    foreach ($singlePayloads as $payloadObj) {
        $payload = json_encode($payloadObj, JSON_THROW_ON_ERROR);
        foreach ($methods as $method) {
            $ch = curl_init($singleEndpoint);
            curl_setopt_array($ch, [
                CURLOPT_CUSTOMREQUEST => $method,
                CURLOPT_POSTFIELDS => $payload,
                CURLOPT_HTTPHEADER => [
                    'Accept: application/json',
                    'Content-Type: application/json',
                    'x-api-key: ' . $apiKey,
                ],
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT => CURL_TIMEOUT_ARCHIVE_SECONDS,
            ]);

            $raw = curl_exec($ch);
            if ($raw === false) {
                $errors[] = 'single:' . $method . ':curl_error:' . curl_error($ch);
                curl_close($ch);
                continue;
            }

            $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
            curl_close($ch);
            if ($status >= 200 && $status < 300) {
                return ['ok' => true, 'status' => $status, 'method' => $method, 'route' => 'single'];
            }

            $errors[] = 'single:' . $method . ':http_status:' . $status;
        }
    }

    $batchEndpoint = buildApiUrl($immichUrl, IMMICH_PATH_ASSETS);
    $batchPayloads = [
        ['ids' => [$assetId], 'isArchived' => $isArchived],
        ['assetIds' => [$assetId], 'isArchived' => $isArchived],
    ];

    foreach ($batchPayloads as $payloadObj) {
        $payload = json_encode($payloadObj, JSON_THROW_ON_ERROR);
        foreach ($methods as $method) {
            $ch = curl_init($batchEndpoint);
            curl_setopt_array($ch, [
                CURLOPT_CUSTOMREQUEST => $method,
                CURLOPT_POSTFIELDS => $payload,
                CURLOPT_HTTPHEADER => [
                    'Accept: application/json',
                    'Content-Type: application/json',
                    'x-api-key: ' . $apiKey,
                ],
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT => CURL_TIMEOUT_ARCHIVE_SECONDS,
            ]);

            $raw = curl_exec($ch);
            if ($raw === false) {
                $errors[] = 'batch:' . $method . ':curl_error:' . curl_error($ch);
                curl_close($ch);
                continue;
            }

            $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
            curl_close($ch);
            if ($status >= 200 && $status < 300) {
                return ['ok' => true, 'status' => $status, 'method' => $method, 'route' => 'batch'];
            }

            $errors[] = 'batch:' . $method . ':http_status:' . $status;
        }
    }

    return ['ok' => false, 'error' => implode('; ', $errors)];
}

function formatCaptureMonthYear(string $captureDateValue): string
{
    if ($captureDateValue === '') {
        return '';
    }

    $timestamp = strtotime($captureDateValue);
    if ($timestamp !== false) {
        return gmdate('M Y', $timestamp);
    }

    if (preg_match('/\b(\d{4})-(\d{2})\b/', $captureDateValue, $m) === 1) {
        $month = (int) $m[2];
        if ($month >= 1 && $month <= 12) {
            $monthName = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][$month - 1];
            return $monthName . ' ' . $m[1];
        }
    }

    if (preg_match('/\b(\d{4})\b/', $captureDateValue, $m) === 1) {
        return $m[1];
    }

    return '';
}
