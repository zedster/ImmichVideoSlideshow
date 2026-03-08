import AVFoundation
import Foundation

struct VideoCandidate: Equatable {
    let id: String
    let title: String
    let duration: Double
    let isFavorite: Bool
    let captureDate: String
    let city: String
    let country: String
    let cameraMake: String
    let cameraModel: String
    let lensModel: String
    let fNumber: String
    let focalLength: String
    let iso: String
    let exposureTime: String
    let latitude: String
    let longitude: String
}

extension VideoCandidate {
    func withFavorite(_ isFavorite: Bool) -> VideoCandidate {
        VideoCandidate(
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

struct ImmichAssetRecord: Equatable {
    let id: String
    let title: String
    let duration: Double
    let isFavorite: Bool
    let captureDate: String
    let city: String
    let country: String
    let cameraMake: String
    let cameraModel: String
    let lensModel: String
    let fNumber: String
    let focalLength: String
    let iso: String
    let exposureTime: String
    let latitude: String
    let longitude: String
}

enum ImmichAPIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case httpStatus(Int)
    case noEligibleVideo

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Invalid Immich URL"
        case .invalidResponse:
            return "Invalid API response"
        case .httpStatus(let code):
            return "Immich HTTP status \(code)"
        case .noEligibleVideo:
            return "No eligible video found"
        }
    }
}

final class ImmichAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchRandomEligibleVideo(config: AppConfig, maxAttempts: Int = 20) async throws -> VideoCandidate {
        var seen = Set<String>()
        for _ in 0..<maxAttempts {
            let batch = try await fetchRandomBatch(config: config, size: max(1, min(config.randomBatchSize, 200)))
            let shuffled = batch.shuffled()
            for item in shuffled {
                guard !seen.contains(item.id) else { continue }
                seen.insert(item.id)

                guard item.duration >= config.minDuration else { continue }
                if config.onlyFavorites && !item.isFavorite {
                    continue
                }

                return VideoCandidate(
                    id: item.id,
                    title: item.title,
                    duration: item.duration,
                    isFavorite: item.isFavorite,
                    captureDate: item.captureDate,
                    city: item.city,
                    country: item.country,
                    cameraMake: item.cameraMake,
                    cameraModel: item.cameraModel,
                    lensModel: item.lensModel,
                    fNumber: item.fNumber,
                    focalLength: item.focalLength,
                    iso: item.iso,
                    exposureTime: item.exposureTime,
                    latitude: item.latitude,
                    longitude: item.longitude
                )
            }
        }
        throw ImmichAPIError.noEligibleVideo
    }

    func fetchRandomBatch(config: AppConfig, size: Int) async throws -> [ImmichAssetRecord] {
        let items = try await searchMetadata(
            config: config,
            request: ImmichMetadataSearchRequest(
                type: "VIDEO",
                size: max(1, min(size, 200)),
                page: nil,
                random: true,
                withExif: true,
                withPeople: true
            )
        )
        return items.map(\.record)
    }

    func fetchMetadataPage(config: AppConfig, page: Int, size: Int) async throws -> [ImmichAssetRecord] {
        let items = try await searchMetadata(
            config: config,
            request: ImmichMetadataSearchRequest(
                type: "VIDEO",
                size: max(1, min(size, 1000)),
                page: page,
                random: nil,
                withExif: true,
                withPeople: true
            )
        )
        return items.map(\.record)
    }

    func makePlaybackItem(candidate: VideoCandidate, config: AppConfig) throws -> AVPlayerItem {
        guard let playbackURL = URL(string: "\(config.normalizedImmichBaseURL)/api/assets/\(candidate.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? candidate.id)/video/playback") else {
            throw ImmichAPIError.invalidBaseURL
        }

        let asset = AVURLAsset(
            url: playbackURL,
            options: ["AVURLAssetHTTPHeaderFieldsKey": [
                "x-api-key": config.apiKey,
                "Accept": "*/*"
            ]]
        )

        let item = AVPlayerItem(asset: asset)
        item.preferredPeakBitRate = config.playbackPeakBitRate
        return item
    }

    func updateFavorite(assetId: String, isFavorite: Bool, config: AppConfig) async throws {
        guard let url = URL(string: "\(config.normalizedImmichBaseURL)/api/assets/\(assetId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? assetId)") else {
            throw ImmichAPIError.invalidBaseURL
        }

        let methods = ["PUT", "PATCH", "POST"]
        let body = try JSONEncoder().encode(ImmichFavoriteUpdateRequest(isFavorite: isFavorite))
        var lastStatus: Int?

        for method in methods {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            request.timeoutInterval = 30
            request.httpBody = body

            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ImmichAPIError.invalidResponse
            }
            if 200..<300 ~= http.statusCode {
                return
            }
            lastStatus = http.statusCode
        }

        throw ImmichAPIError.httpStatus(lastStatus ?? -1)
    }

    private func searchMetadata(config: AppConfig, request body: ImmichMetadataSearchRequest) async throws -> [ImmichAssetItem] {
        guard let url = URL(string: "\(config.normalizedImmichBaseURL)/api/search/metadata") else {
            throw ImmichAPIError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ImmichAPIError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw ImmichAPIError.httpStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(ImmichMetadataSearchResponse.self, from: data)
        return decoded.assets.items
    }
}

