package uk.co.bananasystems.homevideochannel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class ChannelUiState(
    val config: AppConfig = AppConfig(),
    val currentItem: VideoCandidate? = null,
    val statusText: String = "",
    val debugText: String = "",
    val fallbackMessage: String = "",
    val setupVisible: Boolean = false,
    val infoVisible: Boolean = false,
    val isBuffering: Boolean = false,
    val isSyncing: Boolean = false,
    val currentIsFavorite: Boolean = false,
    val canHideToAlbum: Boolean = false,
    val title: String = "Loading...",
    val captionText: String = "",
    val dateLocationText: String = "",
    val infoFields: List<VideoInfoField> = emptyList(),
    val stats: LibraryStats = LibraryStats()
)

class ChannelViewModel(application: Application) : AndroidViewModel(application) {
    private val configRepository = ConfigRepository(application)
    private val apiClient = ImmichApiClient()
    private val store = SQLiteVideoStore(application)

    private val _uiState = MutableStateFlow(ChannelUiState(config = configRepository.load()))
    val uiState: StateFlow<ChannelUiState> = _uiState.asStateFlow()

    val player: ExoPlayer = ExoPlayer.Builder(application).build().apply {
        repeatMode = Player.REPEAT_MODE_OFF
        playWhenReady = true
        addListener(
            object : androidx.media3.common.Player.Listener {
                override fun onIsLoadingChanged(isLoading: Boolean) {
                    _uiState.value = _uiState.value.copy(isBuffering = isLoading)
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
                    if (playbackState == androidx.media3.common.Player.STATE_ENDED) {
                        playNext("ended")
                    }
                }
            }
        )
    }

    private var hiddenAlbumId: String = ""

    init {
        if (_uiState.value.config.isConfigured) {
            start()
        } else {
            _uiState.value = _uiState.value.copy(setupVisible = true)
        }
    }

    fun start() {
        if (!_uiState.value.config.isConfigured) return
        refreshStats()
        viewModelScope.launch {
            if (_uiState.value.config.syncOnStartup && _uiState.value.config.useSQLiteCache) {
                forceSync()
            }
            hiddenAlbumId = withContext(Dispatchers.IO) {
                apiClient.resolveHiddenAlbumAccess(_uiState.value.config).albumId
            }
            _uiState.value = _uiState.value.copy(canHideToAlbum = hiddenAlbumId.isNotBlank())
            ensurePlayback()
        }
    }

    fun saveConfig(config: AppConfig) {
        configRepository.save(config)
        _uiState.value = _uiState.value.copy(config = config, setupVisible = false, fallbackMessage = "")
        start()
    }

    fun showSetup() {
        _uiState.value = _uiState.value.copy(setupVisible = true)
    }

    fun hideSetup() {
        _uiState.value = _uiState.value.copy(setupVisible = false)
    }

    fun toggleInfo() {
        _uiState.value = _uiState.value.copy(infoVisible = !_uiState.value.infoVisible)
    }

    fun togglePlayPause() {
        if (player.isPlaying) player.pause() else player.play()
        _uiState.value = _uiState.value.copy(statusText = if (player.isPlaying) "playing" else "paused")
    }

    fun skip() {
        playNext("skip")
    }

