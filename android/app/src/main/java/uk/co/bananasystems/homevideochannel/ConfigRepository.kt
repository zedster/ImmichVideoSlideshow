package uk.co.bananasystems.homevideochannel

import android.content.Context
import org.json.JSONObject

class ConfigRepository(context: Context) {
    private val prefs = context.getSharedPreferences("home_video_channel", Context.MODE_PRIVATE)

    fun load(): AppConfig {
        val raw = prefs.getString("config_json", null) ?: return AppConfig()
        return runCatching {
            val json = JSONObject(raw)
            AppConfig(
                immichUrl = json.optString("immichUrl"),
                apiKey = json.optString("apiKey"),
                minDuration = json.optDouble("minDuration", 10.0),
                randomBatchSize = json.optInt("randomBatchSize", 20),
                onlyFavorites = json.optBoolean("onlyFavorites", false),
                debug = json.optBoolean("debug", false),
                crossfadeEnabled = json.optBoolean("crossfadeEnabled", true),
                crossfadeDurationMs = json.optInt("crossfadeDurationMs", 450),
                preloadSecondsBeforeEnd = json.optDouble("preloadSecondsBeforeEnd", 4.0),
                queueTargetSize = json.optInt("queueTargetSize", 2),
                playbackOrder = json.optString("playbackOrder", "random"),
                playbackQuality = json.optString("playbackQuality", "auto"),
                showDateLocationOverlay = json.optBoolean("showDateLocationOverlay", true),
                useSQLiteCache = json.optBoolean("useSQLiteCache", true),
                syncOnStartup = json.optBoolean("syncOnStartup", true),
                syncPageSize = json.optInt("syncPageSize", 200),
                syncMaxPages = json.optInt("syncMaxPages", 200)
            )
        }.getOrElse { AppConfig() }
    }

    fun save(config: AppConfig) {
        val json = JSONObject()
            .put("immichUrl", config.immichUrl)
            .put("apiKey", config.apiKey)
            .put("minDuration", config.minDuration)
            .put("randomBatchSize", config.randomBatchSize)
            .put("onlyFavorites", config.onlyFavorites)
            .put("debug", config.debug)
            .put("crossfadeEnabled", config.crossfadeEnabled)
            .put("crossfadeDurationMs", config.crossfadeDurationMs)
            .put("preloadSecondsBeforeEnd", config.preloadSecondsBeforeEnd)
            .put("queueTargetSize", config.queueTargetSize)
            .put("playbackOrder", config.playbackOrder)
            .put("playbackQuality", config.playbackQuality)
            .put("showDateLocationOverlay", config.showDateLocationOverlay)
            .put("useSQLiteCache", config.useSQLiteCache)
            .put("syncOnStartup", config.syncOnStartup)
            .put("syncPageSize", config.syncPageSize)
            .put("syncMaxPages", config.syncMaxPages)
        prefs.edit().putString("config_json", json.toString()).apply()
    }
}
