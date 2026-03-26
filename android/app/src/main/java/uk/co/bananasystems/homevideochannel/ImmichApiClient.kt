package uk.co.bananasystems.homevideochannel

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

class ImmichApiClient(
    private val httpClient: OkHttpClient = OkHttpClient()
) {
    fun testConnection(config: AppConfig) {
        request(
            url = "${config.normalizedImmichBaseUrl}/api/albums",
            apiKey = config.apiKey,
            method = "GET"
        )
    }

    fun fetchRandomBatch(config: AppConfig, size: Int): List<ImmichAssetRecord> {
        val payload = JSONObject()
            .put("type", "VIDEO")
            .put("size", size.coerceIn(1, 200))
            .put("random", true)
            .put("withExif", true)
            .put("withPeople", true)
        return searchMetadata(config, payload)
    }

    fun fetchMetadataPage(config: AppConfig, page: Int, size: Int): List<ImmichAssetRecord> {
        val payload = JSONObject()
            .put("type", "VIDEO")
            .put("size", size.coerceIn(1, 1000))
            .put("page", page)
            .put("withExif", true)
            .put("withPeople", true)
        return searchMetadata(config, payload)
    }

    fun resolveHiddenAlbumAccess(config: AppConfig, albumName: String = "Hidden"): HiddenAlbumAccess {
        return runCatching {
            val albumId = getOrCreateAlbumId(config, albumName)
            HiddenAlbumAccess(true, albumId, "hidden album ready ($albumName)")
        }.getOrElse { error ->
            HiddenAlbumAccess(false, "", "hidden album unavailable (${error.message ?: "error"})")
        }
    }

    fun updateFavorite(assetId: String, isFavorite: Boolean, config: AppConfig) {
        val body = JSONObject().put("isFavorite", isFavorite)
        request(
            url = "${config.normalizedImmichBaseUrl}/api/assets/$assetId",
            apiKey = config.apiKey,
            method = "PUT",
            jsonBody = body
        )
    }

    fun hideAsset(assetId: String, config: AppConfig, hiddenAlbumId: String) {
        request(
            url = "${config.normalizedImmichBaseUrl}/api/albums/$hiddenAlbumId/assets",
            apiKey = config.apiKey,
            method = "PUT",
            jsonBody = JSONObject().put("ids", JSONArray().put(assetId))
        )
        request(
            url = "${config.normalizedImmichBaseUrl}/api/assets",
            apiKey = config.apiKey,
            method = "PUT",
            jsonBody = JSONObject()
                .put("ids", JSONArray().put(assetId))
                .put("isArchived", true)
        )
    }

    fun playbackUrl(candidate: VideoCandidate, config: AppConfig): String {
        return "${config.normalizedImmichBaseUrl}/api/assets/${candidate.id}/video/playback"
    }

    private fun searchMetadata(config: AppConfig, payload: JSONObject): List<ImmichAssetRecord> {
        val response = request(
            url = "${config.normalizedImmichBaseUrl}/api/search/metadata",
            apiKey = config.apiKey,
            method = "POST",
            jsonBody = payload
        )
        val json = JSONObject(response)
        val items = json.optJSONObject("assets")?.optJSONArray("items") ?: JSONArray()
        return buildList {
            for (index in 0 until items.length()) {
                add(parseRecord(items.getJSONObject(index)))
            }
        }
    }

    private fun parseRecord(json: JSONObject): ImmichAssetRecord {
        val exif = json.optJSONObject("exifInfo") ?: JSONObject()
        return ImmichAssetRecord(
            id = json.optString("id"),
            title = json.optString("originalFileName"),
            fileType = json.optString("originalMimeType"),
            videoCodec = json.optString("encodedVideoCodec"),
            duration = parseDuration(json.opt("duration")),
            isFavorite = json.optBoolean("isFavorite", false),
            captureDate = firstNonBlank(
                exif.optString("dateTimeOriginal"),
                exif.optString("dateTime"),
                json.optString("fileCreatedAt"),
                json.optString("localDateTime"),
                json.optString("createdAt")
            ),
            city = exif.optString("city"),
            country = exif.optString("country"),
            cameraMake = exif.optString("make"),
            cameraModel = exif.optString("model"),
            lensModel = nestedValue(exif, "lensModel"),
            fNumber = nestedValue(exif, "fNumber"),
            focalLength = nestedValue(exif, "focalLength"),
            iso = nestedValue(exif, "iso"),
            exposureTime = nestedValue(exif, "exposureTime"),
            latitude = nestedValue(exif, "latitude"),
            longitude = nestedValue(exif, "longitude")
        )
    }

    private fun nestedValue(json: JSONObject, key: String): String {
        val value = json.opt(key)
        return when (value) {
            is JSONObject -> value.optString("value")
            is String -> value
            else -> ""
        }
    }

    private fun parseDuration(value: Any?): Double {
        return when (value) {
            is Number -> value.toDouble()
            is String -> value.toDoubleOrNull() ?: 0.0
            is JSONObject -> value.optDouble("seconds", 0.0)
            else -> 0.0
        }
    }

    private fun firstNonBlank(vararg values: String): String {
        return values.firstOrNull { it.isNotBlank() } ?: ""
    }

    private fun getOrCreateAlbumId(config: AppConfig, albumName: String): String {
        val existing = findAlbumId(config, albumName)
        if (existing.isNotBlank()) return existing

        val response = request(
            url = "${config.normalizedImmichBaseUrl}/api/albums",
            apiKey = config.apiKey,
            method = "POST",
            jsonBody = JSONObject().put("albumName", albumName)
        )
        val created = JSONObject(response).optString("id")
        return if (created.isNotBlank()) created else findAlbumId(config, albumName)
    }

    private fun findAlbumId(config: AppConfig, albumName: String): String {
        val response = request(
            url = "${config.normalizedImmichBaseUrl}/api/albums",
            apiKey = config.apiKey,
            method = "GET"
        )
        val json = JSONArray(response)
        for (index in 0 until json.length()) {
            val item = json.getJSONObject(index)
            val id = item.optString("id")
            val name = item.optString("albumName").ifBlank { item.optString("name") }
            if (id.isNotBlank() && name.equals(albumName, ignoreCase = true)) {
                return id
            }
        }
        return ""
    }

    private fun request(
        url: String,
        apiKey: String,
        method: String,
        jsonBody: JSONObject? = null
    ): String {
        val builder = Request.Builder()
            .url(url)
            .addHeader("Accept", "application/json")
            .addHeader("x-api-key", apiKey)

        val body = jsonBody?.toString()?.toRequestBody("application/json".toMediaType())
        when (method) {
            "GET" -> builder.get()
            "POST" -> builder.post(body ?: ByteArray(0).toRequestBody())
            "PUT" -> builder.put(body ?: ByteArray(0).toRequestBody())
            "PATCH" -> builder.patch(body ?: ByteArray(0).toRequestBody())
            else -> error("Unsupported method $method")
        }

        httpClient.newCall(builder.build()).execute().use { response ->
            if (!response.isSuccessful) {
                error("Immich HTTP ${response.code}")
            }
            return response.body?.string().orEmpty()
        }
    }
}