    fun toggleFavorite() {
        val current = _uiState.value.currentItem ?: return
        val target = !current.isFavorite
        viewModelScope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    apiClient.updateFavorite(current.id, target, _uiState.value.config)
                    store.setFavorite(current.id, target)
                }
            }.onSuccess {
                val updated = current.copy(isFavorite = target)
                _uiState.value = _uiState.value.copy(
                    currentItem = updated,
                    currentIsFavorite = target,
                    statusText = if (target) "favorited" else "unfavorited"
                )
            }.onFailure {
                _uiState.value = _uiState.value.copy(fallbackMessage = it.message ?: "Favorite update failed")
            }
        }
    }

    fun hideCurrentVideo() {
        val current = _uiState.value.currentItem ?: return
        if (hiddenAlbumId.isBlank()) return
        viewModelScope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    apiClient.hideAsset(current.id, _uiState.value.config, hiddenAlbumId)
                    store.setHidden(current.id, true)
                }
            }.onSuccess {
                _uiState.value = _uiState.value.copy(statusText = "hidden")
                playNext("hidden")
            }.onFailure {
                _uiState.value = _uiState.value.copy(fallbackMessage = it.message ?: "Hide failed")
            }
        }
    }

    fun forceSync() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isSyncing = true, statusText = "syncing")
            runCatching {
                withContext(Dispatchers.IO) {
                    var page = 1
                    var total = 0
                    while (page <= _uiState.value.config.syncMaxPages) {
                        val batch = apiClient.fetchMetadataPage(_uiState.value.config, page, _uiState.value.config.syncPageSize)
                        if (batch.isEmpty()) break
                        total += store.upsert(batch)
                        if (batch.size < _uiState.value.config.syncPageSize) break
                        page += 1
                    }
                    total
                }
            }.onSuccess { rows ->
                _uiState.value = _uiState.value.copy(isSyncing = false, statusText = "synced $rows rows")
                refreshStats()
            }.onFailure {
                _uiState.value = _uiState.value.copy(isSyncing = false, fallbackMessage = it.message ?: "Sync failed")
            }
        }
    }

    fun resetPlaybackProgress() {
        viewModelScope.launch(Dispatchers.IO) {
            store.clearSequentialLastAssetId()
        }
        _uiState.value = _uiState.value.copy(statusText = "playback reset")
    }

    fun refreshStats() {
        viewModelScope.launch {
            val stats = withContext(Dispatchers.IO) { store.stats() }
            _uiState.value = _uiState.value.copy(stats = stats)
        }
    }

    private fun ensurePlayback() {
        if (_uiState.value.currentItem == null) {
            playNext("startup")
        }
    }

    private fun playNext(reason: String) {
        viewModelScope.launch {
            val config = _uiState.value.config
            val candidate = withContext(Dispatchers.IO) {
                val cachedCandidate = if (config.useSQLiteCache) {
                    val sequential = when (config.playbackOrder) {
                        "sequential_oldest" -> store.sequentialCandidate(config.minDuration, config.onlyFavorites, newestFirst = false, afterAssetId = store.getSequentialLastAssetId())
                        "sequential_newest" -> store.sequentialCandidate(config.minDuration, config.onlyFavorites, newestFirst = true, afterAssetId = store.getSequentialLastAssetId())
                        else -> null
                    }
                    sequential ?: store.randomCandidate(config.minDuration, config.onlyFavorites)
                } else null

                cachedCandidate ?: run {
                    apiClient.fetchRandomBatch(config, config.randomBatchSize)
                        .firstOrNull { it.duration >= config.minDuration && (!config.onlyFavorites || it.isFavorite) }
                        ?.toCandidate()
                }
            }

            if (candidate == null) {
                _uiState.value = _uiState.value.copy(
                    fallbackMessage = "No eligible video found",
                    statusText = "idle"
                )
                return@launch
            }

            playCandidate(candidate, reason)
        }
    }

    private suspend fun playCandidate(candidate: VideoCandidate, reason: String) {
        withContext(Dispatchers.IO) {
            if (_uiState.value.config.useSQLiteCache) {
                store.setSequentialLastAssetId(candidate.id)
                store.incrementWatchCount(candidate.id)
                store.recordWatchEvent(candidate.id, Instant.now().toString())
            }
        }

        val headers = mapOf(
            "x-api-key" to _uiState.value.config.apiKey,
            "Accept" to "*/*"
        )
        val mediaSourceFactory = DefaultMediaSourceFactory(
            DefaultHttpDataSource.Factory().setDefaultRequestProperties(headers)
        )
        val mediaItem = MediaItem.fromUri(apiClient.playbackUrl(candidate, _uiState.value.config))
        player.setMediaSource(mediaSourceFactory.createMediaSource(mediaItem))
        player.prepare()
        player.play()

        _uiState.value = _uiState.value.copy(
            currentItem = candidate,
            currentIsFavorite = candidate.isFavorite,
            fallbackMessage = "",
            title = candidate.title.ifBlank { "Untitled video" },
            captionText = buildCaption(candidate),
            dateLocationText = buildDateLocation(candidate),
            infoFields = buildInfoFields(candidate),
            statusText = "playing ($reason)",
            debugText = "${candidate.videoCodec.ifBlank { "-" }} ${candidate.fileType.ifBlank { "-" }}"
        )
        refreshStats()
    }

    private fun buildCaption(candidate: VideoCandidate): String {
        val camera = listOf(candidate.cameraMake, candidate.cameraModel).filter { it.isNotBlank() }.joinToString(" ")
        return listOf(camera, candidate.lensModel, candidate.fNumber, candidate.focalLength)
            .filter { it.isNotBlank() }
            .joinToString("  ·  ")
    }

    private fun buildDateLocation(candidate: VideoCandidate): String {
        return listOf(candidate.captureDate.take(10), listOf(candidate.city, candidate.country).filter { it.isNotBlank() }.joinToString(", "))
            .filter { it.isNotBlank() }
            .joinToString("  ·  ")
    }

    private fun buildInfoFields(candidate: VideoCandidate): List<VideoInfoField> {
        return listOf(
            VideoInfoField("title", "Title", candidate.title),
            VideoInfoField("duration", "Duration", "${candidate.duration.toInt()}s"),
            VideoInfoField("date", "Capture date", candidate.captureDate),
            VideoInfoField("location", "Location", listOf(candidate.city, candidate.country).filter { it.isNotBlank() }.joinToString(", ")),
            VideoInfoField("camera", "Camera", listOf(candidate.cameraMake, candidate.cameraModel).filter { it.isNotBlank() }.joinToString(" ")),
            VideoInfoField("lens", "Lens", candidate.lensModel),
            VideoInfoField("codec", "Codec", candidate.videoCodec),
            VideoInfoField("type", "File type", candidate.fileType)
        ).filter { it.value.isNotBlank() }
    }

    override fun onCleared() {
        player.release()
        super.onCleared()
    }

    private fun ImmichAssetRecord.toCandidate(): VideoCandidate {
        return VideoCandidate(
            id = id,
            title = title,
            duration = duration,
            isFavorite = isFavorite,
            isHidden = false,
            timesWatched = 0,
            captureDate = captureDate,
            city = city,
            country = country,
            cameraMake = cameraMake,
            cameraModel = cameraModel,
            lensModel = lensModel,
            fNumber = fNumber,
            focalLength = focalLength,
            iso = iso,
            exposureTime = exposureTime,
            latitude = latitude,
            longitude = longitude,
            videoCodec = videoCodec,
            fileType = fileType
        )
    }
}
