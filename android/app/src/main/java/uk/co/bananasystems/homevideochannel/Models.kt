package uk.co.bananasystems.homevideochannel

data class VideoCandidate(
    val id: String,
    val title: String,
    val duration: Double,
    val isFavorite: Boolean,
    val isHidden: Boolean,
    val timesWatched: Int,
    val captureDate: String,
    val city: String,
    val country: String,
    val cameraMake: String,
    val cameraModel: String,
    val lensModel: String,
    val fNumber: String,
    val focalLength: String,
    val iso: String,
    val exposureTime: String,
    val latitude: String,
    val longitude: String,
    val videoCodec: String = "",
    val fileType: String = ""
)

data class ImmichAssetRecord(
    val id: String,
    val title: String,
    val fileType: String,
    val videoCodec: String,
    val duration: Double,
    val isFavorite: Boolean,
    val captureDate: String,
    val city: String,
    val country: String,
    val cameraMake: String,
    val cameraModel: String,
    val lensModel: String,
    val fNumber: String,
    val focalLength: String,
    val iso: String,
    val exposureTime: String,
    val latitude: String,
    val longitude: String
)

data class VideoInfoField(
    val id: String,
    val label: String,
    val value: String
)

data class HiddenAlbumAccess(
    val canHide: Boolean,
    val albumId: String,
    val detail: String
)

data class LibraryStats(
    val totalVideos: Int = 0,
    val totalVideoDuration: Double = 0.0,
    val totalWatchedPlays: Int = 0,
    val totalWatchedDuration: Double = 0.0,
    val watchedPlays7Days: Int = 0,
    val watchedPlays30Days: Int = 0,
    val videosWatchedAtLeastOnce: Int = 0,
    val favoritesCount: Int = 0,
    val hiddenCount: Int = 0,
    val currentSessionWatched: Int = 0,
    val mostPopularCamera: String = "-",
    val mostPopularCodec: String = "-",
    val mostPopularFileType: String = "-",
    val mostPopularPlace: String = "-",
    val mostPopularYear: String = "-"
)
