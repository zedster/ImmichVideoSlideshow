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
        try Task.checkCancellation()
        try await store.initializeSchema()

        var pagesFetched = 0
        var rowsUpserted = 0

        let pageSize = max(1, min(config.syncPageSize, 1000))
        let maxPages = max(1, config.syncMaxPages)
        var syncedAssetIDs: [String] = []
        var peopleByID: [String: SyncedPersonRecord] = [:]

        for page in 1...maxPages {
            let pageItems = try await client.fetchMetadataPage(config: config, page: page, size: pageSize)
            try Task.checkCancellation()
            if pageItems.isEmpty {
                break
            }

            pagesFetched += 1
            rowsUpserted += try await store.upsert(records: pageItems.map(\.record))
            syncedAssetIDs.append(contentsOf: pageItems.map(\.record.id))

            for item in pageItems {
                for person in item.people {
                    let existing = peopleByID[person.id] ?? SyncedPersonRecord(id: person.id, name: person.name, assetIDs: [])
                    peopleByID[person.id] = SyncedPersonRecord(
                        id: existing.id,
                        name: existing.name,
                        assetIDs: existing.assetIDs + [item.record.id]
                    )
                }
            }
            try Task.checkCancellation()
            onProgress?(pagesFetched, rowsUpserted)
        }

        try Task.checkCancellation()
        try await store.refreshPeople(Array(peopleByID.values), replacingAssetIDs: syncedAssetIDs)

        if let albums = try? await client.fetchAlbumsWithVideoAssets(config: config) {
            try Task.checkCancellation()
            try await store.replaceAlbums(albums)
        }

        try Task.checkCancellation()
        let now = ISO8601DateFormatter().string(from: Date())
        try await store.setSyncState(key: "last_sync_at", value: now)

        return SyncRunResult(pagesFetched: pagesFetched, rowsUpserted: rowsUpserted)
    }
}
