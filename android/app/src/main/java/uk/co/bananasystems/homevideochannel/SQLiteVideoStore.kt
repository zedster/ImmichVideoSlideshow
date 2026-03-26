package uk.co.bananasystems.homevideochannel

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class SQLiteVideoStore(context: Context) : SQLiteOpenHelper(context, "videos.sqlite", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE videos (
                asset_id TEXT PRIMARY KEY,
                title TEXT,
                file_type TEXT,
                video_codec TEXT,
                duration REAL NOT NULL,
                is_favorite INTEGER NOT NULL DEFAULT 0,
                is_hidden INTEGER NOT NULL DEFAULT 0,
                times_watched INTEGER NOT NULL DEFAULT 0,
                capture_date TEXT,
                city TEXT,
                country TEXT,
                camera_make TEXT,
                camera_model TEXT,
                lens_model TEXT,
                f_number TEXT,
                focal_length TEXT,
                iso TEXT,
                exposure_time TEXT,
                latitude TEXT,
                longitude TEXT
            )
            """.trimIndent()
        )
        db.execSQL("CREATE TABLE sync_state (key TEXT PRIMARY KEY, value TEXT)")
        db.execSQL("CREATE TABLE watch_events (id INTEGER PRIMARY KEY AUTOINCREMENT, asset_id TEXT NOT NULL, started_at TEXT NOT NULL)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    fun upsert(records: List<ImmichAssetRecord>): Int {
        val db = writableDatabase
        db.beginTransaction()
        return try {
            records.forEach { record ->
                val values = ContentValues().apply {
                    put("asset_id", record.id)
                    put("title", record.title)
                    put("file_type", record.fileType)
                    put("video_codec", record.videoCodec)
                    put("duration", record.duration)
                    put("is_favorite", if (record.isFavorite) 1 else 0)
                    put("capture_date", record.captureDate)
                    put("city", record.city)
                    put("country", record.country)
                    put("camera_make", record.cameraMake)
                    put("camera_model", record.cameraModel)
                    put("lens_model", record.lensModel)
                    put("f_number", record.fNumber)
                    put("focal_length", record.focalLength)
                    put("iso", record.iso)
                    put("exposure_time", record.exposureTime)
                    put("latitude", record.latitude)
                    put("longitude", record.longitude)
                }
                db.insertWithOnConflict("videos", null, values, SQLiteDatabase.CONFLICT_REPLACE)
            }
            db.setTransactionSuccessful()
            records.size
        } finally {
            db.endTransaction()
        }
    }

    fun randomCandidate(minDuration: Double, onlyFavorites: Boolean): VideoCandidate? {
        val selection = buildString {
            append("duration >= ? AND is_hidden = 0")
            if (onlyFavorites) append(" AND is_favorite = 1")
        }
        readableDatabase.query(
            "videos",
            null,
            selection,
            arrayOf(minDuration.toString()),
            null,
            null,
            "RANDOM()",
            "1"
        ).use { cursor ->
            return if (cursor.moveToFirst()) cursor.toCandidate() else null
        }
    }

    fun sequentialCandidate(minDuration: Double, onlyFavorites: Boolean, newestFirst: Boolean, afterAssetId: String?): VideoCandidate? {
        val selection = buildString {
            append("duration >= ? AND is_hidden = 0")
            if (onlyFavorites) append(" AND is_favorite = 1")
            if (!afterAssetId.isNullOrBlank()) append(" AND asset_id != ?")
        }
        val args = buildList {
            add(minDuration.toString())
            if (!afterAssetId.isNullOrBlank()) add(afterAssetId)
        }.toTypedArray()
        val order = if (newestFirst) "capture_date DESC, asset_id DESC" else "capture_date ASC, asset_id ASC"
        readableDatabase.query("videos", null, selection, args, null, null, order, "1").use { cursor ->
            return if (cursor.moveToFirst()) cursor.toCandidate() else null
        }
    }

    fun setFavorite(assetId: String, isFavorite: Boolean) {
        writableDatabase.update(
            "videos",
            ContentValues().apply { put("is_favorite", if (isFavorite) 1 else 0) },
            "asset_id = ?",
            arrayOf(assetId)
        )
    }

    fun setHidden(assetId: String, isHidden: Boolean) {
        writableDatabase.update(
            "videos",
            ContentValues().apply { put("is_hidden", if (isHidden) 1 else 0) },
            "asset_id = ?",
            arrayOf(assetId)
        )
    }

    fun incrementWatchCount(assetId: String) {
        writableDatabase.execSQL(
            "UPDATE videos SET times_watched = COALESCE(times_watched, 0) + 1 WHERE asset_id = ?",
            arrayOf(assetId)
        )
    }

    fun recordWatchEvent(assetId: String, startedAtIso: String) {
        writableDatabase.insert(
            "watch_events",
            null,
            ContentValues().apply {
                put("asset_id", assetId)
                put("started_at", startedAtIso)
            }
        )
    }

    fun setSyncState(key: String, value: String) {
        writableDatabase.insertWithOnConflict(
            "sync_state",
            null,
            ContentValues().apply {
                put("key", key)
                put("value", value)
            },
            SQLiteDatabase.CONFLICT_REPLACE
        )
    }

    fun getSyncState(key: String): String? {
        readableDatabase.query("sync_state", arrayOf("value"), "key = ?", arrayOf(key), null, null, null, "1").use { cursor ->
            return if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }

    fun clearSequentialLastAssetId() = setSyncState("playback.sequential.last_asset_id", "")
    fun setSequentialLastAssetId(assetId: String) = setSyncState("playback.sequential.last_asset_id", assetId)
    fun getSequentialLastAssetId(): String? = getSyncState("playback.sequential.last_asset_id")?.takeIf { it.isNotBlank() }

    fun stats(): LibraryStats {
        val db = readableDatabase
        val totalVideos = scalarInt(db, "SELECT COUNT(*) FROM videos")
        val totalWatchedPlays = scalarInt(db, "SELECT COALESCE(SUM(times_watched), 0) FROM videos")
        val favoritesCount = scalarInt(db, "SELECT COUNT(*) FROM videos WHERE is_favorite = 1")
        val hiddenCount = scalarInt(db, "SELECT COUNT(*) FROM videos WHERE is_hidden = 1")
        val watchedOnce = scalarInt(db, "SELECT COUNT(*) FROM videos WHERE times_watched > 0")
        val totalVideoDuration = scalarDouble(db, "SELECT COALESCE(SUM(duration), 0) FROM videos")
        val totalWatchedDuration = scalarDouble(db, "SELECT COALESCE(SUM(duration * times_watched), 0) FROM videos")

        return LibraryStats(
            totalVideos = totalVideos,
            totalVideoDuration = totalVideoDuration,
            totalWatchedPlays = totalWatchedPlays,
            totalWatchedDuration = totalWatchedDuration,
            videosWatchedAtLeastOnce = watchedOnce,
            favoritesCount = favoritesCount,
            hiddenCount = hiddenCount,
            currentSessionWatched = scalarInt(db, "SELECT COUNT(*) FROM watch_events"),
            mostPopularCamera = topValue(db, "camera_make || ' ' || camera_model"),
            mostPopularCodec = topValue(db, "video_codec"),
            mostPopularFileType = topValue(db, "file_type"),
            mostPopularPlace = topValue(db, "city || ', ' || country"),
            mostPopularYear = topValue(db, "substr(capture_date, 1, 4)")
        )
    }

    private fun scalarInt(db: SQLiteDatabase, sql: String): Int {
        db.rawQuery(sql, null).use { cursor ->
            return if (cursor.moveToFirst()) cursor.getInt(0) else 0
        }
    }

    private fun scalarDouble(db: SQLiteDatabase, sql: String): Double {
        db.rawQuery(sql, null).use { cursor ->
            return if (cursor.moveToFirst()) cursor.getDouble(0) else 0.0
        }
    }

    private fun topValue(db: SQLiteDatabase, expression: String): String {
        val sql = "SELECT $expression AS value, COUNT(*) AS count FROM videos WHERE TRIM(COALESCE($expression, '')) != '' GROUP BY value ORDER BY count DESC LIMIT 1"
        db.rawQuery(sql, null).use { cursor ->
            return if (cursor.moveToFirst()) cursor.getString(0) ?: "-" else "-"
        }
    }

    private fun android.database.Cursor.toCandidate(): VideoCandidate {
        fun string(name: String) = getString(getColumnIndexOrThrow(name)).orEmpty()
        return VideoCandidate(
            id = string("asset_id"),
            title = string("title"),
            duration = getDouble(getColumnIndexOrThrow("duration")),
            isFavorite = getInt(getColumnIndexOrThrow("is_favorite")) == 1,
            isHidden = getInt(getColumnIndexOrThrow("is_hidden")) == 1,
            timesWatched = getInt(getColumnIndexOrThrow("times_watched")),
            captureDate = string("capture_date"),
            city = string("city"),
            country = string("country"),
            cameraMake = string("camera_make"),
            cameraModel = string("camera_model"),
            lensModel = string("lens_model"),
            fNumber = string("f_number"),
            focalLength = string("focal_length"),
            iso = string("iso"),
            exposureTime = string("exposure_time"),
            latitude = string("latitude"),
            longitude = string("longitude"),
            videoCodec = string("video_codec"),
            fileType = string("file_type")
        )
    }
}
