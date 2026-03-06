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

function buildApiUrl(string $baseUrl, string $path): string
{
    return rtrim($baseUrl, '/') . '/' . ltrim($path, '/');
}

function syncFavoriteToImmich(string $immichUrl, string $apiKey, string $assetId, bool $favorite): array
{
    $endpoint = buildApiUrl($immichUrl, '/api/assets');
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
            CURLOPT_TIMEOUT => 20,
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

ini_set('log_errors', '1');
error_reporting(E_ALL);
header('Content-Type: application/json; charset=utf-8');

$immichUrl = getenv('IMMICH_URL') ?: '';
$apiKey = getenv('IMMICH_API_KEY') ?: '';
$sqlitePath = getenv('SQLITE_PATH') ?: '/var/www/html/data/videos.sqlite';
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
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'missing_id']);
    exit;
}

if (!is_string($favoriteRaw) || ($favoriteRaw !== '0' && $favoriteRaw !== '1')) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'missing_or_invalid_favorite']);
    exit;
}
$favorite = $favoriteRaw === '1';

if ($immichUrl === '' || $apiKey === '') {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'missing_immich_env']);
    exit;
}

if (!extension_loaded('pdo_sqlite')) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'pdo_sqlite_not_loaded']);
    exit;
}

$immichResult = syncFavoriteToImmich($immichUrl, $apiKey, $assetId, $favorite);
if (($immichResult['ok'] ?? false) !== true) {
    http_response_code(502);
    echo json_encode([
        'ok' => false,
        'error' => 'failed_to_update_immich_favorite',
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

    echo json_encode([
        'ok' => true,
        'asset_id' => $assetId,
        'favorite' => $favorite,
        'rows_updated' => $stmt->rowCount(),
        'immich_status' => $immichResult['status'] ?? null,
        'immich_method' => $immichResult['method'] ?? null,
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
