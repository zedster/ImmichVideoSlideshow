package uk.co.bananasystems.homevideochannel

import android.os.Bundle
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.ui.PlayerView

class MainActivity : ComponentActivity() {
    private val viewModel: ChannelViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme {
                HomeVideoChannelApp(viewModel)
            }
        }
    }
}

@Composable
private fun HomeVideoChannelApp(viewModel: ChannelViewModel) {
    val state by viewModel.uiState.collectAsState()

    Scaffold { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.linearGradient(
                        listOf(
                            Color(0xFF07111C),
                            Color(0xFF112736),
                            Color(0xFF24130F)
                        )
                    )
                )
                .padding(padding)
        ) {
            PlayerSurface(viewModel = viewModel)
            PlaybackOverlay(state = state, viewModel = viewModel)

            if (state.setupVisible || !state.config.isConfigured) {
                SetupScreen(
                    initial = state.config,
                    onSave = viewModel::saveConfig,
                    onCancel = viewModel::hideSetup,
                    onForceSync = viewModel::forceSync,
                    onRefreshStats = viewModel::refreshStats,
                    onResetPlayback = viewModel::resetPlaybackProgress,
                    stats = state.stats
                )
            }

            if (state.infoVisible) {
                AlertDialog(
                    onDismissRequest = viewModel::toggleInfo,
                    title = { Text("Video Info") },
                    text = {
                        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            items(state.infoFields) { field ->
                                Column {
                                    Text(field.label, fontWeight = FontWeight.Bold)
                                    Text(field.value)
                                }
                            }
                        }
                    },
                    confirmButton = {
                        TextButton(onClick = viewModel::toggleInfo) { Text("Close") }
                    }
                )
            }
        }
    }
}

@Composable
private fun PlayerSurface(viewModel: ChannelViewModel) {
    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { context ->
            PlayerView(context).apply {
                layoutParams = android.view.ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
                useController = false
                player = viewModel.player
            }
        },
        update = { it.player = viewModel.player }
    )
}

