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

function envInt(string $name, int $default): int
{
    $raw = getenv($name);
    if ($raw === false || trim((string) $raw) === '') {
        return $default;
    }
    return (int) $raw;
}

function envFloat(string $name, float $default): float
{
    $raw = getenv($name);
    if ($raw === false || trim((string) $raw) === '') {
        return $default;
    }
    return (float) $raw;
}

$settings = [
    'minDuration' => max(0.0, envFloat('MIN_DURATION', 10.0)),
    'crossfadeEnabled' => envFlag('CROSSFADE_ENABLED', true),
    'crossfadeDurationMs' => max(0, envInt('CROSSFADE_DURATION', 450)),
    'preloadSecondsBeforeEnd' => max(0.25, envFloat('PRELOAD_SECONDS_BEFORE_END', 4.0)),
    'queueTargetSize' => max(1, min(5, envInt('QUEUE_TARGET_SIZE', 2))),
    'debugEnabled' => envFlag('DEBUG', false),
    'playbackOrder' => (string) (getenv('PLAYBACK_ORDER') ?: 'random'),
];
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>Immich Video Channel</title>
  <link rel="icon" type="image/svg+xml" href="/assets/favicon.svg">
  <link rel="icon" type="image/png" sizes="96x96" href="/assets/favicon-96x96.png">
  <link rel="icon" href="/assets/favicon.ico">
  <link rel="apple-touch-icon" sizes="180x180" href="/assets/apple-touch-icon.png">
  <link rel="manifest" href="/assets/site.webmanifest" crossorigin="use-credentials">
  <style>
    html, body {
      margin: 0;
      width: 100%;
      height: 100%;
      background: #000;
      overflow: hidden;
      font-family: system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif;
      -webkit-text-size-adjust: 100%;
      touch-action: manipulation;
    }

    #stage {
      position: fixed;
      inset: 0;
      background: #000;
    }

    .player {
      position: absolute;
      inset: 0;
      width: 100vw;
      height: 100vh;
      width: 100dvw;
      height: 100dvh;
      object-fit: contain;
      background: #000;
      opacity: 0;
      transition: opacity 0ms linear;
    }

    .player.active {
      opacity: 1;
    }

    .hud {
      position: fixed;
      left: calc(12px + env(safe-area-inset-left));
      right: calc(12px + env(safe-area-inset-right));
      bottom: calc(12px + env(safe-area-inset-bottom));
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 10px;
      z-index: 20;
      pointer-events: none;
      transition: opacity 180ms ease;
    }

    .chip {
      pointer-events: auto;
      color: #fff;
      background: rgba(0, 0, 0, 0.6);
      border: 1px solid rgba(255, 255, 255, 0.25);
      border-radius: 6px;
      padding: 6px 9px;
      font-size: 12px;
      line-height: 1.2;
      backdrop-filter: blur(2px);
    }

    .info-qr-wrap {
      margin: 10px 0 8px 0;
      border: 1px solid rgba(255, 255, 255, 0.2);
      border-radius: 8px;
      padding: 8px;
      background: rgba(255, 255, 255, 0.04);
    }

    .info-qr-title {
      margin: 0 0 6px 0;
      font-size: 12px;
      opacity: 0.9;
    }

    .info-qr-code {
      width: 160px;
      height: 160px;
      margin: 0 auto;
      background: #fff;
    }

    .info-qr-link {
      display: block;
      margin-top: 8px;
      font-size: 11px;
      color: #d9ecff;
      text-decoration: none;
      word-break: break-all;
      max-height: 2.8em;
      overflow: hidden;
    }

    .controls {
      display: flex;
      gap: 8px;
      pointer-events: auto;
      flex-wrap: wrap;
    }

    .btn {
      border: 1px solid rgba(255, 255, 255, 0.35);
      color: #fff;
      background: rgba(0, 0, 0, 0.6);
      border-radius: 6px;
      min-width: 44px;
      min-height: 44px;
      padding: 8px 10px;
      font-size: 16px;
      line-height: 1;
      cursor: pointer;
      -webkit-tap-highlight-color: transparent;
    }

    .btn[aria-pressed="true"] {
      border-color: rgba(120, 210, 255, 0.95);
      background: rgba(15, 55, 75, 0.8);
    }

    .panel {
      position: fixed;
      top: calc(12px + env(safe-area-inset-top));
      left: calc(12px + env(safe-area-inset-left));
      z-index: 24;
      min-width: 260px;
      max-width: min(86vw, 420px);
      max-height: 62vh;
      overflow: auto;
      display: none;
      color: #fff;
      background: rgba(0, 0, 0, 0.7);
      border: 1px solid rgba(255, 255, 255, 0.25);
      border-radius: 8px;
      padding: 10px;
      backdrop-filter: blur(2px);
      font-size: 12px;
      line-height: 1.35;
    }

    .panel h3 {
      margin: 0 0 8px 0;
      font-size: 13px;
      font-weight: 600;
    }

    .panel-row {
      margin: 0 0 6px 0;
      word-break: break-word;
    }

    .admin-actions {
      display: flex;
      flex-direction: column;
      gap: 8px;
      margin-top: 8px;
    }

    .admin-btn {
      border: 1px solid rgba(255, 255, 255, 0.35);
      color: #fff;
      background: rgba(0, 0, 0, 0.6);
      border-radius: 6px;
      min-height: 38px;
      padding: 8px 10px;
      font-size: 13px;
      text-align: left;
      cursor: pointer;
    }

    .admin-btn.danger {
      border-color: rgba(255, 120, 120, 0.7);
      background: rgba(60, 0, 0, 0.65);
    }

    .meta-caption {
      position: fixed;
      left: calc(24px + env(safe-area-inset-left));
      bottom: 10vh;
      z-index: 18;
      color: #fff;
      font-size: clamp(14px, 2.6vw, 37px);
      font-weight: 700;
      line-height: 1.1;
      letter-spacing: 0.01em;
      text-shadow:
        -2px -2px 0 #000,
         2px -2px 0 #000,
        -2px  2px 0 #000,
         2px  2px 0 #000,
         0px  3px 8px rgba(0, 0, 0, 0.7);
      max-width: 80vw;
      pointer-events: none;
      display: none;
      white-space: pre-line;
    }

    .progress-wrap {
      position: fixed;
      left: calc(12px + env(safe-area-inset-left));
      right: calc(12px + env(safe-area-inset-right));
      bottom: calc(52px + env(safe-area-inset-bottom));
      z-index: 19;
      pointer-events: none;
      transition: opacity 180ms ease;
    }

    .progress-track {
      width: 100%;
      height: 8px;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.25);
      overflow: hidden;
    }

    .progress-fill {
      width: 0%;
      height: 100%;
      background: #ffffff;
      box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.2) inset;
    }

    .progress-remaining {
      margin-top: 4px;
      font-size: 12px;
      color: #fff;
      text-align: right;
      text-shadow: 0 1px 3px rgba(0, 0, 0, 0.85);
    }

    #fallback {
      position: fixed;
      top: calc(12px + env(safe-area-inset-top));
      left: 50%;
      transform: translateX(-50%);
      z-index: 30;
      color: #ffd8d8;
      background: rgba(60, 0, 0, 0.72);
      border: 1px solid rgba(255, 120, 120, 0.6);
      border-radius: 8px;
      padding: 8px 10px;
      font: 12px/1.3 monospace;
      display: none;
      white-space: pre-wrap;
      text-align: center;
      max-width: 90vw;
    }

    #issuePopup {
      position: fixed;
      top: calc(12px + env(safe-area-inset-top));
      right: calc(12px + env(safe-area-inset-right));
      z-index: 31;
      color: #fff5cf;
      background: rgba(70, 40, 0, 0.8);
      border: 1px solid rgba(255, 200, 90, 0.72);
      border-radius: 8px;
      padding: 10px 12px;
      font: 12px/1.35 system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif;
      display: none;
      white-space: pre-wrap;
      max-width: min(84vw, 460px);
      box-shadow: 0 8px 20px rgba(0, 0, 0, 0.35);
    }

    body.controls-hidden .hud,
    body.controls-hidden .progress-wrap {
      opacity: 0;
      pointer-events: none;
    }

    @media (max-width: 900px) {
      .controls {
        gap: 6px;
      }

      .btn {
        min-width: 42px;
        min-height: 42px;
        font-size: 15px;
      }

      .chip {
        font-size: 11px;
      }
    }
  </style>
