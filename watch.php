<?php
declare(strict_types=1);

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

ini_set('log_errors', '1');
error_reporting(E_ALL);
header('Content-Type: application/json; charset=utf-8');

$sqlitePath = getenv('SQLITE_PATH') ?: '/var/www/html/data/videos.sqlite';
$assetId = $_GET['id'] ?? '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $assetId === '') {
    $assetId = $_POST['id'] ?? '';
}

if (!is_string($assetId) || $assetId === '') {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'missing_id']);
    exit;
}

if (!extension_loaded('pdo_sqlite')) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'pdo_sqlite_not_loaded']);
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

    echo json_encode([
        'ok' => true,
        'asset_id' => $assetId,
        'rows_updated' => $stmt->rowCount(),
    ]);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'ok' => false,
        'error' => $e->getMessage(),
        'sqlite_path' => $sqlitePath,
        'diagnostics' => sqlitePathDiagnostics($sqlitePath),
    ]);
}
