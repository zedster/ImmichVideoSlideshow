import Foundation
import SQLite3

actor SQLiteVideoStore {
    struct SyncSummary {
        let pagesFetched: Int
        let rowsUpserted: Int
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
                asset_id, title, duration, is_favorite, is_hidden, times_watched, capture_date, city, country,
                camera_make, camera_model, lens_model, f_number, focal_length, iso,
                exposure_time, latitude, longitude, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(asset_id) DO UPDATE SET
                title=excluded.title,
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
                sqlite3_bind_double(stmt, 3, record.duration)
                sqlite3_bind_int(stmt, 4, record.isFavorite ? 1 : 0)
                sqlite3_bind_int(stmt, 5, 0)
                sqlite3_bind_int(stmt, 6, 0)
                sqlite3_bind_text(stmt, 7, (record.captureDate as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 8, (record.city as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 9, (record.country as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 10, (record.cameraMake as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 11, (record.cameraModel as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 12, (record.lensModel as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 13, (record.fNumber as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 14, (record.focalLength as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 15, (record.iso as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 16, (record.exposureTime as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 17, (record.latitude as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 18, (record.longitude as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 19, (now as NSString).utf8String, -1, nil)

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

    func countQualifying(minDuration: Double, onlyFavorites: Bool) throws -> Int {
        try withDatabase { db in
            let sql = onlyFavorites
                ? "SELECT COUNT(*) FROM videos WHERE duration >= ? AND is_favorite = 1 AND COALESCE(is_hidden, 0) = 0"
                : "SELECT COUNT(*) FROM videos WHERE duration >= ? AND COALESCE(is_hidden, 0) = 0"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw storeError(db, fallback: "prepare countQualifying failed")
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, minDuration)
            guard sqlite3_step(stmt) == SQLITE_ROW else {
                throw storeError(db, fallback: "countQualifying step failed")
            }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    func selectRandom(minDuration: Double, onlyFavorites: Bool) throws -> VideoCandidate? {
        try withDatabase { db in
            let sql = onlyFavorites
                ? "SELECT asset_id, title, duration, is_favorite, is_hidden, times_watched, capture_date, city, country, camera_make, camera_model, lens_model, f_number, focal_length, iso, exposure_time, latitude, longitude FROM videos WHERE duration >= ? AND is_favorite = 1 AND COALESCE(is_hidden, 0) = 0 ORDER BY CASE WHEN COALESCE(times_watched, 0) = 0 THEN 0 ELSE 1 END ASC, RANDOM() LIMIT 1"
                : "SELECT asset_id, title, duration, is_favorite, is_hidden, times_watched, capture_date, city, country, camera_make, camera_model, lens_model, f_number, focal_length, iso, exposure_time, latitude, longitude FROM videos WHERE duration >= ? AND COALESCE(is_hidden, 0) = 0 ORDER BY CASE WHEN COALESCE(times_watched, 0) = 0 THEN 0 ELSE 1 END ASC, RANDOM() LIMIT 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw storeError(db, fallback: "prepare selectRandom failed")
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, minDuration)
            guard sqlite3_step(stmt) == SQLITE_ROW else {
                return nil
            }
            return decodeCandidate(stmt: stmt)
        }
    }

    func selectSequential(afterAssetId: String?, minDuration: Double, onlyFavorites: Bool) throws -> VideoCandidate? {
        try withDatabase { db in
            let baseWhere = onlyFavorites
                ? "duration >= ? AND is_favorite = 1 AND COALESCE(is_hidden, 0) = 0"
                : "duration >= ? AND COALESCE(is_hidden, 0) = 0"

            if let afterAssetId, let anchor = try selectSortAnchor(db: db, assetId: afterAssetId) {
                let sql = """
                SELECT asset_id, title, duration, is_favorite, is_hidden, times_watched, capture_date, city, country, camera_make, camera_model, lens_model, f_number, focal_length, iso, exposure_time, latitude, longitude
                FROM videos
                WHERE \(baseWhere)
                  AND (
                    COALESCE(capture_date, '') > ?
                    OR (COALESCE(capture_date, '') = ? AND asset_id > ?)
                  )
                ORDER BY COALESCE(capture_date, '') ASC, asset_id ASC
                LIMIT 1
                """
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    throw storeError(db, fallback: "prepare selectSequential greater-than failed")
                }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_double(stmt, 1, minDuration)
                sqlite3_bind_text(stmt, 2, (anchor.captureDate as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (anchor.captureDate as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 4, (anchor.assetId as NSString).utf8String, -1, nil)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    return decodeCandidate(stmt: stmt)
                }
            }

            let fallbackSQL = """
            SELECT asset_id, title, duration, is_favorite, is_hidden, times_watched, capture_date, city, country, camera_make, camera_model, lens_model, f_number, focal_length, iso, exposure_time, latitude, longitude
            FROM videos
            WHERE \(baseWhere)
            ORDER BY COALESCE(capture_date, '') ASC, asset_id ASC
            LIMIT 1
            """
            var fallbackStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, fallbackSQL, -1, &fallbackStmt, nil) == SQLITE_OK else {
                throw storeError(db, fallback: "prepare selectSequential fallback failed")
            }
            defer { sqlite3_finalize(fallbackStmt) }

            sqlite3_bind_double(fallbackStmt, 1, minDuration)
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

    private func selectSortAnchor(db: OpaquePointer, assetId: String) throws -> (captureDate: String, assetId: String)? {
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
        return (captureDate, resolvedAssetId)
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
}