</head>
<body>
  <div id="stage">
    <video id="v0" class="player active" muted playsinline preload="auto"></video>
    <video id="v1" class="player" muted playsinline preload="auto"></video>
  </div>

  <div id="fallback"></div>
  <div id="issuePopup"></div>
  <div id="metaCaption" class="meta-caption"></div>
  <div id="progressWrap" class="progress-wrap">
    <div class="progress-track">
      <div id="progressFill" class="progress-fill"></div>
    </div>
    <div id="progressRemaining" class="progress-remaining"></div>
  </div>
  <div id="adminPanel" class="panel">
    <h3>Admin</h3>
    <div class="panel-row">Manage current video and local cache sync.</div>
    <div class="admin-actions">
      <button id="adminPlaybackOrderBtn" class="admin-btn" type="button">Playback Order</button>
      <button id="adminFavOnlyBtn" class="admin-btn" type="button">Toggle Favorites Filter</button>
      <button id="adminHideBtn" class="admin-btn danger" type="button">Hide Forever Current Video</button>
      <button id="adminResyncBtn" class="admin-btn" type="button">Force Resync SQLite from Immich</button>
    </div>
  </div>
  <div id="infoPanel" class="panel"></div>
  <div id="statsPanel" class="panel"></div>

  <div class="hud">
    <div class="controls">
      <button id="backBtn" class="btn" type="button" title="Back to previous video (←)">⏮</button>
      <button id="skipBtn" class="btn" type="button" title="Skip">⏭</button>
      <button id="pauseBtn" class="btn" type="button" title="Pause or play (space)">⏸</button>
      <button id="favoriteBtn" class="btn" type="button" title="Toggle favorite (f)">♡</button>
      <button id="adminBtn" class="btn" type="button" title="Admin" aria-pressed="false">⚙</button>
      <button id="muteBtn" class="btn" type="button" title="Mute or unmute">🔇</button>
      <button id="infoBtn" class="btn" type="button" title="Video info (i)" aria-pressed="false">ℹ</button>
      <button id="statsBtn" class="btn" type="button" title="Library stats (s)" aria-pressed="false">📊</button>
      <button id="fullscreenBtn" class="btn" type="button" title="Toggle fullscreen">⤢</button>
      <?php if ($settings['debugEnabled']): ?>
      <div id="status" class="chip"></div>
      <?php endif; ?>
    </div>
  </div>

  <script src="/qrcode.min.js"></script>
  <script>
    const settings = <?= json_encode($settings, JSON_UNESCAPED_SLASHES) ?>;

    const players = [
      document.getElementById('v0'),
      document.getElementById('v1'),
    ];
    const statusEl = document.getElementById('status');
    const fallbackEl = document.getElementById('fallback');
    const issuePopupEl = document.getElementById('issuePopup');
    const metaCaptionEl = document.getElementById('metaCaption');
    const progressWrapEl = document.getElementById('progressWrap');
    const progressFillEl = document.getElementById('progressFill');
    const progressRemainingEl = document.getElementById('progressRemaining');
    const adminPanelEl = document.getElementById('adminPanel');
    const adminPlaybackOrderBtn = document.getElementById('adminPlaybackOrderBtn');
    const adminFavOnlyBtn = document.getElementById('adminFavOnlyBtn');
    const adminHideBtn = document.getElementById('adminHideBtn');
    const adminResyncBtn = document.getElementById('adminResyncBtn');
    const infoPanelEl = document.getElementById('infoPanel');
    const statsPanelEl = document.getElementById('statsPanel');
    const backBtn = document.getElementById('backBtn');
    const skipBtn = document.getElementById('skipBtn');
    const pauseBtn = document.getElementById('pauseBtn');
    const favoriteBtn = document.getElementById('favoriteBtn');
    const adminBtn = document.getElementById('adminBtn');
    const muteBtn = document.getElementById('muteBtn');
    const infoBtn = document.getElementById('infoBtn');
    const statsBtn = document.getElementById('statsBtn');
    const fullscreenBtn = document.getElementById('fullscreenBtn');
    const CONTROL_INACTIVITY_MS = 10000;

    const muteStorageKey = 'immichChannelMuted';
    let activeIndex = 0;
    let queue = [];
    let inflightFetches = 0;
    let transitionInProgress = false;
    let preparingNext = false;
    let nextPreparedId = '';
    let currentItem = null;
    let adminVisible = false;
    let infoVisible = false;
    let statsVisible = false;
    let historyStack = [];
    let sessionVideosStarted = 0;
    let sessionSkips = 0;
    let hideUpdateInProgress = false;
    let resyncInProgress = false;
    let currentPlaybackWatchMarked = false;
    let controlsHideTimer = null;
    let autoplayBlocked = false;
    let issuePopupTimer = null;
    let lastIssuePopupKey = '';
    let lastIssuePopupAt = 0;
    let lastProgressAtMs = Date.now();
    let lastProgressTime = 0;
    let stallRecoveryInProgress = false;
    const sessionUniqueIds = new Set();
    const failedAssetMap = new Map();
    const FAILED_ASSET_COOLDOWN_MS = 5 * 60 * 1000;
    const PLAYBACK_ORDER_VALUES = ['random', 'sequential_oldest', 'sequential_newest'];
    const STALL_TRIGGER_MS = 12000;
    const PROGRESS_DELTA_SECONDS = 0.12;

    const normalizePlaybackOrder = (value) => {
      const raw = String(value || '').trim().toLowerCase();
      if (raw === 'sequential') return 'sequential_oldest';
      if (PLAYBACK_ORDER_VALUES.includes(raw)) return raw;
      return 'random';
    };

    const playbackOrderLabel = (value) => {
      const order = normalizePlaybackOrder(value);
      if (order === 'sequential_oldest') return 'Sequential Oldest -> Newest';
      if (order === 'sequential_newest') return 'Sequential Newest -> Oldest';
      return 'Random';
    };

    const getPlaybackOrder = () => {
      const current = new URL(window.location.href);
      return normalizePlaybackOrder(current.searchParams.get('playbackOrder') || settings.playbackOrder || 'random');
    };

    const isSequentialMode = () => {
      const order = getPlaybackOrder();
      return order === 'sequential_oldest' || order === 'sequential_newest';
    };

    const updateAdminPlaybackOrderButton = () => {
      const order = getPlaybackOrder();
      adminPlaybackOrderBtn.textContent = `Playback Order: ${playbackOrderLabel(order)}`;
    };

    const setPlaybackOrder = (order) => {
      const nextOrder = normalizePlaybackOrder(order);
      const current = new URL(window.location.href);
      current.searchParams.set('playbackOrder', nextOrder);
      window.history.replaceState({}, '', current.toString());
      updateAdminPlaybackOrderButton();
      updateStatus();
    };

    const cyclePlaybackOrder = () => {
      noteInteraction();
      const current = getPlaybackOrder();
      const idx = PLAYBACK_ORDER_VALUES.indexOf(current);
      const next = PLAYBACK_ORDER_VALUES[(idx + 1) % PLAYBACK_ORDER_VALUES.length];
      setPlaybackOrder(next);

      queue = [];
      nextPreparedId = '';
      failedAssetMap.clear();
      clearPlayer(hiddenPlayer());
      fillQueue();
      maybePrepareNext();

      setFallback(`Playback order: ${playbackOrderLabel(next)}`);
      window.setTimeout(() => {
        const text = fallbackEl.textContent || '';
        if (text.startsWith('Playback order:')) {
          setFallback('');
        }
      }, 1400);
    };

    const readMutedPreference = () => {
      try {
        const raw = localStorage.getItem(muteStorageKey);
        if (raw === null) return true;
        return raw === '1';
      } catch (e) {
        return true;
      }
    };

    const saveMutedPreference = (muted) => {
      try {
        localStorage.setItem(muteStorageKey, muted ? '1' : '0');
      } catch (e) {}
    };

    const preferredMuted = readMutedPreference();
    players.forEach((p) => {
      p.muted = preferredMuted;
      p.volume = 1;
    });

    const updateMuteButton = () => {
      const muted = players[activeIndex].muted;
      muteBtn.textContent = muted ? '🔇' : '🔊';
      muteBtn.title = muted ? 'Unmute' : 'Mute';
    };

    const hideControls = () => {
      if (infoVisible || statsVisible) {
        scheduleControlsHide();
        return;
      }
      document.body.classList.add('controls-hidden');
    };

    const showControls = () => {
      document.body.classList.remove('controls-hidden');
    };

    const scheduleControlsHide = () => {
      if (controlsHideTimer !== null) {
        window.clearTimeout(controlsHideTimer);
      }
      controlsHideTimer = window.setTimeout(() => {
        hideControls();
      }, CONTROL_INACTIVITY_MS);
    };

    const noteInteraction = () => {
      showControls();
      scheduleControlsHide();
    };

    const updatePauseButton = () => {
      const paused = activePlayer().paused;
      pauseBtn.textContent = paused ? '▶' : '⏸';
      pauseBtn.title = paused ? 'Play (space)' : 'Pause (space)';
    };

    const isFullscreen = () => {
      return Boolean(
        document.fullscreenElement ||
        document.webkitFullscreenElement
      );
    };

    const updateFullscreenButton = () => {
      fullscreenBtn.textContent = isFullscreen() ? '⤡' : '⤢';
      fullscreenBtn.title = isFullscreen() ? 'Exit fullscreen' : 'Enter fullscreen';
    };

    const toggleFullscreen = async () => {
      const docEl = document.documentElement;
      const current = activePlayer();

      try {
        if (isFullscreen()) {
          if (typeof document.exitFullscreen === 'function') {
            await document.exitFullscreen();
            return;
          }
          if (typeof document.webkitExitFullscreen === 'function') {
            document.webkitExitFullscreen();
            return;
          }
          if (typeof current.webkitExitFullscreen === 'function') {
            current.webkitExitFullscreen();
            return;
          }
          return;
        }

        if (typeof docEl.requestFullscreen === 'function') {
          await docEl.requestFullscreen();
          return;
        }
        if (typeof docEl.webkitRequestFullscreen === 'function') {
          docEl.webkitRequestFullscreen();
          return;
        }
        // iOS Safari fallback: fullscreen video element.
        if (typeof current.webkitEnterFullscreen === 'function') {
          current.webkitEnterFullscreen();
        }
      } catch (err) {
        console.warn('Fullscreen toggle failed', err);
      } finally {
        updateFullscreenButton();
      }
    };

    const setFallback = (text) => {
      fallbackEl.textContent = text;
      fallbackEl.style.display = text ? 'block' : 'none';
    };

    const showIssuePopup = (title, details = '', timeoutMs = 7000) => {
      const key = `${title}|${details}`;
      const now = Date.now();
      if (key === lastIssuePopupKey && (now - lastIssuePopupAt) < 2500) {
        return;
      }
      lastIssuePopupKey = key;
      lastIssuePopupAt = now;

      const safeTitle = String(title || '').trim();
      const safeDetails = String(details || '').trim();
      issuePopupEl.textContent = safeDetails ? `${safeTitle}\n${safeDetails}` : safeTitle;
      issuePopupEl.style.display = 'block';
      if (issuePopupTimer !== null) {
        window.clearTimeout(issuePopupTimer);
      }
      issuePopupTimer = window.setTimeout(() => {
        issuePopupEl.style.display = 'none';
      }, Math.max(1500, timeoutMs));
    };

    const videoErrorText = (video) => {
      const code = Number(video?.error?.code || 0);
      if (code === 1) return 'Playback aborted.';
      if (code === 2) return 'Network error while streaming.';
      if (code === 3) return 'Decoding error.';
      if (code === 4) return 'Video format/source unsupported.';
      return 'Unknown playback error.';
    };

    const resetProgressWatchdog = (video) => {
      lastProgressAtMs = Date.now();
      lastProgressTime = Number(video?.currentTime || 0);
      stallRecoveryInProgress = false;
    };

    const markPlaybackProgress = (video) => {
      const now = Date.now();
      const current = Number(video?.currentTime || 0);
      if (!Number.isFinite(current)) {
        return;
      }
      if (Math.abs(current - lastProgressTime) >= PROGRESS_DELTA_SECONDS) {
        lastProgressTime = current;
        lastProgressAtMs = now;
        stallRecoveryInProgress = false;
      }
    };

    const apiNextUrl = (afterAssetId = '') => {
      const url = new URL('/api.php', window.location.origin);
      url.searchParams.set('next', '1');
      const current = new URL(window.location.href);
      if (current.searchParams.get('favOnly') === '1') {
        url.searchParams.set('favOnly', '1');
      }
      const playbackOrder = normalizePlaybackOrder(current.searchParams.get('playbackOrder') || settings.playbackOrder || 'random');
      url.searchParams.set('playbackOrder', playbackOrder);
      if (afterAssetId) {
        url.searchParams.set('afterAssetId', String(afterAssetId));
      }
      url.searchParams.set('t', String(Date.now()));
      return url.toString();
    };

    const isFavOnlyMode = () => {
      const current = new URL(window.location.href);
      return current.searchParams.get('favOnly') === '1';
    };

    const updateAdminFavOnlyButton = () => {
      if (isFavOnlyMode()) {
        adminFavOnlyBtn.textContent = 'Mode: Favorites Only (Show All)';
      } else {
        adminFavOnlyBtn.textContent = 'Mode: All Videos (Favorites Only)';
      }
    };

    const setFavOnlyMode = (enabled) => {
      const current = new URL(window.location.href);
      if (enabled) {
        current.searchParams.set('favOnly', '1');
      } else {
        current.searchParams.delete('favOnly');
      }
      window.history.replaceState({}, '', current.toString());
      updateAdminFavOnlyButton();
    };

    const toggleFavOnlyMode = () => {
      noteInteraction();
      const enableFavoritesOnly = !isFavOnlyMode();
      setFavOnlyMode(enableFavoritesOnly);

      queue = [];
      nextPreparedId = '';
      failedAssetMap.clear();
      clearPlayer(hiddenPlayer());
      fillQueue();
      maybePrepareNext();

      setFallback(enableFavoritesOnly ? 'Favorites-only mode enabled.' : 'Favorites-only mode disabled.');
      window.setTimeout(() => {
        const text = fallbackEl.textContent || '';
        if (text.startsWith('Favorites-only mode')) {
          setFallback('');
        }
      }, 1400);
    };

    const normalizeItem = (payload) => {
      return {
        id: String(payload.asset_id || payload.id || ''),
        title: String(payload.metadata?.file_name || 'Untitled'),
        duration: Number(payload.metadata?.duration || 0),
        src: String(payload.video_src || ''),
        immichAssetUrl: String(payload.metadata?.immich_asset_url || ''),
        showQrCode: String(payload.metadata?.show_qr_code || '0') === '1',
        isFavorite: String(payload.metadata?.is_favorite || '0') === '1',
        metadata: payload.metadata || {},
        stats: payload.stats || {},
      };
    };

    const updateFavoriteButton = () => {
      const isFavorite = Boolean(currentItem?.isFavorite);
      favoriteBtn.textContent = isFavorite ? '♥' : '♡';
      favoriteBtn.title = isFavorite ? 'Unfavorite (f)' : 'Favorite (f)';
    };

    const isAssetCoolingDown = (assetId) => {
      const entry = failedAssetMap.get(assetId);
      if (!entry) return false;
      return (Date.now() - entry.lastFailedAt) < FAILED_ASSET_COOLDOWN_MS;
    };

    const markAssetFailed = (assetId) => {
      if (!assetId) return;
      const now = Date.now();
      const existing = failedAssetMap.get(assetId);
      if (existing) {
        existing.count += 1;
        existing.lastFailedAt = now;
        failedAssetMap.set(assetId, existing);
      } else {
        failedAssetMap.set(assetId, { count: 1, lastFailedAt: now });
      }
    };

    const markAssetRecovered = (assetId) => {
      if (!assetId) return;
      failedAssetMap.delete(assetId);
    };

    const escapeHtml = (value) => String(value)
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

    const panelRow = (label, value) => {
      if (value === undefined || value === null || String(value).trim() === '') {
        return '';
      }
      return `<div class="panel-row"><strong>${escapeHtml(label)}:</strong> ${escapeHtml(value)}</div>`;
    };

    const formatDuration = (seconds) => {
      const value = Number(seconds);
      if (!Number.isFinite(value) || value <= 0) return '';
      const total = Math.floor(value);
      const h = Math.floor(total / 3600);
      const m = Math.floor((total % 3600) / 60);
      const s = total % 60;
      if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
      return `${m}:${String(s).padStart(2, '0')}`;
    };

    const formatMonthYearFromCaptureDate = (value) => {
      if (!value) return '';
      const date = new Date(String(value));
      if (!Number.isNaN(date.getTime())) {
        return date.toLocaleDateString(undefined, { month: 'short', year: 'numeric' });
      }

      const match = String(value).match(/(\d{4})-(\d{2})/);
      if (match) {
        const year = Number(match[1]);
        const month = Number(match[2]);
        if (month >= 1 && month <= 12) {
          const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
          return `${names[month - 1]} ${year}`;
        }
      }
      return '';
    };

    const updateMetaCaption = (item) => {
      const metadata = item?.metadata || {};
      const monthYear = formatMonthYearFromCaptureDate(metadata.capture_date);
      const location = [metadata.city, metadata.country].filter(Boolean).join(', ');
      const lines = [monthYear, location].filter(Boolean);
      if (lines.length === 0) {
        metaCaptionEl.style.display = 'none';
        metaCaptionEl.textContent = '';
        return;
      }
      metaCaptionEl.textContent = lines.join('\n');
      metaCaptionEl.style.display = 'block';
    };

    const updateProgressUI = (video) => {
      if (!video || !Number.isFinite(video.duration) || video.duration <= 0) {
        progressFillEl.style.width = '0%';
        progressRemainingEl.textContent = '';
        return;
      }

      const current = Math.max(0, Number(video.currentTime) || 0);
      const duration = Number(video.duration);
      const ratio = Math.max(0, Math.min(1, current / duration));
      const remaining = Math.max(0, duration - current);
      progressFillEl.style.width = `${(ratio * 100).toFixed(2)}%`;
      progressRemainingEl.textContent = `${Math.ceil(remaining)}s remaining`;
    };

    const renderInfoPanel = (item) => {
      const metadata = item?.metadata || {};
      const watchedSeen = Number.parseInt(String(metadata.watched_count ?? '0'), 10);
      const metadataRows = Object.keys(metadata)
        .sort((a, b) => a.localeCompare(b))
        .map((key) => panelRow(formatMetadataLabel(key), metadataValueToString(metadata[key])))
        .join('');

      infoPanelEl.innerHTML = `
        <h3>Video Info</h3>
        ${panelRow('Session Playback Time', formatDuration(item.duration || metadata.duration))}
        ${panelRow('Times Watched/Seen', Number.isFinite(watchedSeen) ? watchedSeen : 0)}
        ${metadataRows}
        ${item.showQrCode && item.immichAssetUrl ? `
          <div class="info-qr-wrap">
            <p class="info-qr-title">Open in Immich</p>
            <div id="infoQrCode" class="info-qr-code"></div>
            <a class="info-qr-link" href="${escapeHtml(item.immichAssetUrl)}" target="_blank" rel="noopener noreferrer">${escapeHtml(item.immichAssetUrl)}</a>
          </div>
        ` : ''}
      `;

      if (item.showQrCode && item.immichAssetUrl && typeof QRCode !== 'undefined') {
        const qrTarget = document.getElementById('infoQrCode');
        if (qrTarget) {
          new QRCode(qrTarget, {
            text: item.immichAssetUrl,
            width: 160,
            height: 160,
            colorDark: '#000000',
            colorLight: '#ffffff',
            correctLevel: QRCode.CorrectLevel.M,
          });
        }
      }
    };

    const renderStatsPanel = (item) => {
      const stats = item?.stats || {};
      const parseTopList = (raw, nameKey) => {
        try {
          const parsed = JSON.parse(String(raw || '[]'));
          if (!Array.isArray(parsed)) return '';
          return parsed
            .filter((row) => row && typeof row === 'object')
            .map((row) => {
              const name = String(row[nameKey] ?? '').trim() || 'Unknown';
              const count = Number.parseInt(String(row.cnt ?? '0'), 10) || 0;
              return `${name} (${count})`;
            })
            .join(', ');
        } catch (_e) {
          return '';
        }
      };
      const topCameras = parseTopList(stats.db_top_cameras, 'camera_name');
      const topCodecs = parseTopList(stats.db_top_codecs, 'codec_name');
      const topResolutions = parseTopList(stats.db_top_resolutions, 'resolution_name');
      const topBitrates = parseTopList(stats.db_top_bitrates, 'bitrate_name');
      const topLocations = parseTopList(stats.db_top_locations, 'location_name');

      statsPanelEl.innerHTML = `
        <h3>Library Stats</h3>
        ${panelRow('Session Videos Started', sessionVideosStarted)}
        ${panelRow('Session Unique Videos', sessionUniqueIds.size)}
        ${panelRow('Session Skips', sessionSkips)}
        ${panelRow('Min Duration', stats.min_duration)}
        ${panelRow('SQLite', stats.use_sqlite)}
        ${panelRow('Favorites Only', stats.only_favorites)}
        ${panelRow('Playback Order', stats.playback_order || playbackOrderLabel(getPlaybackOrder()))}
        ${panelRow('Total Videos', stats.db_total_videos)}
        ${panelRow('Videos Matching Filter', stats.db_qualifying_videos)}
        ${panelRow('Favorite Videos', stats.db_favorite_videos)}
        ${panelRow('Total Watched', stats.db_total_watched)}
        ${panelRow('Top Cameras', topCameras)}
        ${panelRow('Top Codecs', topCodecs)}
        ${panelRow('Top Resolutions', topResolutions)}
        ${panelRow('Top Bitrates', topBitrates)}
        ${panelRow('Top Locations', topLocations)}
        ${panelRow('Last Sync', stats.last_sync_at)}
      `;
    };

    const syncPanelVisibility = () => {
      adminPanelEl.style.display = adminVisible ? 'block' : 'none';
      infoPanelEl.style.display = infoVisible ? 'block' : 'none';
      statsPanelEl.style.display = statsVisible ? 'block' : 'none';
      adminBtn.setAttribute('aria-pressed', adminVisible ? 'true' : 'false');
      infoBtn.setAttribute('aria-pressed', infoVisible ? 'true' : 'false');
      statsBtn.setAttribute('aria-pressed', statsVisible ? 'true' : 'false');
    };

    const toggleAdminPanel = () => {
      adminVisible = !adminVisible;
      syncPanelVisibility();
      noteInteraction();
    };

    const toggleInfoPanel = () => {
      infoVisible = !infoVisible;
      if (infoVisible && currentItem) renderInfoPanel(currentItem);
      syncPanelVisibility();
      noteInteraction();
    };

    const toggleStatsPanel = () => {
      statsVisible = !statsVisible;
      if (statsVisible && currentItem) renderStatsPanel(currentItem);
      syncPanelVisibility();
      noteInteraction();
    };

    const metadataValueToString = (value) => {
      if (value === undefined || value === null) return '';
      if (typeof value === 'object') {
        try {
          return JSON.stringify(value);
        } catch (e) {
          return '[object]';
        }
      }
      return String(value);
    };

    const formatMetadataLabel = (key) => key
      .replaceAll('_', ' ')
      .replace(/\b\w/g, (m) => m.toUpperCase());

    const recordSessionVideo = (item) => {
      if (!item || !item.id) {
        return;
      }
      sessionVideosStarted += 1;
      sessionUniqueIds.add(item.id);
    };

    const fetchNextItem = async (afterAssetId = '') => {
      const resp = await fetch(apiNextUrl(afterAssetId), { cache: 'no-store' });
      const body = await resp.json().catch(() => ({}));
      if (!resp.ok || body.ok !== true) {
        const message = body.error || `HTTP ${resp.status}`;
        throw new Error(message);
      }
      const item = normalizeItem(body);
      if (!item.id || !item.src) {
        throw new Error('Invalid next video payload');
      }
      return item;
    };

    const toggleFavorite = async () => {
      if (!currentItem || !currentItem.id) {
        return;
      }

      const nextFavorite = !currentItem.isFavorite;
      favoriteBtn.disabled = true;
      noteInteraction();
      try {
        const body = new URLSearchParams();
        body.set('id', currentItem.id);
        body.set('favorite', nextFavorite ? '1' : '0');

        const resp = await fetch('/favorite.php', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
          },
          body: body.toString(),
          cache: 'no-store',
        });
        const payload = await resp.json().catch(() => ({}));
        if (!resp.ok || payload.ok !== true) {
          const message = payload.error || `HTTP ${resp.status}`;
          throw new Error(message);
        }

        currentItem.isFavorite = nextFavorite;
        if (!currentItem.metadata) {
          currentItem.metadata = {};
        }
        currentItem.metadata.is_favorite = nextFavorite ? '1' : '0';
        updateFavoriteButton();
        if (infoVisible) {
          renderInfoPanel(currentItem);
        }
      } catch (err) {
        console.error('Favorite toggle failed', err);
        setFallback('Favorite update failed.');
      } finally {
        favoriteBtn.disabled = false;
      }
    };

    const hideCurrentVideoForever = async () => {
      if (!currentItem || !currentItem.id || hideUpdateInProgress) {
        return;
      }

      noteInteraction();
      const confirmed = window.confirm(
        'Are you sure? This hides the video in Immich too. The only way to unhide it is via the Immich website/app.'
      );
      if (!confirmed) {
        return;
      }

      hideUpdateInProgress = true;
      adminHideBtn.disabled = true;
      const targetId = currentItem.id;
      try {
        const body = new URLSearchParams();
        body.set('id', targetId);

        const resp = await fetch('/hide.php', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
          },
          body: body.toString(),
          cache: 'no-store',
        });
        const payload = await resp.json().catch(() => ({}));
        if (!resp.ok || payload.ok !== true) {
          const message = payload.error || `HTTP ${resp.status}`;
          throw new Error(message);
        }

        queue = queue.filter((item) => item.id !== targetId);
        historyStack = historyStack.filter((item) => item.id !== targetId);

        await transitionToNext('manual_hide');
      } catch (err) {
        console.error('Hide forever failed', err);
        setFallback('Hide forever failed.');
      } finally {
        hideUpdateInProgress = false;
        adminHideBtn.disabled = false;
      }
    };

    const forceResyncFromImmich = async () => {
      if (resyncInProgress) {
        return;
      }

      noteInteraction();
      const confirmed = window.confirm(
        'Force resync SQLite from Immich now? This may take a while on large libraries.'
      );
      if (!confirmed) {
        return;
      }

      resyncInProgress = true;
      adminResyncBtn.disabled = true;
      try {
        const url = new URL('/api.php', window.location.origin);
        url.searchParams.set('next', '1');
        url.searchParams.set('sync', '1');
        url.searchParams.set('t', String(Date.now()));

        const resp = await fetch(url.toString(), {
          method: 'GET',
          cache: 'no-store',
        });
        const payload = await resp.json().catch(() => ({}));
        if (!resp.ok || payload.ok !== true) {
          throw new Error(payload.error || `HTTP ${resp.status}`);
        }

        failedAssetMap.clear();
        fillQueue();
        const rows = payload?.debug?.sync_stats?.rows_upserted;
        if (Number.isFinite(rows)) {
          setFallback(`Resync complete: +${rows} rows`);
        } else {
          setFallback('Resync complete.');
        }
        window.setTimeout(() => {
          if ((fallbackEl.textContent || '').startsWith('Resync complete')) {
            setFallback('');
          }
        }, 2000);
      } catch (err) {
        console.error('Resync failed', err);
        setFallback('Force resync failed.');
      } finally {
        resyncInProgress = false;
        adminResyncBtn.disabled = false;
      }
    };

    const markCurrentVideoWatched = async () => {
      if (!currentItem || !currentItem.id || currentPlaybackWatchMarked) {
        return;
      }

      currentPlaybackWatchMarked = true;
      try {
        const body = new URLSearchParams();
        body.set('id', currentItem.id);

        const resp = await fetch('/watch.php', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
          },
          body: body.toString(),
          cache: 'no-store',
        });
        const payload = await resp.json().catch(() => ({}));
        if (!resp.ok || payload.ok !== true) {
          throw new Error(payload.error || `HTTP ${resp.status}`);
        }
      } catch (err) {
        // Allow retry on next ended/crossfade trigger if the request failed.
        currentPlaybackWatchMarked = false;
        console.error('Watch increment failed', err);
      }
    };

    const togglePause = () => {
      const v = activePlayer();
      if (v.paused) {
        // Resume only the active player; keep hidden player silent.
        hiddenPlayer().pause();
        v.play().catch(() => {});
      } else {
        // Pause both players to prevent hidden-element audio bleed.
        players[0].pause();
        players[1].pause();
      }
      updatePauseButton();
      noteInteraction();
    };

    const fillQueue = async () => {
      if (isSequentialMode()) {
        if (inflightFetches > 0) {
          return;
        }
        const targetSize = settings.queueTargetSize;
        let attempts = 0;
        while ((queue.length + inflightFetches) < targetSize && attempts < (targetSize * 3)) {
          attempts += 1;
          inflightFetches++;
          try {
            const afterAssetId = queue.length > 0
              ? queue[queue.length - 1].id
              : (currentItem?.id || '');
            const item = await fetchNextItem(afterAssetId);
            if (currentItem && item.id === currentItem.id) {
              continue;
            }
            if (queue.some((q) => q.id === item.id)) {
              continue;
            }
            if (isAssetCoolingDown(item.id)) {
              continue;
            }
            queue.push(item);
            updateStatus();
            maybePrepareNext();
            setFallback('');
          } catch (err) {
            console.error('Queue fetch failed', err);
            setFallback('Could not fetch next video. Retrying…');
          } finally {
            inflightFetches--;
            updateStatus();
          }
        }
        return;
      }

      while ((queue.length + inflightFetches) < settings.queueTargetSize) {
        inflightFetches++;
        fetchNextItem('')
          .then((item) => {
            if (currentItem && item.id === currentItem.id) {
              return;
            }
            if (queue.some((q) => q.id === item.id)) {
              return;
            }
            if (isAssetCoolingDown(item.id)) {
              return;
            }
            queue.push(item);
            updateStatus();
            maybePrepareNext();
            setFallback('');
          })
          .catch((err) => {
            console.error('Queue fetch failed', err);
            setFallback('Could not fetch next video. Retrying…');
          })
          .finally(() => {
            inflightFetches--;
            updateStatus();
          });
      }
    };

    const activePlayer = () => players[activeIndex];
    const hiddenPlayer = () => players[1 - activeIndex];

    const clearPlayer = (video) => {
      video.pause();
      video.removeAttribute('src');
      video.load();
      video.dataset.assetId = '';
      video.classList.remove('active');
      video.style.transitionDuration = '0ms';
      video.style.opacity = '0';
    };

    const isAutoplayBlockedError = (err) => {
      const name = String(err?.name || '');
      const message = String(err?.message || '').toLowerCase();
      return name === 'NotAllowedError' || message.includes('didn\'t interact') || message.includes('notallowederror');
    };

    const playWithMutedFallback = async (video, contextLabel) => {
      try {
        await video.play();
        autoplayBlocked = false;
        return;
      } catch (err) {
        console.warn(`${contextLabel} play failed, retrying muted`, err);
      }

      try {
        video.muted = true;
        players[0].muted = true;
        players[1].muted = true;
        saveMutedPreference(true);
        updateMuteButton();
        await video.play();
        autoplayBlocked = false;
      } catch (err) {
        if (isAutoplayBlockedError(err)) {
          autoplayBlocked = true;
          setFallback('Autoplay blocked by browser. Tap/click or press a key to continue.');
          const blocked = new Error('autoplay_blocked');
          blocked.cause = err;
          throw blocked;
        }
        throw err;
      }
    };

    const tryResumeAfterAutoplayBlock = async () => {
      if (!autoplayBlocked || !currentItem) {
        return;
      }
      const active = activePlayer();
      try {
        await playWithMutedFallback(active, 'Resume');
        autoplayBlocked = false;
        if ((fallbackEl.textContent || '').startsWith('Autoplay blocked')) {
          setFallback('');
        }
        updatePauseButton();
      } catch (_err) {
        // Still blocked or failed. Keep waiting for another interaction.
      }
    };

    const waitForCanPlay = (video, timeoutMs) => {
      return new Promise((resolve, reject) => {
        let done = false;
        const onReady = () => {
          if (done) return;
          done = true;
          cleanup();
          resolve();
        };
        const onError = () => {
          if (done) return;
          done = true;
          cleanup();
          reject(new Error('Video failed while buffering'));
        };
        const onTimeout = () => {
          if (done) return;
          done = true;
          cleanup();
          reject(new Error('Timed out waiting for buffered video'));
        };
        const cleanup = () => {
          video.removeEventListener('canplay', onReady);
          video.removeEventListener('loadeddata', onReady);
          video.removeEventListener('error', onError);
          window.clearTimeout(timer);
        };

        video.addEventListener('canplay', onReady, { once: true });
        video.addEventListener('loadeddata', onReady, { once: true });
        video.addEventListener('error', onError, { once: true });

        const timer = window.setTimeout(onTimeout, timeoutMs);
      });
    };

    const prepareHiddenWith = async (item) => {
      const hidden = hiddenPlayer();
      if (hidden.dataset.assetId === item.id && nextPreparedId === item.id) {
        return;
      }
      hidden.muted = activePlayer().muted;
      hidden.src = item.src;
      hidden.dataset.assetId = item.id;
      hidden.preload = 'auto';
      hidden.load();
      await waitForCanPlay(hidden, 12000);
      nextPreparedId = item.id;
    };

    const maybePrepareNext = async () => {
      if (preparingNext || transitionInProgress || queue.length === 0) {
        return;
      }
      preparingNext = true;
      try {
        await prepareHiddenWith(queue[0]);
      } catch (err) {
        console.error('Prepare next failed', err);
        const failed = queue.shift();
        if (failed?.id) {
          markAssetFailed(failed.id);
        }
        updateStatus();
        fillQueue();
      } finally {
        preparingNext = false;
      }
    };

    const playOnActivePlayer = async (item) => {
      const active = activePlayer();
      active.src = item.src;
      active.dataset.assetId = item.id;
      active.classList.add('active');
      active.style.opacity = '1';
      active.style.transitionDuration = '0ms';
      active.muted = players[0].muted;
      active.load();
      try {
        await playWithMutedFallback(active, 'Initial');
      } catch (err) {
        if (err instanceof Error && err.message === 'autoplay_blocked') {
          currentItem = item;
          updateMetaCaption(item);
          updateFavoriteButton();
          if (infoVisible) renderInfoPanel(item);
          if (statsVisible) renderStatsPanel(item);
          updateStatus();
          updateProgressUI(active);
        }
        throw err;
      }
      currentItem = item;
      recordSessionVideo(item);
      currentPlaybackWatchMarked = false;
      markAssetRecovered(item.id);
      updateMetaCaption(item);
      updateFavoriteButton();
      if (infoVisible) renderInfoPanel(item);
      if (statsVisible) renderStatsPanel(item);
      updateStatus();
      updateProgressUI(active);
      resetProgressWatchdog(active);
    };

    const swapPlayers = () => {
      const outgoingIdx = activeIndex;
      activeIndex = 1 - activeIndex;
      clearPlayer(players[outgoingIdx]);
    };

    const transitionToItem = async (nextItem, reason) => {
      const outgoing = activePlayer();
      const incoming = hiddenPlayer();
      const shouldCrossfade = settings.crossfadeEnabled;
      let preparedForCrossfade = true;

      try {
        await prepareHiddenWith(nextItem);
      } catch (err) {
        preparedForCrossfade = false;
        console.warn('Prepare hidden failed; falling back to direct load', err);
        incoming.src = nextItem.src;
        incoming.dataset.assetId = nextItem.id;
        incoming.preload = 'auto';
        incoming.load();
        await waitForCanPlay(incoming, 9000);
      }

      const canCrossfade = shouldCrossfade && preparedForCrossfade;
      incoming.muted = outgoing.muted;
      incoming.classList.add('active');
      incoming.style.transitionDuration = '0ms';
      incoming.style.opacity = canCrossfade ? '0' : '1';

      // Keep single-audio behavior even when fading visuals.
      if (canCrossfade) {
        outgoing.muted = true;
      } else {
        outgoing.pause();
      }

      await playWithMutedFallback(incoming, 'Transition');

      if (canCrossfade && settings.crossfadeDurationMs > 0) {
        const duration = settings.crossfadeDurationMs;
        incoming.style.transitionDuration = `${duration}ms`;
        outgoing.style.transitionDuration = `${duration}ms`;
        requestAnimationFrame(() => {
          incoming.style.opacity = '1';
          outgoing.style.opacity = '0';
        });
        await new Promise((resolve) => setTimeout(resolve, duration));
      } else {
        outgoing.style.opacity = '0';
        incoming.style.opacity = '1';
      }

      swapPlayers();
      currentItem = nextItem;
      recordSessionVideo(nextItem);
      currentPlaybackWatchMarked = false;
      markAssetRecovered(nextItem.id);
      updateMetaCaption(nextItem);
      updateFavoriteButton();
      if (infoVisible) renderInfoPanel(nextItem);
      if (statsVisible) renderStatsPanel(nextItem);
      updatePauseButton();
      nextPreparedId = '';
      setFallback('');
      resetProgressWatchdog(activePlayer());
    };

    const goBackToPrevious = async () => {
      if (transitionInProgress) {
        return;
      }
      noteInteraction();

      while (historyStack.length > 0 && currentItem && historyStack[historyStack.length - 1].id === currentItem.id) {
        historyStack.pop();
      }
      const previousItem = historyStack.pop();
      if (!previousItem) {
        setFallback('No previous video in session history.');
        return;
      }

      transitionInProgress = true;
      try {
        await transitionToItem(previousItem, 'back');
        fillQueue();
        maybePrepareNext();
      } catch (err) {
        console.error('Back transition failed', err);
        setFallback('Could not go back to previous video.');
      } finally {
        transitionInProgress = false;
      }
    };

    const transitionToNext = async (reason) => {
      if (transitionInProgress) {
        return;
      }
      if (reason === 'ended' || reason === 'near_end_crossfade') {
        await markCurrentVideoWatched();
      }
      if (reason === 'manual_skip' || reason === 'arrow_skip') {
        sessionSkips += 1;
      }
      transitionInProgress = true;
      try {
        if (queue.length === 0) {
          await fillQueue();
        }

        if (queue.length === 0) {
          setFallback('No eligible videos right now. Retrying…');
          window.setTimeout(() => {
            transitionInProgress = false;
            fillQueue();
          }, 2000);
          return;
        }

        let transitioned = false;
        let attempts = 0;
        if (currentItem) {
          historyStack.push(currentItem);
        }
        while (!transitioned && queue.length > 0 && attempts < 6) {
          attempts += 1;
          const nextItem = queue.shift();
          if (!nextItem) {
            break;
          }
          updateStatus();
          try {
            await transitionToItem(nextItem, reason);
            transitioned = true;
          } catch (err) {
            console.error('Transition candidate failed', nextItem.id, err);
            markAssetFailed(nextItem.id);
          }
        }

        if (!transitioned) {
          throw new Error('No playable transition candidate available');
        }

        fillQueue();
        maybePrepareNext();
      } catch (err) {
        console.error('Transition failed', reason, err);
        setFallback('Transition failed. Skipping to another video…');
        const hidden = hiddenPlayer();
        clearPlayer(hidden);
        nextPreparedId = '';
        fillQueue();
      } finally {
        transitionInProgress = false;
      }
    };

    const updateStatus = () => {
      if (!statusEl) {
        return;
      }
      const order = playbackOrderLabel(getPlaybackOrder());
      const mode = settings.crossfadeEnabled ? `fade ${settings.crossfadeDurationMs}ms` : 'cut';
      statusEl.textContent = `Queue ${queue.length}/${settings.queueTargetSize} · ${order} · ${mode}`;
    };

    const onActiveTimeUpdate = () => {
      const video = activePlayer();
      updateProgressUI(video);
      if (!isFinite(video.duration) || video.duration <= 0) {
        return;
      }
      const remaining = video.duration - video.currentTime;
      if (remaining <= settings.preloadSecondsBeforeEnd) {
        maybePrepareNext();
      }
      if (settings.crossfadeEnabled && remaining <= Math.max(0.15, settings.crossfadeDurationMs / 1000) && queue.length > 0) {
        transitionToNext('near_end_crossfade');
      }
      markPlaybackProgress(video);
    };

    const bindPlayerEvents = () => {
      players.forEach((video, idx) => {
        video.addEventListener('timeupdate', () => {
          if (idx === activeIndex) {
            onActiveTimeUpdate();
          }
        });
        video.addEventListener('ended', () => {
          if (idx === activeIndex) {
            transitionToNext('ended');
          }
        });
        video.addEventListener('error', () => {
          if (idx === activeIndex) {
            console.error('Active player error', video.error);
            showIssuePopup('Playback error', videoErrorText(video));
            transitionToNext('active_error');
          }
        });
        video.addEventListener('stalled', () => {
          if (idx === activeIndex && !video.paused) {
            showIssuePopup('Playback stalled', 'Stream interrupted. Attempting recovery...');
          }
        });
        video.addEventListener('waiting', () => {
          if (idx === activeIndex && !video.paused) {
            showIssuePopup('Buffering', 'Playback is waiting for data...');
          }
        });
        video.addEventListener('play', () => {
          if (idx === activeIndex) {
            updatePauseButton();
            resetProgressWatchdog(video);
          }
        });
        video.addEventListener('pause', () => {
          if (idx === activeIndex) updatePauseButton();
        });
      });
    };

    backBtn.addEventListener('click', () => {
      goBackToPrevious();
    });

    skipBtn.addEventListener('click', () => {
      transitionToNext('manual_skip');
    });

    pauseBtn.addEventListener('click', () => {
      togglePause();
    });

    favoriteBtn.addEventListener('click', () => {
      toggleFavorite();
    });

    adminBtn.addEventListener('click', () => {
      toggleAdminPanel();
    });

    adminFavOnlyBtn.addEventListener('click', () => {
      toggleFavOnlyMode();
    });

    adminPlaybackOrderBtn.addEventListener('click', () => {
      cyclePlaybackOrder();
    });

    adminHideBtn.addEventListener('click', () => {
      hideCurrentVideoForever();
    });

    adminResyncBtn.addEventListener('click', () => {
      forceResyncFromImmich();
    });

    muteBtn.addEventListener('click', () => {
      const nextMuted = !activePlayer().muted;
      players[0].muted = nextMuted;
      players[1].muted = nextMuted;
      saveMutedPreference(nextMuted);
      updateMuteButton();
      noteInteraction();
    });

    infoBtn.addEventListener('click', () => {
      toggleInfoPanel();
    });

    statsBtn.addEventListener('click', () => {
      toggleStatsPanel();
    });

    fullscreenBtn.addEventListener('click', () => {
      toggleFullscreen();
      noteInteraction();
    });

    window.addEventListener('keydown', (event) => {
      noteInteraction();
      tryResumeAfterAutoplayBlock();
      if (event.code === 'Space') {
        event.preventDefault();
        togglePause();
      }
      if (event.key === 'ArrowRight') {
        event.preventDefault();
        transitionToNext('arrow_skip');
      }
      if (event.key === 'ArrowLeft') {
        event.preventDefault();
        goBackToPrevious();
      }
      if (event.key.toLowerCase() === 'f') {
        event.preventDefault();
        toggleFavorite();
      }
      if (event.key.toLowerCase() === 'i') {
        event.preventDefault();
        toggleInfoPanel();
      }
      if (event.key.toLowerCase() === 's') {
        event.preventDefault();
        toggleStatsPanel();
      }
      if (event.key.toLowerCase() === 'a') {
        event.preventDefault();
        toggleAdminPanel();
      }
      if (event.key.toLowerCase() === 'o') {
        event.preventDefault();
        cyclePlaybackOrder();
      }
    });

    ['pointerdown', 'pointermove', 'touchstart', 'touchmove', 'mousemove', 'wheel', 'click'].forEach((eventName) => {
      window.addEventListener(eventName, noteInteraction, { passive: true });
    });
    ['pointerdown', 'touchstart', 'click'].forEach((eventName) => {
      window.addEventListener(eventName, () => {
        tryResumeAfterAutoplayBlock();
      }, { passive: true });
    });

    const bootstrap = async () => {
      bindPlayerEvents();
      updateMuteButton();
      updatePauseButton();
      updateFullscreenButton();
      updateStatus();
      updateAdminPlaybackOrderButton();
      updateAdminFavOnlyButton();
      syncPanelVisibility();
      showControls();
      scheduleControlsHide();

      document.addEventListener('fullscreenchange', updateFullscreenButton);
      document.addEventListener('webkitfullscreenchange', updateFullscreenButton);

      try {
        const first = await fetchNextItem(currentItem?.id || '');
        await playOnActivePlayer(first);
        fillQueue();
      } catch (err) {
        console.error('Initial load failed', err);
        setFallback('Could not load initial video. Retrying…');
      }

      // Keep queue filled over long runs.
      window.setInterval(() => {
        fillQueue();
      }, 2000);

      // Detect mid-stream hangs with no time progression.
      window.setInterval(() => {
        if (transitionInProgress || autoplayBlocked || stallRecoveryInProgress) {
          return;
        }
        if (!currentItem) {
          return;
        }
        const video = activePlayer();
        if (!video || video.paused || video.ended) {
          return;
        }
        markPlaybackProgress(video);
        const stalledForMs = Date.now() - lastProgressAtMs;
        if (stalledForMs < STALL_TRIGGER_MS) {
          return;
        }
        stallRecoveryInProgress = true;
        showIssuePopup(
          'Playback appears stuck',
          `No progress for ${Math.floor(stalledForMs / 1000)}s. Skipping to next video...`,
          5000
        );
        transitionToNext('stalled_watchdog')
          .catch((err) => {
            console.error('Stall recovery transition failed', err);
          })
          .finally(() => {
            resetProgressWatchdog(activePlayer());
          });
      }, 2000);

      // If startup failed, retry until recovered.
      window.setInterval(() => {
        if (autoplayBlocked) {
          return;
        }
        if (!currentItem && !transitionInProgress) {
          fetchNextItem(currentItem?.id || '')
            .then((item) => playOnActivePlayer(item))
            .then(() => {
              setFallback('');
              fillQueue();
            })
            .catch((err) => {
              console.error('Startup retry failed', err);
            });
        }
      }, 3000);
    };

    bootstrap();
  </script>
</body>
</html>
