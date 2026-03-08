import Foundation
import SQLite3

actor SQLiteVideoStore {
    struct SyncSummary {
        let pagesFetched: Int
        let rowsUpserted: Int
    }

    private let dbPath: String

    init(dbFileName: String = "videos.sqlite") {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ImmichChannelTV", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbPath = dir.appendingPathComponent(dbFileName).path
    }

    func initializeSchema() throws {
        try withDatabase { db in
            try exec(db, sql: """
            CREATE TABLE IF NOT EXISTS videos (
                asset_id TEXT PRIMARY KEY,
                title TEXT,
                duration REAL NOT NULL,
                is_favorite INTEGER NOT NULL DEFAULT 0,
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
                asset_id, title, duration, is_favorite, capture_date, city, country,
                camera_make, camera_model, lens_model, f_number, focal_length, iso,
                exposure_time, latitude, longitude, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                sqlite3_bind_text(stmt, 5, (record.captureDate as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 6, (record.city as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 7, (record.country as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 8, (record.cameraMake as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 9, (record.cameraModel as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 10, (record.lensModel as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 11, (record.fNumber as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 12, (record.focalLength as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 13, (record.iso as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 14, (record.exposureTime as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 15, (record.latitude as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 16, (record.longitude as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 17, (now as NSString).utf8String, -1, nil)

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

    func countQualifying(minDuration: Double, onlyFavorites: Bool) throws -> Int {
        try withDatabase { db in
            let sql = onlyFavorites
                ? "SELECT COUNT(*) FROM videos WHERE duration >= ? AND is_favorite = 1"
                : "SELECT COUNT(*) FROM videos WHERE duration >= ?"
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
                ? "SELECT asset_id, title, duration, is_favorite, capture_date, city, country, camera_make, camera_model, lens_model, f_number, focal_length, iso, exposure_time, latitude, longitude FROM videos WHERE duration >= ? AND is_favorite = 1 ORDER BY RANDOM() LIMIT 1"
                : "SELECT asset_id, title, duration, is_favorite, capture_date, city, country, camera_make, camera_model, lens_model, f_number, focal_length, iso, exposure_time, latitude, longitude FROM videos WHERE duration >= ? ORDER BY RANDOM() LIMIT 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw storeError(db, fallback: "prepare selectRandom failed")
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, minDuration)
            guard sqlite3_step(stmt) == SQLITE_ROW else {
                return nil
            }

            guard let idC = sqlite3_column_text(stmt, 0) else { return nil }
            let id = String(cString: idC)
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "Untitled"
            let duration = sqlite3_column_double(stmt, 2)
            let isFavorite = sqlite3_column_int(stmt, 3) == 1
            let captureDate = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            let city = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""
            let country = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
            let cameraMake = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? ""
            let cameraModel = sqlite3_column_text(stmt, 8).map { String(cString: $0) } ?? ""
            let lensModel = sqlite3_column_text(stmt, 9).map { String(cString: $0) } ?? ""
            let fNumber = sqlite3_column_text(stmt, 10).map { String(cString: $0) } ?? ""
            let focalLength = sqlite3_column_text(stmt, 11).map { String(cString: $0) } ?? ""
            let iso = sqlite3_column_text(stmt, 12).map { String(cString: $0) } ?? ""
            let exposureTime = sqlite3_column_text(stmt, 13).map { String(cString: $0) } ?? ""
            let latitude = sqlite3_column_text(stmt, 14).map { String(cString: $0) } ?? ""
            let longitude = sqlite3_column_text(stmt, 15).map { String(cString: $0) } ?? ""
            return VideoCandidate(
                id: id,
                title: title,
                duration: duration,
                isFavorite: isFavorite,
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

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK, let db else {
            throw NSError(domain: "SQLiteVideoStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot open sqlite DB at \(dbPath)"])
        }
        defer { sqlite3_close(db) }

        return try body(db)
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
