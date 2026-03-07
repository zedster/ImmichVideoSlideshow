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
      width: 100dvw;
      height: 100dvh;
      object-fit: contain;
      background: #000;
      display: block;
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

    .action-btn.wide {
      min-width: 72px;
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

    .video-caption.hidden {
      display: none;
    }

    .metadata-panel .metadata-pre {
      white-space: pre-wrap;
      margin-bottom: 10px;
    }

    .metadata-panel .meta-qr {
      margin-top: 8px;
      text-align: center;
    }

    .metadata-panel .meta-qr img {
      width: 150px;
      height: 150px;
      display: block;
      margin: 0 auto 6px;
      background: #fff;
    }

    .metadata-panel .meta-qr a {
      color: #fff;
      font: 12px/1.2 sans-serif;
      text-decoration: underline;
      word-break: break-word;
    }

    .next-countdown {
      position: fixed;
      left: 50%;
      top: 50%;
      transform: translate(-50%, -50%);
      z-index: 10000;
      color: #fff;
      background: rgba(0, 0, 0, 0.7);
      border: 1px solid #666;
      border-radius: 10px;
      padding: 14px 18px;
      font: 700 28px/1.1 sans-serif;
      text-align: center;
      display: none;
      pointer-events: none;
      -webkit-text-stroke: 1px #000;
      text-shadow: 0 2px 6px rgba(0, 0, 0, 0.9);
    }

    .next-countdown.visible {
      display: block;
    }

    .admin-trigger {
      position: fixed;
      right: 8px;
      bottom: 6px;
      z-index: 10001;
      background: transparent;
      border: none;
      color: rgba(255, 255, 255, 0.25);
      font: 700 18px/1 monospace;
      cursor: pointer;
      padding: 4px 6px;
    }

    .admin-panel {
      position: fixed;
      right: 12px;
      bottom: 28px;
      z-index: 10002;
      width: 280px;
      background: rgba(0, 0, 0, 0.88);
      border: 1px solid #666;
      color: #fff;
      padding: 12px;
      display: none;
      border-radius: 8px;
    }

    .admin-panel.visible {
      display: block;
    }

    .admin-title {
      font: 700 14px/1.2 sans-serif;
      margin-bottom: 10px;
    }

    .admin-row {
      display: flex;
      gap: 8px;
      justify-content: flex-end;
    }

    .admin-btn {
      border: 1px solid #666;
      background: rgba(255, 255, 255, 0.08);
      color: #fff;
      font: 12px/1.2 sans-serif;
      padding: 7px 9px;
      cursor: pointer;
      border-radius: 4px;
    }

    .admin-btn.primary {
      border-color: #2f7f2f;
      background: rgba(47, 127, 47, 0.3);
    }

    .load-error {
      position: fixed;
      left: 12px;
      top: 12px;
      z-index: 10003;
      background: rgba(40, 0, 0, 0.85);
      border: 1px solid #8f3a3a;
      color: #ffd0d0;
      padding: 10px 12px;
      max-width: 80vw;
      font: 12px/1.4 monospace;
      display: none;
      white-space: pre-wrap;
    }

    .load-error.visible {
      display: block;
    }
  </style>
</head>
<body>
  <video id="player" autoplay muted playsinline controls></video>
  <div class="action-bar">
    <button id="backBtn" class="action-btn wide" type="button" title="Back" aria-label="Back">↩</button>
    <button id="skipBtn" class="action-btn wide" type="button" title="Skip" aria-label="Skip">⏭</button>
    <button id="favoriteFilterToggle" class="action-btn" type="button" title="Favorites only" aria-label="Favorites only">⭐</button>
    <button id="statsToggle" class="action-btn" type="button" title="Stats" aria-label="Stats">📊</button>
    <button id="metaToggle" class="action-btn" type="button" title="Metadata" aria-label="Metadata">ⓘ</button>
    <button id="favoriteToggle" class="action-btn" type="button" title="Toggle favorite">♡</button>
    <button id="muteToggle" class="mute-toggle" type="button" title="Mute toggle" aria-label="Mute toggle">🔇</button>
  </div>
  <div id="videoCaption" class="video-caption hidden"></div>
  <button id="adminTrigger" class="admin-trigger" type="button" title="Admin">~</button>
  <div id="adminPanel" class="admin-panel" role="dialog" aria-modal="false" aria-label="Admin panel">
    <div class="admin-title">Admin Panel</div>
    <div id="adminLastSync" style="font:12px/1.3 monospace; margin-bottom:10px; color:#d0d0d0;">Last synced: -</div>
    <div class="admin-row">
      <button id="adminCloseBtn" class="admin-btn" type="button">Close</button>
      <button id="syncNowBtn" class="admin-btn primary" type="button">Sync With Immich</button>
    </div>
  </div>
  <div id="nextCountdown" class="next-countdown"></div>
  <div id="metadataPanel" class="metadata-panel"></div>
  <div id="statsPanel" class="stats-panel"></div>
  <div id="loadError" class="load-error"></div>

  <script>
    const player = document.getElementById('player');
    const backBtn = document.getElementById('backBtn');
    const skipBtn = document.getElementById('skipBtn');
    const favoriteFilterToggle = document.getElementById('favoriteFilterToggle');
    const statsToggle = document.getElementById('statsToggle');
    const metaToggle = document.getElementById('metaToggle');
    const favoriteToggle = document.getElementById('favoriteToggle');
    const muteToggle = document.getElementById('muteToggle');
    const metadataPanel = document.getElementById('metadataPanel');
    const statsPanel = document.getElementById('statsPanel');
    const adminTrigger = document.getElementById('adminTrigger');
    const adminPanel = document.getElementById('adminPanel');
    const adminCloseBtn = document.getElementById('adminCloseBtn');
    const adminLastSync = document.getElementById('adminLastSync');
    const syncNowBtn = document.getElementById('syncNowBtn');
    const nextCountdown = document.getElementById('nextCountdown');
    const videoCaption = document.getElementById('videoCaption');
    const loadError = document.getElementById('loadError');

    const muteStorageKey = 'immichVideoKioskMuted';
    const metadataStorageKey = 'immichVideoKioskShowMetadata';
    const sessionShownStorageKey = 'immichVideoKioskShownThisSession';

    let metadata = {};
    let stats = {};
    let isFavorite = false;
    let onlyFavoritesMode = false;
    let suppressMutePersist = false;
    let userInteracted = false;
    let nextTimerInterval = null;
    let nextTimerTimeout = null;

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

    const preferredMuted = readMutedPreference();

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

    const getShownThisSession = () => {
      const url = new URL(window.location.href);
      const fromUrl = parseInt(url.searchParams.get('shown') || '', 10);
      if (!Number.isNaN(fromUrl) && fromUrl >= 0) {
        return fromUrl;
      }
      try {
        const fromStorage = parseInt(window.sessionStorage.getItem(sessionShownStorageKey) || '0', 10);
        return Number.isNaN(fromStorage) ? 0 : Math.max(0, fromStorage);
      } catch (e) {
        return 0;
      }
    };

    const setShownThisSession = (value) => {
      const normalized = Math.max(0, value);
      try {
        window.sessionStorage.setItem(sessionShownStorageKey, String(normalized));
      } catch (e) {}
      const url = new URL(window.location.href);
      url.searchParams.set('shown', String(normalized));
      return url;
    };

    const updateMuteButton = () => {
      muteToggle.textContent = player.muted ? '🔇' : '🔊';
      muteToggle.title = player.muted ? 'Unmute' : 'Mute';
      muteToggle.setAttribute('aria-label', player.muted ? 'Unmute' : 'Mute');
    };

    const isLandscapePhone = () => {
      const isCoarse = window.matchMedia('(pointer: coarse)').matches;
      const isLandscape = window.matchMedia('(orientation: landscape)').matches;
      const isPhoneLike = Math.max(window.screen.width, window.screen.height) <= 1366;
      return isCoarse && isLandscape && isPhoneLike;
    };

    const tryEnterFullscreenForMobile = () => {
      if (!isLandscapePhone()) {
        return;
      }
      if (document.fullscreenElement) {
        return;
      }
      if (typeof player.requestFullscreen === 'function') {
        player.requestFullscreen().catch(() => {});
        return;
      }
      if (typeof player.webkitEnterFullscreen === 'function') {
        try {
          player.webkitEnterFullscreen();
        } catch (e) {}
      }
    };

    const escapeHtml = (value) => {
      return String(value ?? '').replace(/[&<>"']/g, (ch) => (
        { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]
      ));
    };

    const formatMetadataText = (data) => {
      const cameraName = [data.camera_make || '', data.camera_model || ''].join(' ').trim();
      const resolution = (data.video_width && data.video_height) ? `${data.video_width}x${data.video_height}` : '-';
      return [
        `asset_id: ${data.asset_id || '-'}`,
        `file_name: ${data.file_name || '-'}`,
        `is_favorite: ${data.is_favorite === '1' ? 'yes' : 'no'}`,
        `capture_date: ${data.capture_date || '-'}`,
        `camera: ${cameraName || '-'}`,
        `lens: ${data.camera_lens || '-'}`,
        `codec: ${data.video_codec || '-'}`,
        `fps: ${data.video_fps || '-'}`,
        `resolution: ${resolution}`,
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

    const renderMetadataPanel = (data) => {
      const textBlock = `<div class="metadata-pre">${escapeHtml(formatMetadataText(data))}</div>`;
      if (data.show_qr_code === '1' && data.qr_image_url && data.immich_asset_url) {
        return `${textBlock}<div class="meta-qr"><img src="${escapeHtml(data.qr_image_url)}" alt="QR code to open asset in Immich"><a href="${escapeHtml(data.immich_asset_url)}" target="_blank" rel="noopener noreferrer">Open in Immich</a></div>`;
      }
      return textBlock;
    };

    const formatStats = (data) => {
      const shownThisSession = String(getShownThisSession());
      let topCameras = [];
      let topCodecs = [];
      try {
        topCameras = JSON.parse(data.db_top_cameras || '[]');
      } catch (e) {
        topCameras = [];
      }
      try {
        topCodecs = JSON.parse(data.db_top_codecs || '[]');
      } catch (e) {
        topCodecs = [];
      }
      const topCameraLines = topCameras.map((row, i) => `${i + 1}. ${(row.camera_name || 'Unknown')} (${row.cnt || 0})`);
      const topCodecLines = topCodecs.map((row, i) => `${i + 1}. ${(row.codec_name || 'Unknown')} (${row.cnt || 0})`);
      const lines = [
        `use_sqlite: ${data.use_sqlite || '-'}`,
        `only_favorites: ${data.only_favorites || '-'}`,
        `min_duration: ${data.min_duration || '-'}s`,
        `total_videos: ${data.db_total_videos || '-'}`,
        `matching_duration: ${data.db_qualifying_videos || '-'}`,
        `favorites: ${data.db_favorite_videos || '-'}`,
        `shown_this_session: ${shownThisSession}`,
        `shown_total: ${data.db_total_watched || '-'}`,
        `last_sync_at: ${data.last_sync_at || '-'}`,
        'top_5_cameras:'
      ];
      if (topCameraLines.length > 0) {
        lines.push(...topCameraLines);
      } else {
        lines.push('-');
      }
      lines.push('top_5_codecs:');
      if (topCodecLines.length > 0) {
        lines.push(...topCodecLines);
      } else {
        lines.push('-');
      }
      return lines.join('\n');
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

    const setAdminVisible = (visible) => {
      adminPanel.classList.toggle('visible', visible);
    };

    const clearNextTimer = () => {
      if (nextTimerInterval !== null) {
        window.clearInterval(nextTimerInterval);
        nextTimerInterval = null;
      }
      if (nextTimerTimeout !== null) {
        window.clearTimeout(nextTimerTimeout);
        nextTimerTimeout = null;
      }
      nextCountdown.classList.remove('visible');
      nextCountdown.textContent = '';
    };

    const buildApiUrl = () => {
      const currentUrl = new URL(window.location.href);
      const apiUrl = new URL('/api.php', window.location.origin);
      apiUrl.searchParams.set('next', '1');
      if (currentUrl.searchParams.get('favOnly') === '1') {
        apiUrl.searchParams.set('favOnly', '1');
      }
      if (currentUrl.searchParams.get('sync') === '1') {
        apiUrl.searchParams.set('sync', '1');
      }
      apiUrl.searchParams.set('t', String(Date.now()));
      return apiUrl;
    };

    const clearOneShotParamsFromUrl = () => {
      const url = new URL(window.location.href);
      let changed = false;
      if (url.searchParams.has('sync')) {
        url.searchParams.delete('sync');
        changed = true;
      }
      if (url.searchParams.has('skip')) {
        url.searchParams.delete('skip');
        changed = true;
      }
      if (changed) {
        window.history.replaceState(null, '', url.toString());
      }
    };

    const showLoadError = (message) => {
      loadError.textContent = message;
      loadError.classList.add('visible');
    };

    const hideLoadError = () => {
      loadError.textContent = '';
      loadError.classList.remove('visible');
    };

    const applyPayload = (data) => {
      metadata = data.metadata || {};
      stats = data.stats || {};
      isFavorite = metadata.is_favorite === '1';
      onlyFavoritesMode = stats.only_favorites === 'true';

      metadataPanel.innerHTML = renderMetadataPanel(metadata);
      statsPanel.textContent = formatStats(stats);
      adminLastSync.textContent = `Last synced: ${stats.last_sync_at || '-'}`;

      const captionText = String(data.caption_text || '');
      videoCaption.textContent = captionText;
      videoCaption.classList.toggle('hidden', captionText === '');

      updateFavoriteButton();
      updateFavoriteFilterButton();

      if (typeof data.video_src === 'string' && data.video_src !== '') {
        player.src = data.video_src;
      }
    };

    const loadCurrentVideo = async () => {
      const response = await fetch(buildApiUrl().toString(), { cache: 'no-store' });
      const body = await response.json().catch(() => ({}));
      if (!response.ok || body.ok !== true) {
        throw new Error(body.error || `HTTP ${response.status}`);
      }

      applyPayload(body);
      clearOneShotParamsFromUrl();
      hideLoadError();

      player.load();
      player.play().catch(() => {
        if (!preferredMuted) {
          suppressMutePersist = true;
          player.muted = true;
          suppressMutePersist = false;
          updateMuteButton();
          player.play().catch(() => {});
        }
      });
    };

    const startNextTimer = () => {
      clearNextTimer();
      const durationMs = 3000;
      const deadline = Date.now() + durationMs;
      const update = () => {
        const remainingMs = Math.max(0, deadline - Date.now());
        const remainingSeconds = Math.ceil(remainingMs / 1000);
        nextCountdown.textContent = `Next video in ${remainingSeconds}s`;
        nextCountdown.classList.add('visible');
      };
      update();
      nextTimerInterval = window.setInterval(update, 100);
      nextTimerTimeout = window.setTimeout(() => {
        clearNextTimer();
        const currentShown = getShownThisSession();
        const nextUrl = setShownThisSession(currentShown + 1);
        const encodedId = encodeURIComponent(metadata.asset_id || '');
        fetch(`/watch.php?id=${encodedId}`, { method: 'POST', keepalive: true }).catch(() => {});
        window.location.href = nextUrl.toString();
      }, durationMs);
    };

    muteToggle.addEventListener('click', () => {
      player.muted = !player.muted;
      saveMutedPreference(player.muted);
      updateMuteButton();
    });

    backBtn.addEventListener('click', () => {
      if (window.history.length > 1) {
        window.history.back();
      } else {
        window.location.reload();
      }
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
        metadataPanel.innerHTML = renderMetadataPanel(metadata);
        updateFavoriteButton();
      } catch (err) {
        console.error('Favorite toggle failed', err);
      } finally {
        favoriteToggle.disabled = false;
      }
    });

    adminTrigger.addEventListener('click', () => {
      setAdminVisible(!adminPanel.classList.contains('visible'));
    });

    adminCloseBtn.addEventListener('click', () => {
      setAdminVisible(false);
    });

    syncNowBtn.addEventListener('click', () => {
      const url = new URL(window.location.href);
      url.searchParams.set('sync', '1');
      window.location.href = url.toString();
    });

    const isTypingTarget = (target) => {
      if (!(target instanceof Element)) {
        return false;
      }
      if (target.isContentEditable) {
        return true;
      }
      const tag = target.tagName;
      return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT';
    };

    window.addEventListener('keydown', (event) => {
      if (isTypingTarget(event.target)) {
        return;
      }

      const key = (event.key || '').toLowerCase();
      if (event.key === 'ArrowLeft') {
        event.preventDefault();
        backBtn.click();
        return;
      }
      if (event.key === 'ArrowRight') {
        event.preventDefault();
        skipBtn.click();
        return;
      }
      if (key === 'f') {
        event.preventDefault();
        favoriteToggle.click();
        return;
      }
      if (key === 's') {
        event.preventDefault();
        statsToggle.click();
        return;
      }
      if (key === 'i') {
        event.preventDefault();
        metaToggle.click();
        return;
      }
      if (event.code === 'Space' || event.key === ' ') {
        event.preventDefault();
        if (player.paused) {
          player.play().catch(() => {});
        } else {
          player.pause();
        }
      }
    });

    metadataPanel.classList.toggle('visible', readMetadataPreference());

    // Keep storage synchronized with URL-based session counter.
    setShownThisSession(getShownThisSession());

    player.addEventListener('volumechange', () => {
      if (!suppressMutePersist) {
        saveMutedPreference(player.muted);
      }
      updateMuteButton();
    });

    player.addEventListener('play', clearNextTimer);
    player.addEventListener('seeking', clearNextTimer);
    player.addEventListener('ended', () => {
      startNextTimer();
    });

    player.muted = preferredMuted;
    updateMuteButton();

    const markUserInteracted = () => {
      userInteracted = true;
      if (!preferredMuted && player.muted) {
        suppressMutePersist = true;
        player.muted = false;
        suppressMutePersist = false;
        updateMuteButton();
      }
      tryEnterFullscreenForMobile();
    };

    window.addEventListener('pointerdown', markUserInteracted, { passive: true });
    window.addEventListener('touchstart', markUserInteracted, { passive: true });
    window.addEventListener('click', markUserInteracted, { passive: true });
    window.addEventListener('resize', () => {
      if (userInteracted) {
        tryEnterFullscreenForMobile();
      }
    });
    window.addEventListener('orientationchange', () => {
      if (userInteracted) {
        tryEnterFullscreenForMobile();
      }
    });

    loadCurrentVideo().catch((err) => {
      console.error('Failed to load video payload', err);
      showLoadError(`Could not load a video.\n${String(err.message || err)}`);
    });
  </script>
</body>
</html>