private struct ImmichMetadataSearchRequest: Encodable {
    let type: String
    let size: Int
    let page: Int?
    let random: Bool?
    let withExif: Bool
    let withPeople: Bool
}

private struct ImmichFavoriteUpdateRequest: Encodable {
    let isFavorite: Bool
}

private struct ImmichMetadataSearchResponse: Decodable {
    let assets: ImmichAssetsPage
}

private struct ImmichAssetsPage: Decodable {
    let items: [ImmichAssetItem]
}

private struct ImmichAssetItem: Decodable {
    let id: String
    let durationRaw: DurationValue
    let isFavorite: Bool?
    let originalFileName: String?
    let exifInfo: ImmichExifInfo?
    let fileCreatedAt: String?
    let localDateTime: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case durationRaw = "duration"
        case isFavorite
        case originalFileName
        case exifInfo
        case fileCreatedAt
        case localDateTime
        case createdAt
    }

    var durationSeconds: Double { durationRaw.seconds }

    var captureDateValue: String {
        let candidates = [
            exifInfo?.dateTimeOriginal,
            exifInfo?.dateTime,
            fileCreatedAt,
            localDateTime,
            createdAt
        ]
        for candidate in candidates {
            let trimmed = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    var cityValue: String {
        (exifInfo?.city ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var countryValue: String {
        (exifInfo?.country ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var cameraMakeValue: String {
        (exifInfo?.make ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var cameraModelValue: String {
        (exifInfo?.model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var lensModelValue: String {
        (exifInfo?.lensModel?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var fNumberValue: String {
        (exifInfo?.fNumber?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var focalLengthValue: String {
        (exifInfo?.focalLength?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isoValue: String {
        (exifInfo?.iso?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var exposureTimeValue: String {
        (exifInfo?.exposureTime?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var latitudeValue: String {
        (exifInfo?.latitude?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var longitudeValue: String {
        (exifInfo?.longitude?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var record: ImmichAssetRecord {
        ImmichAssetRecord(
            id: id,
            title: originalFileName ?? "Untitled",
            duration: durationSeconds,
            isFavorite: isFavorite ?? false,
            captureDate: captureDateValue,
            city: cityValue,
            country: countryValue,
            cameraMake: cameraMakeValue,
            cameraModel: cameraModelValue,
            lensModel: lensModelValue,
            fNumber: fNumberValue,
            focalLength: focalLengthValue,
            iso: isoValue,
            exposureTime: exposureTimeValue,
            latitude: latitudeValue,
            longitude: longitudeValue
        )
    }
}

private struct ImmichExifInfo: Decodable {
    let dateTimeOriginal: String?
    let dateTime: String?
    let make: String?
    let model: String?
    let lensModel: FlexibleValue?
    let fNumber: FlexibleValue?
    let focalLength: FlexibleValue?
    let iso: FlexibleValue?
    let exposureTime: FlexibleValue?
    let latitude: FlexibleValue?
    let longitude: FlexibleValue?
    let city: String?
    let country: String?
}

private struct FlexibleValue: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let text = try? container.decode(String.self) {
            value = text
            return
        }
        if let number = try? container.decode(Double.self) {
            value = String(number)
            return
        }
        if let number = try? container.decode(Int.self) {
            value = String(number)
            return
        }
        if let flag = try? container.decode(Bool.self) {
            value = flag ? "true" : "false"
            return
        }
        value = ""
    }
}

private struct DurationValue: Decodable {
    let seconds: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let doubleValue = try? container.decode(Double.self) {
            self.seconds = doubleValue
            return
        }

        if let intValue = try? container.decode(Int.self) {
            self.seconds = Double(intValue)
            return
        }

        if let stringValue = try? container.decode(String.self) {
            self.seconds = Self.parseDuration(stringValue)
            return
        }

        self.seconds = 0
    }

    private static func parseDuration(_ value: String) -> Double {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let numeric = Double(trimmed) {
            return numeric
        }

        let parts = trimmed.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else {
            return 0
        }
        return (hours * 3600) + (minutes * 60) + seconds
    }
}
