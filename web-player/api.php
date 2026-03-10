<?php
declare(strict_types=1);

require_once __DIR__ . '/helpers.php';

$immichUrl = getenv('IMMICH_URL') ?: '';
$apiKey = getenv('IMMICH_API_KEY') ?: '';
$minDuration = (float) (getenv('MIN_DURATION') ?: (string) DEFAULT_MIN_DURATION_SECONDS);
$batchSize = (int) (getenv('RANDOM_BATCH_SIZE') ?: (string) DEFAULT_RANDOM_BATCH_SIZE);
$debug = envFlag('DEBUG', false);
$useSqlite = envFlag('USE_SQLITE_CACHE', true);
$sqlitePath = getenv('SQLITE_PATH') ?: DEFAULT_SQLITE_PATH;
$syncPageSize = (int) (getenv('SYNC_PAGE_SIZE') ?: (string) DEFAULT_SYNC_PAGE_SIZE);
$syncMaxPages = (int) (getenv('SYNC_MAX_PAGES') ?: (string) DEFAULT_SYNC_MAX_PAGES);
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
    $minDuration = DEFAULT_MIN_DURATION_SECONDS;
}
if ($batchSize < 1) {
    $batchSize = DEFAULT_RANDOM_BATCH_SIZE;
}
if ($batchSize > MAX_RANDOM_BATCH_SIZE) {
    $batchSize = MAX_RANDOM_BATCH_SIZE;
}
if ($syncPageSize < 1) {
    $syncPageSize = DEFAULT_SYNC_PAGE_SIZE;
}
if ($syncPageSize > MAX_SYNC_PAGE_SIZE) {
    $syncPageSize = MAX_SYNC_PAGE_SIZE;
}
if ($syncMaxPages < 1) {
    $syncMaxPages = DEFAULT_SYNC_MAX_PAGES;
}

kioskLog('api', 'Incoming slideshow request', [
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
    kioskLog('api', 'Missing required environment variables', ['request_id' => $requestId]);
    jsonErrorResponse(500, ERROR_MISSING_IMMICH_ENV, 'missing_immich_env', [
        'request_id' => $requestId,
    ]);
    exit;
}

$selected = null;
$attemptTrace = [];
$syncStats = null;
$dbStats = [];
$sqliteDiagnostics = [];
$forcedSync = isset($_GET['sync']) && $_GET['sync'] === '1';
$asJsonNext = isset($_GET['next']) && $_GET['next'] === '1';

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

        if ($needsSync && $showSyncStatus && !$asJsonNext) {
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
            'db_total_watched' => countTotalWatchedVideos($pdo),
            'db_top_cameras' => topCameras($pdo, 5),
            'db_top_codecs' => topCodecs($pdo, 5),
            'last_sync_at' => getSyncState($pdo, 'last_sync_at'),
        ];

        if ($selected === null && !$forcedSync) {
            $syncStats = syncVideosFromImmich($pdo, $immichUrl, $apiKey, $requestId, $syncPageSize, $syncMaxPages);
            $selected = selectRandomVideo($pdo, $minDuration, $onlyFavorites);
            $dbStats['db_total_videos'] = countVideos($pdo);
            $dbStats['db_qualifying_videos'] = countQualifyingVideos($pdo, $minDuration, $onlyFavorites);
            $dbStats['db_favorite_videos'] = countFavoriteVideos($pdo);
            $dbStats['db_total_watched'] = countTotalWatchedVideos($pdo);
            $dbStats['db_top_cameras'] = topCameras($pdo, 5);
            $dbStats['db_top_codecs'] = topCodecs($pdo, 5);
            $dbStats['last_sync_at'] = getSyncState($pdo, 'last_sync_at');
        }
    } catch (Throwable $e) {
        kioskLog('api', 'SQLite mode failed and cannot continue', [
            'request_id' => $requestId,
            'error' => $e->getMessage(),
            'sqlite_path' => $sqlitePath,
            'sqlite_diagnostics' => $sqliteDiagnostics,
        ]);
        jsonErrorResponse(500, ERROR_SQLITE_INITIALIZATION_FAILED, 'sqlite_initialization_failed', [
            'message' => $e->getMessage(),
            'sqlite_path' => $sqlitePath,
            'sqlite_diagnostics' => $sqliteDiagnostics,
            'request_id' => $requestId,
        ]);
        exit;
    }
} elseif ($useSqlite) {
    jsonErrorResponse(500, ERROR_PDO_SQLITE_NOT_LOADED, 'pdo_sqlite_not_loaded', [
        'sqlite_path' => $sqlitePath,
        'request_id' => $requestId,
    ]);
    exit;
}