@Composable
private fun PlaybackOverlay(state: ChannelUiState, viewModel: ChannelViewModel) {
    Box(modifier = Modifier.fillMaxSize()) {
        if (state.fallbackMessage.isNotBlank()) {
            Text(
                text = state.fallbackMessage,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 24.dp)
                    .background(Color(0xAA7A1010))
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                color = Color.White
            )
        }

        if (state.config.showDateLocationOverlay && state.dateLocationText.isNotBlank()) {
            Text(
                text = state.dateLocationText,
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(start = 24.dp, bottom = 120.dp)
                    .background(Color(0x99000000))
                    .padding(horizontal = 14.dp, vertical = 8.dp),
                color = Color.White
            )
        }

        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .background(Color(0x88000000))
                .padding(20.dp)
        ) {
            if (state.title.isNotBlank()) {
                Text(
                    state.title,
                    color = Color.White,
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.padding(bottom = 8.dp)
                )
            }
            if (state.captionText.isNotBlank()) {
                Text(state.captionText, color = Color.White, modifier = Modifier.padding(bottom = 10.dp))
            }
            if (state.config.debug && state.debugText.isNotBlank()) {
                Text(state.debugText, color = Color(0xFFE0E0E0), modifier = Modifier.padding(bottom = 10.dp))
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = viewModel::togglePlayPause) {
                    Icon(
                        imageVector = if (viewModel.player.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                        contentDescription = "Play Pause",
                        tint = Color.White
                    )
                }
                IconButton(onClick = viewModel::skip) {
                    Icon(Icons.Default.SkipNext, contentDescription = "Skip", tint = Color.White)
                }
                IconButton(onClick = viewModel::toggleFavorite) {
                    Icon(
                        imageVector = if (state.currentIsFavorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                        contentDescription = "Favorite",
                        tint = Color.White
                    )
                }
                IconButton(onClick = viewModel::hideCurrentVideo, enabled = state.canHideToAlbum) {
                    Icon(Icons.Default.VisibilityOff, contentDescription = "Hide", tint = Color.White)
                }
                IconButton(onClick = viewModel::toggleInfo) {
                    Icon(Icons.Default.Info, contentDescription = "Info", tint = Color.White)
                }
                IconButton(onClick = viewModel::showSetup) {
                    Icon(Icons.Default.Settings, contentDescription = "Settings", tint = Color.White)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SetupScreen(
    initial: AppConfig,
    onSave: (AppConfig) -> Unit,
    onCancel: () -> Unit,
    onForceSync: () -> Unit,
    onRefreshStats: () -> Unit,
    onResetPlayback: () -> Unit,
    stats: LibraryStats
) {
    var immichUrl by remember(initial) { mutableStateOf(initial.immichUrl) }
    var apiKey by remember(initial) { mutableStateOf(initial.apiKey) }
    var minDuration by remember(initial) { mutableStateOf(initial.minDuration.toString()) }
    var randomBatchSize by remember(initial) { mutableStateOf(initial.randomBatchSize.toString()) }
    var syncPageSize by remember(initial) { mutableStateOf(initial.syncPageSize.toString()) }
    var syncMaxPages by remember(initial) { mutableStateOf(initial.syncMaxPages.toString()) }
    var onlyFavorites by remember(initial) { mutableStateOf(initial.onlyFavorites) }
    var debug by remember(initial) { mutableStateOf(initial.debug) }
    var useCache by remember(initial) { mutableStateOf(initial.useSQLiteCache) }
    var syncOnStartup by remember(initial) { mutableStateOf(initial.syncOnStartup) }
    var showOverlay by remember(initial) { mutableStateOf(initial.showDateLocationOverlay) }
    var playbackOrder by remember(initial) { mutableStateOf(initial.playbackOrder) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xD0141C26))
            .padding(28.dp)
    ) {
        LazyColumn(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            item {
                Text("Home Video Channel Setup", style = MaterialTheme.typography.headlineMedium, color = Color.White)
                Text("Android feature copy of the tvOS app", color = Color(0xFFD0D5DB))
            }
            item {
                Card {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        OutlinedTextField(value = immichUrl, onValueChange = { immichUrl = it }, label = { Text("Immich URL") }, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(value = apiKey, onValueChange = { apiKey = it }, label = { Text("API key") }, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(value = minDuration, onValueChange = { minDuration = it }, label = { Text("Min duration (seconds)") }, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(value = randomBatchSize, onValueChange = { randomBatchSize = it }, label = { Text("Random batch size") }, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(value = syncPageSize, onValueChange = { syncPageSize = it }, label = { Text("Sync page size") }, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(value = syncMaxPages, onValueChange = { syncMaxPages = it }, label = { Text("Sync max pages") }, modifier = Modifier.fillMaxWidth())

                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(checked = onlyFavorites, onCheckedChange = { onlyFavorites = it })
                            Text("Only favorites")
                        }
                        ToggleRow("Debug mode", debug) { debug = it }
                        ToggleRow("Use SQLite cache", useCache) { useCache = it }
                        ToggleRow("Sync on startup", syncOnStartup) { syncOnStartup = it }
                        ToggleRow("Show date/location overlay", showOverlay) { showOverlay = it }

                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            TextButton(onClick = { playbackOrder = "random" }) { Text(if (playbackOrder == "random") "Random *" else "Random") }
                            TextButton(onClick = { playbackOrder = "sequential_oldest" }) { Text(if (playbackOrder == "sequential_oldest") "Oldest *" else "Oldest") }
                            TextButton(onClick = { playbackOrder = "sequential_newest" }) { Text(if (playbackOrder == "sequential_newest") "Newest *" else "Newest") }
                        }

                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Button(onClick = {
                                onSave(
                                    AppConfig(
                                        immichUrl = immichUrl,
                                        apiKey = apiKey,
                                        minDuration = minDuration.toDoubleOrNull() ?: 10.0,
                                        randomBatchSize = randomBatchSize.toIntOrNull() ?: 20,
                                        onlyFavorites = onlyFavorites,
                                        debug = debug,
                                        useSQLiteCache = useCache,
                                        syncOnStartup = syncOnStartup,
                                        showDateLocationOverlay = showOverlay,
                                        syncPageSize = syncPageSize.toIntOrNull() ?: 200,
                                        syncMaxPages = syncMaxPages.toIntOrNull() ?: 200,
                                        playbackOrder = playbackOrder
                                    )
                                )
                            }) {
                                Text("Save and Start")
                            }
                            TextButton(onClick = onCancel) { Text("Close") }
                            TextButton(onClick = onForceSync) { Text("Sync Now") }
                            TextButton(onClick = onResetPlayback) { Text("Reset Playback") }
                            TextButton(onClick = onRefreshStats) { Text("Refresh Stats") }
                        }
                    }
                }
            }
            item {
                Card {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("Library Stats", fontWeight = FontWeight.Bold)
                        Text("Videos: ${stats.totalVideos}")
                        Text("Watched plays: ${stats.totalWatchedPlays}")
                        Text("Favorites: ${stats.favoritesCount}")
                        Text("Hidden: ${stats.hiddenCount}")
                        Text("Most used camera: ${stats.mostPopularCamera}")
                        Text("Most used codec: ${stats.mostPopularCodec}")
                        Text("Most used file type: ${stats.mostPopularFileType}")
                        Text("Most common place: ${stats.mostPopularPlace}")
                        Text("Most common year: ${stats.mostPopularYear}")
                    }
                }
            }
        }
    }
}

@Composable
private fun ToggleRow(label: String, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label)
        Switch(checked = value, onCheckedChange = onChange)
    }
}
