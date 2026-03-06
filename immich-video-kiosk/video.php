<?php
declare(strict_types=1);

function buildApiUrl(string $baseUrl, string $path): string
{
    return rtrim($baseUrl, '/') . '/' . ltrim($path, '/');
}

$immichUrl = getenv('IMMICH_URL') ?: '';
$apiKey = getenv('IMMICH_API_KEY') ?: '';
$assetId = $_GET['id'] ?? '';

if ($immichUrl === '' || $apiKey === '') {
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    echo 'Server misconfiguration: missing IMMICH_URL or IMMICH_API_KEY.';
    exit;
}

if (!is_string($assetId) || $assetId === '') {
    http_response_code(400);
    header('Content-Type: text/plain; charset=utf-8');
    echo 'Missing required query parameter: id';
    exit;
}

$playbackUrl = buildApiUrl($immichUrl, '/api/assets/' . rawurlencode($assetId) . '/video/playback');

@set_time_limit(0);
@ini_set('zlib.output_compression', 'Off');
while (ob_get_level() > 0) {
    ob_end_clean();
}

$ch = curl_init($playbackUrl);
$headers = [
    'x-api-key: ' . $apiKey,
    'Accept: */*',
];

// Forward range requests so browser seeking/streaming works for large files.
if (isset($_SERVER['HTTP_RANGE']) && is_string($_SERVER['HTTP_RANGE'])) {
    $headers[] = 'Range: ' . $_SERVER['HTTP_RANGE'];
}

$hopByHop = [
    'connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailers',
    'transfer-encoding',
    'upgrade',
];

curl_setopt_array($ch, [
    CURLOPT_HTTPHEADER => $headers,
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_RETURNTRANSFER => false,
    CURLOPT_BINARYTRANSFER => true,
    CURLOPT_TIMEOUT => 0,
    CURLOPT_BUFFERSIZE => 1024 * 1024,
    CURLOPT_HEADERFUNCTION => static function ($curl, string $line) use ($hopByHop): int {
        $trimmed = trim($line);

        if ($trimmed === '') {
            return strlen($line);
        }

        if (str_starts_with($trimmed, 'HTTP/')) {
            $parts = explode(' ', $trimmed);
            if (isset($parts[1]) && is_numeric($parts[1])) {
                http_response_code((int) $parts[1]);
            }
            return strlen($line);
        }

        $pos = strpos($trimmed, ':');
        if ($pos === false) {
            return strlen($line);
        }

        $name = strtolower(trim(substr($trimmed, 0, $pos)));
        if (in_array($name, $hopByHop, true)) {
            return strlen($line);
        }

        header($trimmed, false);
        return strlen($line);
    },
    CURLOPT_WRITEFUNCTION => static function ($curl, string $chunk): int {
        echo $chunk;
        flush();
        return strlen($chunk);
    },
]);

$ok = curl_exec($ch);
if ($ok === false) {
    if (!headers_sent()) {
        http_response_code(502);
        header('Content-Type: text/plain; charset=utf-8');
    }
    echo 'Failed to stream video from Immich.';
}

curl_close($ch);
