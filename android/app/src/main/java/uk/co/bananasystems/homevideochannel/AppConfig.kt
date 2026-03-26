package uk.co.bananasystems.homevideochannel

data class AppConfig(
    val immichUrl: String = "",
    val apiKey: String = "",
    val minDuration: Double = 10.0,
    val randomBatchSize: Int = 20,
    val onlyFavorites: Boolean = false,
    val debug: Boolean = false,
    val crossfadeEnabled: Boolean = true,
    val crossfadeDurationMs: Int = 450,
    val preloadSecondsBeforeEnd: Double = 4.0,
    val queueTargetSize: Int = 2,
    val playbackOrder: String = "random",
    val playbackQuality: String = "auto",
    val showDateLocationOverlay: Boolean = true,
    val useSQLiteCache: Boolean = true,
    val syncOnStartup: Boolean = true,
    val syncPageSize: Int = 200,
    val syncMaxPages: Int = 200
) {
    val isConfigured: Boolean
        get() = immichUrl.trim().isNotEmpty() && apiKey.trim().isNotEmpty()

    val normalizedImmichBaseUrl: String
        get() = immichUrl.trim().trimEnd('/')

    val playbackPeakBitrate: Long
        get() = when (playbackQuality) {
            "low" -> 2_000_000L
            "medium" -> 5_000_000L
            "high" -> 10_000_000L
            else -> 0L
        }
}
