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
];
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Immich Video Channel</title>
  <style>
    html, body {
      margin: 0;
      width: 100%;
      height: 100%;
      background: #000;
      overflow: hidden;
      font-family: system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif;
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
      left: 12px;
      right: 12px;
      bottom: 12px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 10px;
      z-index: 20;
      pointer-events: none;
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

    .qr-panel {
      position: fixed;
      top: 12px;
      right: 12px;
      z-index: 25;
      width: 192px;
      color: #fff;
      background: rgba(0, 0, 0, 0.7);
      border: 1px solid rgba(255, 255, 255, 0.25);
      border-radius: 8px;
      padding: 8px;
      display: none;
      backdrop-filter: blur(2px);
    }

    .qr-title {
      font-size: 12px;
      margin: 0 0 6px 0;
      opacity: 0.9;
    }

    #qrCode {
      width: 160px;
      height: 160px;
      margin: 0 auto;
      background: #fff;
    }

    .qr-link {
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
    }

    .btn {
      border: 1px solid rgba(255, 255, 255, 0.35);
      color: #fff;
      background: rgba(0, 0, 0, 0.6);
      border-radius: 6px;
      padding: 6px 10px;
      font-size: 12px;
      cursor: pointer;
    }

    #fallback {
      position: fixed;
      top: 12px;
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
  </style>
