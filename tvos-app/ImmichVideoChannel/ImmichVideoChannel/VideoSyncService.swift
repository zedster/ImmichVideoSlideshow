import Foundation

struct SyncRunResult {
    let pagesFetched: Int
    let rowsUpserted: Int
}

@MainActor
final class VideoSyncService {
    private let client: ImmichAPIClient
    private let store: SQLiteVideoStore

    init(client: ImmichAPIClient, store: SQLiteVideoStore) {
        self.client = client
        self.store = store
    }

    func forceSync(
        config: AppConfig,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> SyncRunResult {
        try await store.initializeSchema()

        var pagesFetched = 0
        var rowsUpserted = 0

        let pageSize = max(1, min(config.syncPageSize, 1000))
        let maxPages = max(1, config.syncMaxPages)

        for page in 1...maxPages {
            let pageItems = try await client.fetchMetadataPage(config: config, page: page, size: pageSize)
            if pageItems.isEmpty {
                break
            }

            pagesFetched += 1
            rowsUpserted += try await store.upsert(records: pageItems)
            onProgress?(pagesFetched, rowsUpserted)
        }

        let now = ISO8601DateFormatter().string(from: Date())
        try await store.setSyncState(key: "last_sync_at", value: now)

        return SyncRunResult(pagesFetched: pagesFetched, rowsUpserted: rowsUpserted)
    }
}
