<?php
declare(strict_types=1);

require_once __DIR__ . '/helpers.php';

ini_set('log_errors', '1');
error_reporting(E_ALL);

$immichUrl = getenv('IMMICH_URL') ?: '';
$apiKey = getenv('IMMICH_API_KEY') ?: '';
$sqlitePath = getenv('SQLITE_PATH') ?: DEFAULT_SQLITE_PATH;
$assetId = $_GET['id'] ?? '';
$favoriteRaw = $_GET['favorite'] ?? '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if ($assetId === '') {
        $assetId = $_POST['id'] ?? '';
    }
    if ($favoriteRaw === '') {
        $favoriteRaw = $_POST['favorite'] ?? '';
    }
}

if (!is_string($assetId) || $assetId === '') {
    jsonErrorResponse(400, ERROR_MISSING_ID, 'missing_id');
    exit;
}

if (!is_string($favoriteRaw) || ($favoriteRaw !== '0' && $favoriteRaw !== '1')) {
    jsonErrorResponse(400, ERROR_INVALID_FAVORITE, 'missing_or_invalid_favorite');
    exit;
}
$favorite = $favoriteRaw === '1';

if ($immichUrl === '' || $apiKey === '') {
    jsonErrorResponse(500, ERROR_MISSING_IMMICH_ENV, 'missing_immich_env');
    exit;
}

if (!extension_loaded('pdo_sqlite')) {
    jsonErrorResponse(500, ERROR_PDO_SQLITE_NOT_LOADED, 'pdo_sqlite_not_loaded');
    exit;
}

$immichResult = syncFavoriteToImmich($immichUrl, $apiKey, $assetId, $favorite);
if (($immichResult['ok'] ?? false) !== true) {
    jsonErrorResponse(502, ERROR_FAILED_UPDATE_IMMICH_FAVORITE, 'failed_to_update_immich_favorite', [
        'details' => $immichResult['error'] ?? 'unknown',
    ]);
    exit;
}

try {
    $pdo = openSqliteStrict($sqlitePath);
    $stmt = $pdo->prepare(
        'UPDATE videos
         SET is_favorite = :is_favorite,
             updated_at = :updated_at
         WHERE asset_id = :asset_id'
    );
    $stmt->execute([
        ':is_favorite' => $favorite ? 1 : 0,
        ':updated_at' => gmdate('c'),
        ':asset_id' => $assetId,
    ]);

    jsonResponse(200, [
        'ok' => true,
        'asset_id' => $assetId,
        'favorite' => $favorite,
        'rows_updated' => $stmt->rowCount(),
        'immich_status' => $immichResult['status'] ?? null,
        'immich_method' => $immichResult['method'] ?? null,
    ]);
} catch (Throwable $e) {
    jsonErrorResponse(500, ERROR_SQLITE_WRITE_FAILED, $e->getMessage(), [
        'sqlite_path' => $sqlitePath,
        'diagnostics' => sqlitePathDiagnostics($sqlitePath),
    ]);
}
