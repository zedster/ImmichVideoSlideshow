<?php
declare(strict_types=1);

require_once __DIR__ . '/helpers.php';

ini_set('log_errors', '1');
error_reporting(E_ALL);

$sqlitePath = getenv('SQLITE_PATH') ?: DEFAULT_SQLITE_PATH;
$assetId = $_GET['id'] ?? '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $assetId === '') {
    $assetId = $_POST['id'] ?? '';
}

if (!is_string($assetId) || $assetId === '') {
    jsonErrorResponse(400, ERROR_MISSING_ID, 'missing_id');
    exit;
}

if (!extension_loaded('pdo_sqlite')) {
    jsonErrorResponse(500, ERROR_PDO_SQLITE_NOT_LOADED, 'pdo_sqlite_not_loaded');
    exit;
}

try {
    $pdo = openSqliteStrict($sqlitePath);
    $stmt = $pdo->prepare(
        'UPDATE videos
         SET watched_count = COALESCE(watched_count, 0) + 1,
             updated_at = :updated_at
         WHERE asset_id = :asset_id'
    );
    $stmt->execute([
        ':updated_at' => gmdate('c'),
        ':asset_id' => $assetId,
    ]);

    jsonResponse(200, [
        'ok' => true,
        'asset_id' => $assetId,
        'rows_updated' => $stmt->rowCount(),
    ]);
} catch (Throwable $e) {
    jsonErrorResponse(500, ERROR_SQLITE_WRITE_FAILED, $e->getMessage(), [
        'sqlite_path' => $sqlitePath,
        'diagnostics' => sqlitePathDiagnostics($sqlitePath),
    ]);
}