if (!$useSqlite) {
    $maxAttempts = DEFAULT_LIVE_SELECTION_MAX_ATTEMPTS;
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
    kioskLog('api', 'Failed to find qualifying video', [
        'request_id' => $requestId,
        'min_duration' => $minDuration,
        'only_favorites' => $onlyFavorites,
        'use_sqlite' => $useSqlite,
        'sync_stats' => $syncStats,
        'db_stats' => $dbStats,
        'sqlite_diagnostics' => $sqliteDiagnostics,
        'attempt_trace' => $attemptTrace,
    ]);

    jsonErrorResponse(503, ERROR_NO_QUALIFYING_VIDEO, 'Could not find a qualifying video', [
        'request_id' => $requestId,
        'min_duration' => $minDuration,
        'only_favorites' => $onlyFavorites,
        'use_sqlite' => $useSqlite,
        'sqlite_path' => $sqlitePath,
        'sqlite_diagnostics' => $sqliteDiagnostics,
        'db_stats' => $dbStats,
        'sync_stats' => $syncStats,
        'attempt_trace' => $attemptTrace,
    ]);
    exit;
}

$assetId = rawurlencode((string) ($selected['asset_id'] ?? $selected['id'] ?? ''));
$videoSrc = '/video.php?id=' . $assetId;
$assetIdPlain = (string) ($selected['asset_id'] ?? $selected['id'] ?? '');
$immichAssetUrl = rtrim($immichUrl, '/') . '/photos/' . rawurlencode($assetIdPlain);
$captureDateValue = (string) ($selected['capture_date'] ?? '');
$captureMonthYear = formatCaptureMonthYear($captureDateValue);
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
$captionText = trim($captureMonthYear . ($locationLabel !== '' ? "\n" . $locationLabel : ''));
$metadataPayload = [
    'asset_id' => (string) ($selected['asset_id'] ?? $selected['id'] ?? ''),
    'file_name' => (string) ($selected['file_name'] ?? ''),
    'is_favorite' => (string) ((int) ($selected['is_favorite'] ?? 0)),
    'capture_date' => (string) ($selected['capture_date'] ?? ''),
    'camera_make' => (string) ($selected['camera_make'] ?? ''),
    'camera_model' => (string) ($selected['camera_model'] ?? ''),
    'camera_lens' => (string) ($selected['camera_lens'] ?? ''),
    'video_codec' => (string) ($selected['video_codec'] ?? ''),
    'video_fps' => isset($selected['video_fps']) ? (string) $selected['video_fps'] : '',
    'video_width' => isset($selected['video_width']) ? (string) $selected['video_width'] : '',
    'video_height' => isset($selected['video_height']) ? (string) $selected['video_height'] : '',
    'duration' => (string) ($selected['duration'] ?? ''),
    'duration_raw' => (string) ($selected['duration_raw'] ?? ''),
    'city' => (string) ($selected['city'] ?? ''),
    'country' => (string) ($selected['country'] ?? ''),
    'latitude' => isset($selected['latitude']) ? (string) $selected['latitude'] : '',
    'longitude' => isset($selected['longitude']) ? (string) $selected['longitude'] : '',
    'faces_count' => (string) ($selected['faces_count'] ?? ''),
    'watched_count' => (string) ($selected['watched_count'] ?? ''),
    'immich_asset_url' => $immichAssetUrl,
    'show_qr_code' => $showQrCode ? '1' : '0',
    'original_path' => (string) ($selected['original_path'] ?? ''),
];
$statsPayload = [
    'use_sqlite' => $useSqlite ? 'true' : 'false',
    'only_favorites' => $onlyFavorites ? 'true' : 'false',
    'min_duration' => (string) $minDuration,
    'db_total_videos' => isset($dbStats['db_total_videos']) ? (string) $dbStats['db_total_videos'] : '',
    'db_qualifying_videos' => isset($dbStats['db_qualifying_videos']) ? (string) $dbStats['db_qualifying_videos'] : '',
    'db_favorite_videos' => isset($dbStats['db_favorite_videos']) ? (string) $dbStats['db_favorite_videos'] : '',
    'db_total_watched' => isset($dbStats['db_total_watched']) ? (string) $dbStats['db_total_watched'] : '',
    'db_top_cameras' => isset($dbStats['db_top_cameras']) ? json_encode($dbStats['db_top_cameras']) : '[]',
    'db_top_codecs' => isset($dbStats['db_top_codecs']) ? json_encode($dbStats['db_top_codecs']) : '[]',
    'last_sync_at' => isset($dbStats['last_sync_at']) ? (string) $dbStats['last_sync_at'] : '',
];

$payload = [
    'ok' => true,
    'asset_id' => (string) ($selected['asset_id'] ?? $selected['id'] ?? ''),
    'video_src' => $videoSrc,
    'metadata' => $metadataPayload,
    'stats' => $statsPayload,
    'caption_text' => $captionText,
];
if ($debug) {
    $payload['debug'] = [
        'request_id' => $requestId,
        'use_sqlite' => $useSqlite,
        'sqlite_path' => $sqlitePath,
        'min_duration' => $minDuration,
        'sqlite_diagnostics' => $sqliteDiagnostics,
        'sync_stats' => $syncStats,
        'attempt_trace' => $attemptTrace,
    ];
}
jsonResponse(200, $payload);
exit;
