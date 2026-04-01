import Foundation
import SQLite3

actor SQLiteVideoStore {
    struct SyncSummary {
        let pagesFetched: Int
        let rowsUpserted: Int
    }

    struct RankedStat: Equatable {
        let label: String
        let count: Int
    }

    struct LibraryStats {
        let totalVideos: Int
        let totalVideoDuration: Double
        let totalWatchedPlays: Int
        let totalWatchedDuration: Double
        let watchedPlays7Days: Int
        let watchedPlays30Days: Int
        let videosWatchedAtLeastOnce: Int
        let favoritesCount: Int
        let hiddenCount: Int
        let currentSessionWatched: Int
        let mostPopularCamera: String
        let mostPopularCodec: String
        let mostPopularFileType: String
        let mostPopularPlace: String
        let mostPopularYear: String
        let topCameras: [RankedStat]
        let topCodecs: [RankedStat]
        let topFileTypes: [RankedStat]
        let topPlaces: [RankedStat]
        let topYears: [RankedStat]
    }

    private let sequentialLastAssetIdKey = "playback.sequential.last_asset_id"

    private let dbPath: String
    private let dbDirectoryPath: String

    init(dbFileName: String = "videos.sqlite") {
        let fm = FileManager.default
        let baseDirectory = Self.resolveWritableBaseDirectory(fileManager: fm)
        let dbURL = baseDirectory.appendingPathComponent(dbFileName, isDirectory: false)

        dbDirectoryPath = baseDirectory.path
        dbPath = dbURL.path

        print("DB directory:", dbDirectoryPath)
        print("DB file:", dbPath)
    }

    func initializeSchema() throws {
        try withDatabase { db in
            try exec(db, sql: """
            CREATE TABLE IF NOT EXISTS videos (
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
                longitude TEXT,
                updated_at TEXT NOT NULL
            )
            """)

            try exec(db, sql: "CREATE INDEX IF NOT EXISTS idx_videos_duration ON videos(duration)")
            try exec(db, sql: "CREATE INDEX IF NOT EXISTS idx_videos_favorite ON videos(is_favorite)")
            try exec(db, sql: "CREATE INDEX IF NOT EXISTS idx_videos_hidden ON videos(is_hidden)")
            try exec(db, sql: "CREATE INDEX IF NOT EXISTS idx_videos_times_watched ON videos(times_watched)")
            try ensureColumn(db, table: "videos", column: "is_hidden", type: "INTEGER NOT NULL DEFAULT 0")
            try ensureColumn(db, table: "videos", column: "times_watched", type: "INTEGER NOT NULL DEFAULT 0")
            try ensureColumn(db, table: "videos", column: "file_type", type: "TEXT")
            try ensureColumn(db, table: "videos", column: "video_codec", type: "TEXT")
            try ensureColumn(db, table: "videos", column: "capture_date", type: "TEXT")
            try ensureColumn(db, table: "videos", column: "city", type: "TEXT")
            try ensureColumn(db, table: "videos", column: "country", type: "TEXT")
            try ensureColumn(db, table: "videos", column: "camera_make", type: "TEXT")
            try ensureColumn(db, table: "videos", column: "camera_model", type: "TEXT")
            try ensureColumn(db, table: "videos", column: "lens_model", type: "TEXT")
            try ensureColumn(db, table: "videos", column: "f_number", type: "TEXT")
            try ensureColumn(db, table: "videos", column: "focal_length", type: "TEXT")
            try ensureColumn(db, table: "videos", column: "iso", type: "TEXT")
            try ensureColumn(db, table: "videos", column: "exposure_time", type: "TEXT")
            try ensureColumn(db, table: "videos", column: "latitude", type: "TEXT")
            try ensureColumn(db, table: "videos", column: "longitude", type: "TEXT")

            try exec(db, sql: """
            CREATE TABLE IF NOT EXISTS sync_state (
                key TEXT PRIMARY KEY,
                value TEXT
            )
            """)

            try exec(db, sql: """
            CREATE TABLE IF NOT EXISTS watch_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                asset_id TEXT NOT NULL,
                started_at TEXT NOT NULL
            )
            """)
            try exec(db, sql: "CREATE INDEX IF NOT EXISTS idx_watch_events_started_at ON watch_events(started_at)")
            try exec(db, sql: "CREATE INDEX IF NOT EXISTS idx_watch_events_asset_id ON watch_events(asset_id)")
        }
    }

    func upsert(records: [ImmichAssetRecord]) throws -> Int {
        guard !records.isEmpty else { return 0 }
        return try withDatabase { db in
            try exec(db, sql: "BEGIN TRANSACTION")
            defer {
                _ = sqlite3_exec(db, "COMMIT", nil, nil, nil)
            }

            let sql = """
            INSERT INTO videos (
                asset_id, title, file_type, video_codec, duration, is_favorite, is_hidden, times_watched, capture_date, city, country,
                camera_make, camera_model, lens_model, f_number, focal_length, iso,
                exposure_time, latitude, longitude, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(asset_id) DO UPDATE SET
                title=excluded.title,
                file_type=excluded.file_type,
                video_codec=excluded.video_codec,
                duration=excluded.duration,
                is_favorite=excluded.is_favorite,
                capture_date=excluded.capture_date,
                city=excluded.city,
                country=excluded.country,
                camera_make=excluded.camera_make,
                camera_model=excluded.camera_model,
                lens_model=excluded.lens_model,
                f_number=excluded.f_number,
                focal_length=excluded.focal_length,
                iso=excluded.iso,
                exposure_time=excluded.exposure_time,
                latitude=excluded.latitude,
                longitude=excluded.longitude,
                updated_at=excluded.updated_at
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw storeError(db, fallback: "prepare upsert failed")
            }
            defer { sqlite3_finalize(stmt) }

            let now = ISO8601DateFormatter().string(from: Date())
            var count = 0
            for record in records {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)

                sqlite3_bind_text(stmt, 1, (record.id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (record.title as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (record.fileType as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 4, (record.videoCodec as NSString).utf8String, -1, nil)
                sqlite3_bind_double(stmt, 5, record.duration)
                sqlite3_bind_int(stmt, 6, record.isFavorite ? 1 : 0)
                sqlite3_bind_int(stmt, 7, 0)
                sqlite3_bind_int(stmt, 8, 0)
                sqlite3_bind_text(stmt, 9, (record.captureDate as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 10, (record.city as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 11, (record.country as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 12, (record.cameraMake as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 13, (record.cameraModel as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 14, (record.lensModel as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 15, (record.fNumber as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 16, (record.focalLength as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 17, (record.iso as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 18, (record.exposureTime as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 19, (record.latitude as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 20, (record.longitude as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 21, (now as NSString).utf8String, -1, nil)

                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw storeError(db, fallback: "upsert step failed")
                }
                count += 1
            }
            return count
        }
    }

    func setSyncState(key: String, value: String) throws {
        try withDatabase { db in
            let sql = """
            INSERT INTO sync_state (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value=excluded.value
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw storeError(db, fallback: "prepare setSyncState failed")
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (value as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw storeError(db, fallback: "setSyncState step failed")
            }
        }
    }

    func getSyncState(key: String) throws -> String? {
        try withDatabase { db in
            let sql = "SELECT value FROM sync_state WHERE key = ? LIMIT 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw storeError(db, fallback: "prepare getSyncState failed")
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                guard let cstr = sqlite3_column_text(stmt, 0) else { return nil }
                return String(cString: cstr)
            }
            return nil
        }
    }

    func getSequentialLastAssetId() throws -> String? {
        let value = try getSyncState(key: sequentialLastAssetIdKey)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    func setSequentialLastAssetId(_ assetId: String) throws {
        try setSyncState(key: sequentialLastAssetIdKey, value: assetId)
    }

    func clearSequentialLastAssetId() throws {
        try setSyncState(key: sequentialLastAssetIdKey, value: "")
    }

    func countQualifying(
        minDuration: Double,
        onlyFavorites: Bool,
        onlyThisMonth: Bool,
        onlyThisDay: Bool,
        onlyThisWeek: Bool,
        referenceCaptureDate: String,
        placeCity: String,
        placeCountry: String
    ) throws -> Int {
        try withDatabase { db in
            let filters = selectionFilters(
                onlyFavorites: onlyFavorites,
                onlyThisMonth: onlyThisMonth,
                onlyThisDay: onlyThisDay,
                onlyThisWeek: onlyThisWeek,
                referenceCaptureDate: referenceCaptureDate,
                placeCity: placeCity,
                placeCountry: placeCountry
            )
            let sql = """
            SELECT COUNT(*)
            FROM videos
            WHERE duration >= ?
              AND \(filters.whereClause)
              AND COALESCE(is_hidden, 0) = 0
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw storeError(db, fallback: "prepare countQualifying failed")
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, minDuration)
            bind(filters.bindings, to: stmt, startingAt: 2)
            guard sqlite3_step(stmt) == SQLITE_ROW else {
                throw storeError(db, fallback: "countQualifying step failed")
            }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    func getLibraryStats() throws -> LibraryStats {
        try withDatabase { db in
            let now = Date()
            let formatter = ISO8601DateFormatter()
            let since7 = formatter.string(from: now.addingTimeInterval(-(7 * 24 * 60 * 60)))
            let since30 = formatter.string(from: now.addingTimeInterval(-(30 * 24 * 60 * 60)))

            let totalsSQL = """
            SELECT
                COUNT(*) AS total_videos,
                COALESCE(SUM(COALESCE(duration, 0)), 0) AS total_video_duration,
                COALESCE(SUM(COALESCE(times_watched, 0)), 0) AS total_watched_plays,
                COALESCE(SUM(COALESCE(duration, 0) * COALESCE(times_watched, 0)), 0) AS total_watched_duration,
                COALESCE(SUM(CASE WHEN COALESCE(times_watched, 0) > 0 THEN 1 ELSE 0 END), 0) AS watched_once_count,
                COALESCE(SUM(CASE WHEN is_favorite = 1 THEN 1 ELSE 0 END), 0) AS favorites_count,
                COALESCE(SUM(CASE WHEN COALESCE(is_hidden, 0) = 1 THEN 1 ELSE 0 END), 0) AS hidden_count
            FROM videos
            """
            var totalsStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, totalsSQL, -1, &totalsStmt, nil) == SQLITE_OK else {
                throw storeError(db, fallback: "prepare library totals failed")
            }
            defer { sqlite3_finalize(totalsStmt) }

            guard sqlite3_step(totalsStmt) == SQLITE_ROW else {
                throw storeError(db, fallback: "library totals step failed")
            }
            let totalVideos = Int(sqlite3_column_int64(totalsStmt, 0))
            let totalVideoDuration = sqlite3_column_double(totalsStmt, 1)
            let totalWatchedPlays = Int(sqlite3_column_int64(totalsStmt, 2))
            let totalWatchedDuration = sqlite3_column_double(totalsStmt, 3)
            let videosWatchedAtLeastOnce = Int(sqlite3_column_int64(totalsStmt, 4))
            let favoritesCount = Int(sqlite3_column_int64(totalsStmt, 5))
            let hiddenCount = Int(sqlite3_column_int64(totalsStmt, 6))

            let watchedPlays7Days = try scalarInt(
                db: db,
                sql: "SELECT COUNT(*) FROM watch_events WHERE started_at >= ?",
                bindTexts: [since7]
            )
            let watchedPlays30Days = try scalarInt(
                db: db,
                sql: "SELECT COUNT(*) FROM watch_events WHERE started_at >= ?",
                bindTexts: [since30]
            )

            let mostPopularCamera = try topValue(
                db: db,
                sql: """
                SELECT camera_name, COUNT(*) AS c
                FROM (
                    SELECT
                        CASE
                            WHEN TRIM(COALESCE(camera_make, '')) != '' AND TRIM(COALESCE(camera_model, '')) != ''
                                THEN TRIM(camera_make) || ' ' || TRIM(camera_model)
                            WHEN TRIM(COALESCE(camera_model, '')) != ''
                                THEN TRIM(camera_model)
                            WHEN TRIM(COALESCE(camera_make, '')) != ''
                                THEN TRIM(camera_make)
                            ELSE ''
                        END AS camera_name
                    FROM videos
                )
                WHERE camera_name != ''
                GROUP BY camera_name
                ORDER BY c DESC, camera_name ASC
                LIMIT 1
                """
            )

            let mostPopularCodec = try topValue(
                db: db,
                sql: """
                SELECT codec_name, COUNT(*) AS c
                FROM (
                    SELECT TRIM(COALESCE(video_codec, '')) AS codec_name
                    FROM videos
                )
                WHERE codec_name != ''
                GROUP BY codec_name
                ORDER BY c DESC, codec_name ASC
                LIMIT 1
                """
            )

            let mostPopularFileType = try topValue(
                db: db,
                sql: """
                SELECT file_type, COUNT(*) AS c
                FROM videos
                WHERE TRIM(COALESCE(file_type, '')) != ''
                GROUP BY file_type
                ORDER BY c DESC, file_type ASC
                LIMIT 1
                """
            )

            let mostPopularPlace = try topValue(
                db: db,
                sql: """
                SELECT place_name, COUNT(*) AS c
                FROM (
                    SELECT
                        CASE
                            WHEN TRIM(COALESCE(city, '')) != '' AND TRIM(COALESCE(country, '')) != ''
                                THEN TRIM(city) || ', ' || TRIM(country)
                            WHEN TRIM(COALESCE(city, '')) != ''
                                THEN TRIM(city)
                            WHEN TRIM(COALESCE(country, '')) != ''
                                THEN TRIM(country)
                            ELSE ''
                        END AS place_name
                    FROM videos
                )
                WHERE place_name != ''
                GROUP BY place_name
                ORDER BY c DESC, place_name ASC
                LIMIT 1
                """
            )

            let mostPopularYear = try topValue(
                db: db,
                sql: """
                SELECT year_value, COUNT(*) AS c
                FROM (
                    SELECT SUBSTR(COALESCE(capture_date, ''), 1, 4) AS year_value
                    FROM videos
                )
                WHERE year_value GLOB '[0-9][0-9][0-9][0-9]'
                GROUP BY year_value
                ORDER BY c DESC, year_value ASC
                LIMIT 1
                """
            )

            let topCameras = try topRankedValues(
                db: db,
                sql: """
                SELECT camera_name, COUNT(*) AS c
                FROM (
                    SELECT
                        CASE
                            WHEN TRIM(COALESCE(camera_make, '')) != '' AND TRIM(COALESCE(camera_model, '')) != ''
                                THEN TRIM(camera_make) || ' ' || TRIM(camera_model)
                            WHEN TRIM(COALESCE(camera_model, '')) != ''
                                THEN TRIM(camera_model)
                            WHEN TRIM(COALESCE(camera_make, '')) != ''
                                THEN TRIM(camera_make)
                            ELSE ''
                        END AS camera_name
                    FROM videos
                )
                WHERE camera_name != ''
                GROUP BY camera_name
                ORDER BY c DESC, camera_name ASC
                LIMIT 5
                """
            )

            let topCodecs = try topRankedValues(
                db: db,
                sql: """
                SELECT codec_name, COUNT(*) AS c
                FROM (
                    SELECT TRIM(COALESCE(video_codec, '')) AS codec_name
                    FROM videos
                )
                WHERE codec_name != ''
                GROUP BY codec_name
                ORDER BY c DESC, codec_name ASC
                LIMIT 5
                """
            )

            let topFileTypes = try topRankedValues(
                db: db,
                sql: """
                SELECT file_type, COUNT(*) AS c
                FROM videos
                WHERE TRIM(COALESCE(file_type, '')) != ''
                GROUP BY file_type
                ORDER BY c DESC, file_type ASC
                LIMIT 5
                """
            )

            let topPlaces = try topRankedValues(
                db: db,
                sql: """
                SELECT place_name, COUNT(*) AS c
                FROM (
                    SELECT
                        CASE
                            WHEN TRIM(COALESCE(city, '')) != '' AND TRIM(COALESCE(country, '')) != ''
                                THEN TRIM(city) || ', ' || TRIM(country)
                            WHEN TRIM(COALESCE(city, '')) != ''
                                THEN TRIM(city)
                            WHEN TRIM(COALESCE(country, '')) != ''
                                THEN TRIM(country)
                            ELSE ''
                        END AS place_name
                    FROM videos
                )
                WHERE place_name != ''
                GROUP BY place_name
                ORDER BY c DESC, place_name ASC
                LIMIT 5
                """
            )

            let topYears = try topRankedValues(
                db: db,
                sql: """
                SELECT year_value, COUNT(*) AS c
                FROM (
                    SELECT SUBSTR(COALESCE(capture_date, ''), 1, 4) AS year_value
                    FROM videos
                )
                WHERE year_value GLOB '[0-9][0-9][0-9][0-9]'
                GROUP BY year_value
                ORDER BY c DESC, year_value ASC
                LIMIT 5
                """
            )

            let sessionStartedAt = try scalarText(
                db: db,
                sql: "SELECT value FROM sync_state WHERE key = ? LIMIT 1",
                bindTexts: ["session_started_at"]
            ) ?? since30
            let currentSessionWatched = try scalarInt(
                db: db,
                sql: "SELECT COUNT(*) FROM watch_events WHERE started_at >= ?",
                bindTexts: [sessionStartedAt]
            )

            return LibraryStats(
                totalVideos: totalVideos,
                totalVideoDuration: totalVideoDuration,
                totalWatchedPlays: totalWatchedPlays,
                totalWatchedDuration: totalWatchedDuration,
                watchedPlays7Days: watchedPlays7Days,
                watchedPlays30Days: watchedPlays30Days,
                videosWatchedAtLeastOnce: videosWatchedAtLeastOnce,
                favoritesCount: favoritesCount,
                hiddenCount: hiddenCount,
                currentSessionWatched: currentSessionWatched,
                mostPopularCamera: mostPopularCamera,
                mostPopularCodec: mostPopularCodec,
                mostPopularFileType: mostPopularFileType,
                mostPopularPlace: mostPopularPlace,
                mostPopularYear: mostPopularYear,
                topCameras: topCameras,
                topCodecs: topCodecs,
                topFileTypes: topFileTypes,
                topPlaces: topPlaces,
                topYears: topYears
            )
        }
    }

    func selectRandom(
        minDuration: Double,
        onlyFavorites: Bool,
        onlyThisMonth: Bool,
        onlyThisDay: Bool,
        onlyThisWeek: Bool,
        referenceCaptureDate: String,
        placeCity: String,
        placeCountry: String
    ) throws -> VideoCandidate? {
        try withDatabase { db in
            let filters = selectionFilters(
                onlyFavorites: onlyFavorites,
                onlyThisMonth: onlyThisMonth,
                onlyThisDay: onlyThisDay,
                onlyThisWeek: onlyThisWeek,
                referenceCaptureDate: referenceCaptureDate,
                placeCity: placeCity,
                placeCountry: placeCountry
            )
            let sql = """
            SELECT asset_id, title, duration, is_favorite, is_hidden, times_watched, capture_date, city, country, camera_make, camera_model, lens_model, f_number, focal_length, iso, exposure_time, latitude, longitude
            FROM videos
            WHERE duration >= ?
              AND \(filters.whereClause)
              AND COALESCE(is_hidden, 0) = 0
            ORDER BY CASE WHEN COALESCE(times_watched, 0) = 0 THEN 0 ELSE 1 END ASC, RANDOM()
            LIMIT 1
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw storeError(db, fallback: "prepare selectRandom failed")
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, minDuration)
            bind(filters.bindings, to: stmt, startingAt: 2)
            guard sqlite3_step(stmt) == SQLITE_ROW else {
                return nil
            }
            return decodeCandidate(stmt: stmt)
        }
    }

    func selectSequential(
        afterAssetId: String?,
        newestFirst: Bool,
        minDuration: Double,
        onlyFavorites: Bool,
        onlyThisMonth: Bool,
        onlyThisDay: Bool,
        onlyThisWeek: Bool,
        referenceCaptureDate: String,
        placeCity: String,
        placeCountry: String
    ) throws -> VideoCandidate? {
        try withDatabase { db in
            let filters = selectionFilters(
                onlyFavorites: onlyFavorites,
                onlyThisMonth: onlyThisMonth,
                onlyThisDay: onlyThisDay,
                onlyThisWeek: onlyThisWeek,
                referenceCaptureDate: referenceCaptureDate,
                placeCity: placeCity,
                placeCountry: placeCountry
            )
            let baseWhere = "duration >= ? AND \(filters.whereClause) AND COALESCE(is_hidden, 0) = 0"
            let sortExpr = "CASE WHEN COALESCE(capture_date, '') = '' THEN 1 ELSE 0 END"
            let compareDate = newestFirst ? "<" : ">"
            let compareBucket = newestFirst ? "<" : ">"
            let orderDirection = newestFirst ? "DESC" : "ASC"

            if let afterAssetId, let anchor = try selectSortAnchor(db: db, assetId: afterAssetId) {
                let sql = """
                SELECT asset_id, title, duration, is_favorite, is_hidden, times_watched, capture_date, city, country, camera_make, camera_model, lens_model, f_number, focal_length, iso, exposure_time, latitude, longitude
                FROM videos
                WHERE \(baseWhere)
                  AND (
                    \(sortExpr) \(compareBucket) ?
                    OR (
                        \(sortExpr) = ?
                        AND (
                            COALESCE(capture_date, '') \(compareDate) ?
                            OR (COALESCE(capture_date, '') = ? AND asset_id \(compareDate) ?)
                        )
                    )
                  )
                ORDER BY \(sortExpr) \(orderDirection), COALESCE(capture_date, '') \(orderDirection), asset_id \(orderDirection)
                LIMIT 1
                """
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    throw storeError(db, fallback: "prepare selectSequential greater-than failed")
                }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_double(stmt, 1, minDuration)
                bind(filters.bindings, to: stmt, startingAt: 2)
                let anchorIndex = Int32(2 + filters.bindings.count)
                sqlite3_bind_int(stmt, anchorIndex, Int32(anchor.emptyDateBucket))
                sqlite3_bind_int(stmt, anchorIndex + 1, Int32(anchor.emptyDateBucket))
                sqlite3_bind_text(stmt, anchorIndex + 2, (anchor.captureDate as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, anchorIndex + 3, (anchor.captureDate as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, anchorIndex + 4, (anchor.assetId as NSString).utf8String, -1, nil)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    return decodeCandidate(stmt: stmt)
                }
            }

            let fallbackSQL = """
            SELECT asset_id, title, duration, is_favorite, is_hidden, times_watched, capture_date, city, country, camera_make, camera_model, lens_model, f_number, focal_length, iso, exposure_time, latitude, longitude
            FROM videos
            WHERE \(baseWhere)
            ORDER BY \(sortExpr) \(orderDirection), COALESCE(capture_date, '') \(orderDirection), asset_id \(orderDirection)
            LIMIT 1
            """
            var fallbackStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, fallbackSQL, -1, &fallbackStmt, nil) == SQLITE_OK else {
                throw storeError(db, fallback: "prepare selectSequential fallback failed")
            }
            defer { sqlite3_finalize(fallbackStmt) }

            sqlite3_bind_double(fallbackStmt, 1, minDuration)
            bind(filters.bindings, to: fallbackStmt, startingAt: 2)
            guard sqlite3_step(fallbackStmt) == SQLITE_ROW else {
                return nil
            }
            return decodeCandidate(stmt: fallbackStmt)
        }
    }

    func setHidden(assetId: String, isHidden: Bool) throws {
        try withDatabase { db in
            let sql = """
            UPDATE videos
            SET is_hidden = ?, updated_at = ?
            WHERE asset_id = ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw storeError(db, fallback: "prepare setHidden failed")
            }
            defer { sqlite3_finalize(stmt) }

            let now = ISO8601DateFormatter().string(from: Date())
            sqlite3_bind_int(stmt, 1, isHidden ? 1 : 0)
            sqlite3_bind_text(stmt, 2, (now as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (assetId as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw storeError(db, fallback: "setHidden step failed")
            }
        }
    }

    func setFavorite(assetId: String, isFavorite: Bool) throws {
        try withDatabase { db in
            let sql = """
            UPDATE videos
            SET is_favorite = ?, updated_at = ?
            WHERE asset_id = ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw storeError(db, fallback: "prepare setFavorite failed")
            }
            defer { sqlite3_finalize(stmt) }

            let now = ISO8601DateFormatter().string(from: Date())
            sqlite3_bind_int(stmt, 1, isFavorite ? 1 : 0)
            sqlite3_bind_text(stmt, 2, (now as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (assetId as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw storeError(db, fallback: "setFavorite step failed")
            }
        }
    }

    func incrementWatchCount(assetId: String) throws -> Int {
        try withDatabase { db in
            let now = ISO8601DateFormatter().string(from: Date())

            let updateSQL = """
            UPDATE videos
            SET times_watched = COALESCE(times_watched, 0) + 1,
                updated_at = ?
            WHERE asset_id = ?
            """
            var updateStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK else {
                throw storeError(db, fallback: "prepare incrementWatchCount failed")
            }
            defer { sqlite3_finalize(updateStmt) }

            sqlite3_bind_text(updateStmt, 1, (now as NSString).utf8String, -1, nil)
            sqlite3_bind_text(updateStmt, 2, (assetId as NSString).utf8String, -1, nil)
            guard sqlite3_step(updateStmt) == SQLITE_DONE else {
                throw storeError(db, fallback: "incrementWatchCount step failed")
            }

            let insertEventSQL = "INSERT INTO watch_events (asset_id, started_at) VALUES (?, ?)"
            var eventStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, insertEventSQL, -1, &eventStmt, nil) == SQLITE_OK else {
                throw storeError(db, fallback: "prepare insert watch event failed")
            }
            defer { sqlite3_finalize(eventStmt) }

            sqlite3_bind_text(eventStmt, 1, (assetId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(eventStmt, 2, (now as NSString).utf8String, -1, nil)
            guard sqlite3_step(eventStmt) == SQLITE_DONE else {
                throw storeError(db, fallback: "insert watch event step failed")
            }

            let selectSQL = "SELECT COALESCE(times_watched, 0) FROM videos WHERE asset_id = ? LIMIT 1"
            var selectStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else {
                throw storeError(db, fallback: "prepare select watch count failed")
            }
            defer { sqlite3_finalize(selectStmt) }

            sqlite3_bind_text(selectStmt, 1, (assetId as NSString).utf8String, -1, nil)
            guard sqlite3_step(selectStmt) == SQLITE_ROW else {
                return 0
            }
            return Int(sqlite3_column_int64(selectStmt, 0))
        }
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        let fm = FileManager.default

        do {
            try fm.createDirectory(atPath: dbDirectoryPath, withIntermediateDirectories: true)
            try fm.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: dbDirectoryPath)
        } catch {
            throw NSError(
                domain: "SQLiteVideoStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot prepare sqlite DB directory at \(dbDirectoryPath): \(error.localizedDescription)"]
            )
        }

        var db: OpaquePointer?

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(dbPath, &db, flags, nil) == SQLITE_OK, let db else {
            throw NSError(
                domain: "SQLiteVideoStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot open sqlite DB at \(dbPath)"]
            )
        }

        _ = try? fm.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: dbPath)

        defer { sqlite3_close(db) }

        return try body(db)
    }

    private func selectSortAnchor(db: OpaquePointer, assetId: String) throws -> (emptyDateBucket: Int, captureDate: String, assetId: String)? {
        let sql = "SELECT COALESCE(capture_date, ''), asset_id FROM videos WHERE asset_id = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw storeError(db, fallback: "prepare selectSortAnchor failed")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (assetId as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        let captureDate = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
        let resolvedAssetId = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? assetId
        let emptyDateBucket = captureDate.isEmpty ? 1 : 0
        return (emptyDateBucket, captureDate, resolvedAssetId)
    }

    private func currentMonthSQLCondition(column: String) -> String {
        "SUBSTR(COALESCE(\(column), ''), 6, 2) = STRFTIME('%m', 'now', 'localtime')"
    }

    private func currentDaySQLCondition(column: String) -> String {
        "SUBSTR(COALESCE(\(column), ''), 6, 5) = ?"
    }

    private func currentWeekSQLCondition(column: String) -> String {
        "STRFTIME('%W', DATETIME(COALESCE(\(column), ''))) = ?"
    }

    private func selectionFilters(
        onlyFavorites: Bool,
        onlyThisMonth: Bool,
        onlyThisDay: Bool,
        onlyThisWeek: Bool,
        referenceCaptureDate: String,
        placeCity: String,
        placeCountry: String
    ) -> (whereClause: String, bindings: [SQLiteBindValue]) {
        var clauses: [String] = []
        var bindings: [SQLiteBindValue] = []

        if onlyFavorites {
            clauses.append("is_favorite = 1")
        }
        if onlyThisMonth {
            clauses.append(currentMonthSQLCondition(column: "capture_date"))
        }
        if onlyThisDay {
            let referenceMonthDay = monthDayComponent(from: referenceCaptureDate)
            if !referenceMonthDay.isEmpty {
                clauses.append(currentDaySQLCondition(column: "capture_date"))
                bindings.append(.text(referenceMonthDay))
            }
        }
        if onlyThisWeek {
            let referenceWeek = weekOfYearComponent(from: referenceCaptureDate)
            if !referenceWeek.isEmpty {
                clauses.append(currentWeekSQLCondition(column: "capture_date"))
                bindings.append(.text(referenceWeek))
            }
        }

        let trimmedCity = placeCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = placeCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCity.isEmpty && !trimmedCountry.isEmpty {
            clauses.append("LOWER(TRIM(COALESCE(city, ''))) = LOWER(?) AND LOWER(TRIM(COALESCE(country, ''))) = LOWER(?)")
            bindings.append(.text(trimmedCity))
            bindings.append(.text(trimmedCountry))
        } else if !trimmedCity.isEmpty {
            clauses.append("LOWER(TRIM(COALESCE(city, ''))) = LOWER(?)")
            bindings.append(.text(trimmedCity))
        } else if !trimmedCountry.isEmpty {
            clauses.append("LOWER(TRIM(COALESCE(country, ''))) = LOWER(?)")
            bindings.append(.text(trimmedCountry))
        }

        return (clauses.isEmpty ? "1 = 1" : clauses.joined(separator: " AND "), bindings)
    }

    private func monthDayComponent(from raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 10 else { return "" }
        return String(value.dropFirst(5).prefix(5))
    }

    private func weekOfYearComponent(from raw: String) -> String {
        guard let date = parseCaptureDate(raw) else { return "" }
        let week = Calendar.current.component(.weekOfYear, from: date)
        return String(format: "%02d", week)
    }

    private func parseCaptureDate(_ raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        return Self.fallbackCaptureDateFormatter.date(from: value)
    }

    private func bind(_ values: [SQLiteBindValue], to stmt: OpaquePointer?, startingAt index: Int) {
        for (offset, value) in values.enumerated() {
            let bindIndex = Int32(index + offset)
            switch value {
            case .double(let number):
                sqlite3_bind_double(stmt, bindIndex, number)
            case .text(let string):
                sqlite3_bind_text(stmt, bindIndex, (string as NSString).utf8String, -1, nil)
            }
        }
    }

    private func decodeCandidate(stmt: OpaquePointer?) -> VideoCandidate? {
        guard let stmt else { return nil }
        guard let idC = sqlite3_column_text(stmt, 0) else { return nil }
        let id = String(cString: idC)
        let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "Untitled"
        let duration = sqlite3_column_double(stmt, 2)
        let isFavorite = sqlite3_column_int(stmt, 3) == 1
        let isHidden = sqlite3_column_int(stmt, 4) == 1
        let timesWatched = Int(sqlite3_column_int64(stmt, 5))
        let captureDate = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
        let city = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? ""
        let country = sqlite3_column_text(stmt, 8).map { String(cString: $0) } ?? ""
        let cameraMake = sqlite3_column_text(stmt, 9).map { String(cString: $0) } ?? ""
        let cameraModel = sqlite3_column_text(stmt, 10).map { String(cString: $0) } ?? ""
        let lensModel = sqlite3_column_text(stmt, 11).map { String(cString: $0) } ?? ""
        let fNumber = sqlite3_column_text(stmt, 12).map { String(cString: $0) } ?? ""
        let focalLength = sqlite3_column_text(stmt, 13).map { String(cString: $0) } ?? ""
        let iso = sqlite3_column_text(stmt, 14).map { String(cString: $0) } ?? ""
        let exposureTime = sqlite3_column_text(stmt, 15).map { String(cString: $0) } ?? ""
        let latitude = sqlite3_column_text(stmt, 16).map { String(cString: $0) } ?? ""
        let longitude = sqlite3_column_text(stmt, 17).map { String(cString: $0) } ?? ""
        return VideoCandidate(
            id: id,
            title: title,
            duration: duration,
            isFavorite: isFavorite,
            isHidden: isHidden,
            timesWatched: timesWatched,
            captureDate: captureDate,
            city: city,
            country: country,
            cameraMake: cameraMake,
            cameraModel: cameraModel,
            lensModel: lensModel,
            fNumber: fNumber,
            focalLength: focalLength,
            iso: iso,
            exposureTime: exposureTime,
            latitude: latitude,
            longitude: longitude
        )
    }

    private static func resolveWritableBaseDirectory(fileManager fm: FileManager) -> URL {
        let candidates: [URL] = [
            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        ].compactMap { $0 }

        for candidate in candidates {
            do {
                try fm.createDirectory(at: candidate, withIntermediateDirectories: true)
                try fm.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: candidate.path)
                return candidate
            } catch {
                continue
            }
        }

        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    private func exec(_ db: OpaquePointer, sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw storeError(db, fallback: "SQL exec failed")
        }
    }

    private func ensureColumn(_ db: OpaquePointer, table: String, column: String, type: String) throws {
        let pragma = "PRAGMA table_info(\(table))"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, pragma, -1, &stmt, nil) == SQLITE_OK else {
            throw storeError(db, fallback: "prepare table_info failed")
        }
        defer { sqlite3_finalize(stmt) }

        var hasColumn = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cName = sqlite3_column_text(stmt, 1) else { continue }
            if String(cString: cName) == column {
                hasColumn = true
                break
            }
        }

        if !hasColumn {
            try exec(db, sql: "ALTER TABLE \(table) ADD COLUMN \(column) \(type)")
        }
    }

    private func storeError(_ db: OpaquePointer, fallback: String) -> NSError {
        let msg = sqlite3_errmsg(db).flatMap { String(cString: $0) } ?? fallback
        return NSError(domain: "SQLiteVideoStore", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
    }

    private func topValue(db: OpaquePointer, sql: String) throws -> String {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw storeError(db, fallback: "prepare top value failed")
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return "-"
        }
        let value = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }

    private func topRankedValues(db: OpaquePointer, sql: String) throws -> [RankedStat] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw storeError(db, fallback: "prepare ranked values failed")
        }
        defer { sqlite3_finalize(stmt) }

        var rows: [RankedStat] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let labelRaw = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let label = labelRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty { continue }
            let count = Int(sqlite3_column_int64(stmt, 1))
            rows.append(RankedStat(label: label, count: count))
        }
        return rows
    }

    private func scalarInt(db: OpaquePointer, sql: String, bindTexts: [String] = []) throws -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw storeError(db, fallback: "prepare scalar int failed")
        }
        defer { sqlite3_finalize(stmt) }

        for (index, value) in bindTexts.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 1), (value as NSString).utf8String, -1, nil)
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func scalarText(db: OpaquePointer, sql: String, bindTexts: [String] = []) throws -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw storeError(db, fallback: "prepare scalar text failed")
        }
        defer { sqlite3_finalize(stmt) }

        for (index, value) in bindTexts.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 1), (value as NSString).utf8String, -1, nil)
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let c = sqlite3_column_text(stmt, 0) else { return nil }
        let text = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

private enum SQLiteBindValue {
    case double(Double)
    case text(String)
}

private extension SQLiteVideoStore {
    static let fallbackCaptureDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