</head>
<body>
  <div id="stage">
    <video id="v0" class="player active" autoplay muted playsinline preload="auto"></video>
    <video id="v1" class="player" autoplay muted playsinline preload="auto"></video>
  </div>

  <div id="fallback"></div>
  <div id="qrPanel" class="qr-panel">
    <p class="qr-title">Open in Immich</p>
    <div id="qrCode"></div>
    <a id="qrLink" class="qr-link" href="#" target="_blank" rel="noopener noreferrer"></a>
  </div>

  <div class="hud">
    <div id="title" class="chip">Loading…</div>
    <div class="controls">
      <button id="skipBtn" class="btn" type="button">Skip</button>
      <button id="muteBtn" class="btn" type="button">Unmute</button>
      <button id="fullscreenBtn" class="btn" type="button">Fullscreen</button>
      <div id="status" class="chip"></div>
    </div>
  </div>

  <script src="/qrcode.min.js"></script>
  <script>
    const settings = <?= json_encode($settings, JSON_UNESCAPED_SLASHES) ?>;

    const players = [
      document.getElementById('v0'),
      document.getElementById('v1'),
    ];
    const titleEl = document.getElementById('title');
    const statusEl = document.getElementById('status');
    const fallbackEl = document.getElementById('fallback');
    const qrPanelEl = document.getElementById('qrPanel');
    const qrCodeEl = document.getElementById('qrCode');
    const qrLinkEl = document.getElementById('qrLink');
    const skipBtn = document.getElementById('skipBtn');
    const muteBtn = document.getElementById('muteBtn');
    const fullscreenBtn = document.getElementById('fullscreenBtn');

    const muteStorageKey = 'immichChannelMuted';
    let activeIndex = 0;
    let queue = [];
    let inflightFetches = 0;
    let transitionInProgress = false;
    let preparingNext = false;
    let nextPreparedId = '';
    let currentItem = null;
    let qrInstance = null;

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
      muteBtn.textContent = muted ? 'Unmute' : 'Mute';
    };

    const isFullscreen = () => {
      return Boolean(
        document.fullscreenElement ||
        document.webkitFullscreenElement
      );
    };

    const updateFullscreenButton = () => {
      fullscreenBtn.textContent = isFullscreen() ? 'Exit Fullscreen' : 'Fullscreen';
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

    const apiNextUrl = () => {
      const url = new URL('/api.php', window.location.origin);
      url.searchParams.set('next', '1');
      const current = new URL(window.location.href);
      if (current.searchParams.get('favOnly') === '1') {
        url.searchParams.set('favOnly', '1');
      }
      url.searchParams.set('t', String(Date.now()));
      return url.toString();
    };

    const normalizeItem = (payload) => {
      return {
        id: String(payload.asset_id || payload.id || ''),
        title: String(payload.metadata?.file_name || 'Untitled'),
        duration: Number(payload.metadata?.duration || 0),
        src: String(payload.video_src || ''),
        immichAssetUrl: String(payload.metadata?.immich_asset_url || ''),
        showQrCode: String(payload.metadata?.show_qr_code || '0') === '1',
      };
    };

    const clearQrCode = () => {
      while (qrCodeEl.firstChild) {
        qrCodeEl.removeChild(qrCodeEl.firstChild);
      }
    };

    const renderQrCode = (item) => {
      if (!item.showQrCode || !item.immichAssetUrl) {
        qrPanelEl.style.display = 'none';
        clearQrCode();
        qrLinkEl.textContent = '';
        qrLinkEl.removeAttribute('href');
        return;
      }

      if (typeof QRCode === 'undefined') {
        qrPanelEl.style.display = 'none';
        return;
      }

      qrPanelEl.style.display = 'block';
      qrLinkEl.href = item.immichAssetUrl;
      qrLinkEl.textContent = item.immichAssetUrl;

      if (!qrInstance) {
        clearQrCode();
        qrInstance = new QRCode(qrCodeEl, {
          text: item.immichAssetUrl,
          width: 160,
          height: 160,
          colorDark: '#000000',
          colorLight: '#ffffff',
          correctLevel: QRCode.CorrectLevel.M,
        });
      } else if (typeof qrInstance.makeCode === 'function') {
        qrInstance.makeCode(item.immichAssetUrl);
      } else {
        clearQrCode();
        qrInstance = new QRCode(qrCodeEl, item.immichAssetUrl);
      }
    };

    const fetchNextItem = async () => {
      const resp = await fetch(apiNextUrl(), { cache: 'no-store' });
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

    const fillQueue = async () => {
      while ((queue.length + inflightFetches) < settings.queueTargetSize) {
        inflightFetches++;
        fetchNextItem()
          .then((item) => {
            if (currentItem && item.id === currentItem.id) {
              return;
            }
            if (queue.some((q) => q.id === item.id)) {
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
      await active.play().catch((err) => {
        console.warn('Autoplay failed, retrying muted', err);
        active.muted = true;
        players[0].muted = true;
        players[1].muted = true;
        saveMutedPreference(true);
        updateMuteButton();
        return active.play();
      });
      currentItem = item;
      titleEl.textContent = item.title;
      renderQrCode(item);
      updateStatus();
    };

    const swapPlayers = () => {
      const outgoingIdx = activeIndex;
      activeIndex = 1 - activeIndex;
      clearPlayer(players[outgoingIdx]);
    };

    const transitionToNext = async (reason) => {
      if (transitionInProgress) {
        return;
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

        const nextItem = queue.shift();
        updateStatus();

        await prepareHiddenWith(nextItem);

        const outgoing = activePlayer();
        const incoming = hiddenPlayer();

        incoming.muted = outgoing.muted;
        incoming.classList.add('active');
        incoming.style.transitionDuration = '0ms';
        incoming.style.opacity = settings.crossfadeEnabled ? '0' : '1';

        await incoming.play();

        if (settings.crossfadeEnabled && settings.crossfadeDurationMs > 0) {
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
        titleEl.textContent = nextItem.title;
        renderQrCode(nextItem);
        nextPreparedId = '';
        setFallback('');

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
      const mode = settings.crossfadeEnabled ? `fade ${settings.crossfadeDurationMs}ms` : 'cut';
      statusEl.textContent = `Queue ${queue.length}/${settings.queueTargetSize} · ${mode}`;
    };

    const onActiveTimeUpdate = () => {
      const video = activePlayer();
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
            transitionToNext('active_error');
          }
        });
      });
    };

    skipBtn.addEventListener('click', () => {
      transitionToNext('manual_skip');
    });

    muteBtn.addEventListener('click', () => {
      const nextMuted = !activePlayer().muted;
      players[0].muted = nextMuted;
      players[1].muted = nextMuted;
      saveMutedPreference(nextMuted);
      updateMuteButton();
    });

    fullscreenBtn.addEventListener('click', () => {
      toggleFullscreen();
    });

    window.addEventListener('keydown', (event) => {
      if (event.code === 'Space') {
        event.preventDefault();
        const v = activePlayer();
        if (v.paused) v.play().catch(() => {});
        else v.pause();
      }
      if (event.key === 'ArrowRight') {
        event.preventDefault();
        transitionToNext('arrow_skip');
      }
    });

    const bootstrap = async () => {
      bindPlayerEvents();
      updateMuteButton();
      updateFullscreenButton();
      updateStatus();

      document.addEventListener('fullscreenchange', updateFullscreenButton);
      document.addEventListener('webkitfullscreenchange', updateFullscreenButton);

      try {
        const first = await fetchNextItem();
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

      // If startup failed, retry until recovered.
      window.setInterval(() => {
        if (!currentItem && !transitionInProgress) {
          fetchNextItem()
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
