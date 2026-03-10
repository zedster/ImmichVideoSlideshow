<?php
declare(strict_types=1);

require_once __DIR__ . '/helpers.php';

ini_set('log_errors', '1');
error_reporting(E_ALL);

$immichUrl = getenv('IMMICH_URL') ?: '';
$apiKey = getenv('IMMICH_API_KEY') ?: '';
$sqlitePath = getenv('SQLITE_PATH') ?: DEFAULT_SQLITE_PATH;

$requestSecurity = enforceMutationRequestSecurity();
if ($requestSecurity !== null) {
    jsonErrorResponse(
        (int) $requestSecurity['status'],
        (string) $requestSecurity['code'],
        (string) $requestSecurity['message']
    );
    exit;
}

$assetId = $_POST['id'] ?? ($_GET['id'] ?? '');
if (!is_string($assetId) || $assetId === '') {
    jsonErrorResponse(400, ERROR_MISSING_ID, 'missing_id');
    exit;
}

if ($immichUrl === '' || $apiKey === '') {
    jsonErrorResponse(500, ERROR_MISSING_IMMICH_ENV, 'missing_immich_env');
    exit;
}

if (!extension_loaded('pdo_sqlite')) {
    jsonErrorResponse(500, ERROR_PDO_SQLITE_NOT_LOADED, 'pdo_sqlite_not_loaded');
    exit;
}

$immichResult = archiveAssetToImmich($immichUrl, $apiKey, $assetId, true);
if (($immichResult['ok'] ?? false) !== true) {
    jsonErrorResponse(502, ERROR_FAILED_ARCHIVE_IMMICH_ASSET, 'failed_to_archive_immich_asset', [
        'details' => $immichResult['error'] ?? 'unknown',
    ]);
    exit;
}

try {
    $pdo = openSqliteStrict($sqlitePath);
    $stmt = $pdo->prepare('DELETE FROM videos WHERE asset_id = :asset_id');
    $stmt->execute([
        ':asset_id' => $assetId,
    ]);

    jsonResponse(200, [
        'ok' => true,
        'asset_id' => $assetId,
        'hidden' => true,
        'archived' => true,
        'rows_deleted' => $stmt->rowCount(),
        'immich_status' => $immichResult['status'] ?? null,
        'immich_method' => $immichResult['method'] ?? null,
        'immich_route' => $immichResult['route'] ?? null,
    ]);
} catch (Throwable $e) {
    jsonErrorResponse(500, ERROR_SQLITE_WRITE_FAILED, $e->getMessage(), [
        'sqlite_path' => $sqlitePath,
        'diagnostics' => sqlitePathDiagnostics($sqlitePath),
    ]);
}
