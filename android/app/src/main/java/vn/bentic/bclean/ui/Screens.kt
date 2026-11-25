@file:OptIn(ExperimentalMaterial3Api::class)

package vn.bentic.bclean.ui

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Compress
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Swipe
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material.icons.outlined.BlurOn
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Collections
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.launch
import vn.bentic.bclean.BuildConfig
import vn.bentic.bclean.R
import vn.bentic.bclean.core.AppConfig
import vn.bentic.bclean.core.CleanCategory
import vn.bentic.bclean.core.CompressionLevel
import vn.bentic.bclean.core.Fmt
import vn.bentic.bclean.core.MediaEntry
import vn.bentic.bclean.core.MediaGroup
import java.util.Calendar

// region Điều hướng

sealed interface Route {
    data class Category(val category: CleanCategory) : Route
    data class SwipeSession(val key: String, val title: String, val items: List<MediaEntry>) : Route
    data class Compress(val entry: MediaEntry) : Route
    data object Tips : Route
}

@Composable
fun AppRoot(vm: AppViewModel) {
    val state by vm.state.collectAsState()
    var onboarded by remember { mutableStateOf(vm.onboarded) }
    val stack = remember { mutableStateListOf<Route>() }

    val deleteLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { res ->
        vm.onDeleteResult(res.resultCode == Activity.RESULT_OK)
    }
    val requestDelete: (List<MediaEntry>) -> Unit = { items ->
        vm.prepareDelete(items)?.let { deleteLauncher.launch(IntentSenderRequest.Builder(it).build()) }
    }

    BackHandler(enabled = stack.isNotEmpty()) { stack.removeAt(stack.lastIndex) }

    when {
        !onboarded -> OnboardingScreen { vm.onboarded = true; onboarded = true }
        state.access == Access.NONE -> PermissionScreen(vm)
        stack.isEmpty() -> MainTabs(vm, state, requestDelete) { stack.add(it) }
        else -> when (val r = stack.last()) {
            is Route.Category -> CategoryScreen(r.category, state, vm, requestDelete,
                onBack = { stack.removeAt(stack.lastIndex) }, onCompress = { stack.add(Route.Compress(it)) })
            is Route.SwipeSession -> SwipeSessionScreen(r, requestDelete) { stack.removeAt(stack.lastIndex) }
            is Route.Compress -> CompressScreen(r.entry, vm, state,
                onDeleteOriginal = { sender -> deleteLauncher.launch(IntentSenderRequest.Builder(sender).build()) }) {
                vm.clearCompressResult()
                stack.removeAt(stack.lastIndex)
            }
            Route.Tips -> TipsScreen { stack.removeAt(stack.lastIndex) }
        }
    }

    if (state.showPaywall) PaywallDialog(vm, state)

    state.message?.let { msg ->
        AlertDialog(
            onDismissRequest = vm::consumeMessage,
            confirmButton = { TextButton(onClick = vm::consumeMessage) { Text(stringResource(R.string.ok)) } },
            title = { Text(stringResource(R.string.done_title)) },
            text = { Text(msg) },
        )
    }
}

@Composable
private fun BackTopBar(title: String, onBack: () -> Unit, actions: @Composable () -> Unit = {}) {
    TopAppBar(
        title = { Text(title, maxLines = 1) },
        navigationIcon = {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.close)) }
        },
        actions = { actions() },
    )
}

// endregion

// region Onboarding & quyền

@Composable
fun OnboardingScreen(onDone: () -> Unit) {
    val pages = listOf(
        Triple(Icons.Filled.AutoAwesome, R.string.onb1_title, R.string.onb1_body),
        Triple(Icons.Filled.Lock, R.string.onb2_title, R.string.onb2_body),
        Triple(Icons.Filled.Swipe, R.string.onb3_title, R.string.onb3_body),
    )
    val pager = rememberPagerState { pages.size }
    val scope = rememberCoroutineScope()
    Scaffold { pad ->
        Column(Modifier.fillMaxSize().padding(pad).padding(24.dp)) {
            HorizontalPager(pager, modifier = Modifier.weight(1f)) { i ->
                Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                    Icon(pages[i].first, null, tint = BColors.teal, modifier = Modifier.size(96.dp))
                    Spacer(Modifier.height(24.dp))
                    Text(stringResource(pages[i].second), fontSize = 28.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(12.dp))
                    Text(stringResource(pages[i].third), style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                }
            }
            Row(Modifier.fillMaxWidth().padding(vertical = 16.dp), horizontalArrangement = Arrangement.Center) {
                repeat(pages.size) { i ->
                    Box(Modifier.padding(4.dp).size(8.dp).clip(CircleShape)
                        .background(if (pager.currentPage == i) BColors.teal else Color.LightGray))
                }
            }
            val last = pager.currentPage == pages.size - 1
            PrimaryButton(stringResource(if (last) R.string.get_started else R.string.continue_label), onClick = {
                if (last) { Analytics.log("onboarding_done"); onDone() }
                else scope.launch { pager.animateScrollToPage(pager.currentPage + 1) }
            })
        }
    }
}

@Composable
fun PermissionScreen(vm: AppViewModel) {
    val context = LocalContext.current
    var asked by rememberSaveable { mutableStateOf(false) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        asked = true
        vm.refreshAccess()
    }
    Scaffold { pad ->
        Column(
            Modifier.fillMaxSize().padding(pad).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.weight(1f))
            Icon(Icons.Filled.PhotoLibrary, null, tint = BColors.teal, modifier = Modifier.size(88.dp))
            Spacer(Modifier.height(20.dp))
            Text(stringResource(R.string.perm_title), fontSize = 26.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
            Spacer(Modifier.height(12.dp))
            Text(stringResource(R.string.perm_body), textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(12.dp))
            Text(stringResource(R.string.perm_privacy), color = BColors.teal, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
            Spacer(Modifier.weight(1f))
            if (asked) {
                Text(stringResource(R.string.perm_denied), textAlign = TextAlign.Center, style = MaterialTheme.typography.bodySmall)
                Spacer(Modifier.height(8.dp))
                SecondaryButton(stringResource(R.string.open_settings), onClick = {
                    context.startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)))
                })
                Spacer(Modifier.height(8.dp))
            }
            PrimaryButton(stringResource(R.string.perm_allow), onClick = { launcher.launch(vm.permissionsToRequest()) })
        }
    }
}

// endregion

// region Tabs & Dashboard

@Composable
fun MainTabs(vm: AppViewModel, state: UiState, requestDelete: (List<MediaEntry>) -> Unit, navigate: (Route) -> Unit) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    Scaffold(
        bottomBar = {
            NavigationBar {
                val tabs = listOf(
                    Triple(Icons.Filled.AutoAwesome, R.string.tab_clean, 0),
                    Triple(Icons.Filled.Swipe, R.string.tab_swipe, 1),
                    Triple(Icons.Filled.Movie, R.string.tab_videos, 2),
                    Triple(Icons.Filled.Settings, R.string.tab_settings, 3),
                )
                tabs.forEach { (icon, label, idx) ->
                    NavigationBarItem(selected = tab == idx, onClick = { tab = idx },
                        icon = { Icon(icon, null) }, label = { Text(stringResource(label)) })
                }
            }
        },
    ) { pad ->
        Box(Modifier.padding(pad)) {
            when (tab) {
                0 -> DashboardScreen(vm, state, navigate)
                1 -> SwipeMonthsScreen(vm, navigate)
                2 -> Column {
                    TopAppBar(title = { Text(stringResource(R.string.cat_videos)) })
                    VideoList(state, requestDelete) { navigate(Route.Compress(it)) }
                }
                else -> SettingsScreen(vm, state, navigate)
            }
        }
    }
}

private fun categoryIcon(c: CleanCategory): ImageVector = when (c) {
    CleanCategory.DUPLICATES -> Icons.Outlined.ContentCopy
    CleanCategory.SIMILAR -> Icons.Outlined.Collections
    CleanCategory.SCREENSHOTS -> Icons.Outlined.PhoneAndroid
    CleanCategory.BLURRY -> Icons.Outlined.BlurOn
    CleanCategory.VIDEOS -> Icons.Outlined.Movie
}

@Composable
fun DashboardScreen(vm: AppViewModel, state: UiState, navigate: (Route) -> Unit) {
    LaunchedEffect(Unit) { vm.startScanIfNeeded() }
    val scanned = state.result.scannedAt > 0
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        contentPadding = PaddingValues(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background),
    ) {
        item(span = { GridItemSpan(2) }) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Bclean", fontSize = 32.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                if (scanned && !state.scanning) {
                    IconButton(onClick = vm::startScan) { Icon(Icons.Filled.Refresh, stringResource(R.string.scan_again)) }
                }
            }
        }
        item(span = { GridItemSpan(2) }) { StorageCard(state, scanned) }
        if (state.access == Access.PARTIAL) {
            item(span = { GridItemSpan(2) }) {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        Text(stringResource(R.string.limited_title), fontWeight = FontWeight.Bold)
                        Text(stringResource(R.string.limited_body), style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
        item(span = { GridItemSpan(2) }) {
            if (state.scanning) {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        Row {
                            Text(stringResource(R.string.scanning), fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                            Text("${(state.progress * 100).toInt()}%", fontWeight = FontWeight.Bold)
                        }
                        Spacer(Modifier.height(8.dp))
                        LinearProgressIndicator(progress = { state.progress }, modifier = Modifier.fillMaxWidth())
                        Spacer(Modifier.height(6.dp))
                        Text(state.progressText, style = MaterialTheme.typography.bodySmall)
                        Text(stringResource(R.string.scan_private_note), style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            } else if (!scanned) {
                PrimaryButton(stringResource(R.string.scan_start), onClick = vm::startScan)
            }
        }
        items(CleanCategory.entries.toList()) { c ->
            CategoryCard(c, state) { if (!state.scanning) navigate(Route.Category(c)) }
        }
        if (!state.isPro) {
            item(span = { GridItemSpan(2) }) {
                Card(Modifier.fillMaxWidth().clickable { vm.showPaywall(null) }) {
                    Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.WorkspacePremium, null, tint = Color(0xFFFFB300), modifier = Modifier.size(32.dp))
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(stringResource(R.string.pro_banner_title), fontWeight = FontWeight.Bold)
                            Text(stringResource(R.string.pro_banner_body, vm.deletesQuota.remaining), style = MaterialTheme.typography.bodySmall)
                        }
                        Icon(Icons.Filled.ChevronRight, null)
                    }
                }
            }
        }
        if (state.freedBytes > 0) {
            item(span = { GridItemSpan(2) }) {
                Text(stringResource(R.string.stats_freed, Fmt.bytes(state.freedBytes), state.deletedCount),
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun StorageCard(state: UiState, scanned: Boolean) {
    val used = state.storageTotal - state.storageFree
    val fraction = if (state.storageTotal > 0) used.toFloat() / state.storageTotal else 0f
    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(BColors.gradient).padding(20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(contentAlignment = Alignment.Center, modifier = Modifier.size(96.dp)) {
                CircularProgressIndicator(progress = { fraction }, modifier = Modifier.fillMaxSize(),
                    color = Color.White, trackColor = Color.White.copy(alpha = 0.25f), strokeWidth = 10.dp)
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("${(fraction * 100).toInt()}%", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 22.sp)
                    Text(stringResource(R.string.used), color = Color.White, fontSize = 11.sp)
                }
            }
            Spacer(Modifier.width(20.dp))
            Column {
                Text(stringResource(R.string.storage_used, Fmt.bytes(used), Fmt.bytes(state.storageTotal)),
                    color = Color.White, fontWeight = FontWeight.SemiBold)
                Text(stringResource(R.string.storage_free, Fmt.bytes(state.storageFree)), color = Color.White.copy(alpha = 0.9f), fontSize = 13.sp)
                HorizontalDivider(Modifier.padding(vertical = 8.dp), color = Color.White.copy(alpha = 0.4f))
                Text(stringResource(if (scanned) R.string.can_free else R.string.scan_to_find), color = Color.White.copy(alpha = 0.9f), fontSize = 13.sp)
                if (scanned) {
                    Text(Fmt.bytes(state.result.headlineReclaimable), color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun CategoryCard(c: CleanCategory, state: UiState, onClick: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Column(Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(40.dp).clip(RoundedCornerShape(12.dp)).background(c.color().copy(alpha = 0.14f)),
                    contentAlignment = Alignment.Center) {
                    Icon(categoryIcon(c), null, tint = c.color())
                }
                Spacer(Modifier.weight(1f))
                if (state.scanning) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
            }
            Spacer(Modifier.height(10.dp))
            Text(stringResource(c.titleRes()), fontWeight = FontWeight.Bold, maxLines = 1)
            Text(
                if (state.scanning) " " else stringResource(R.string.cat_count, state.result.count(c), Fmt.bytes(state.result.reclaimable(c))),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
            )
        }
    }
}

// endregion

// region Danh mục

@Composable
fun CategoryScreen(
    category: CleanCategory,
    state: UiState,
    vm: AppViewModel,
    requestDelete: (List<MediaEntry>) -> Unit,
    onBack: () -> Unit,
    onCompress: (MediaEntry) -> Unit,
) {
    Scaffold(topBar = { BackTopBar(stringResource(category.titleRes()), onBack) }) { pad ->
        Box(Modifier.padding(pad)) {
            when {
                category == CleanCategory.VIDEOS -> VideoList(state, requestDelete, onCompress)
                category.isGrouped -> GroupedList(category, state, requestDelete)
                else -> MediaGrid(category, state, requestDelete)
            }
        }
    }
}

@Composable
private fun MediaGrid(category: CleanCategory, state: UiState, requestDelete: (List<MediaEntry>) -> Unit) {
    val items = state.result.items(category)
    var selected by remember { mutableStateOf(setOf<Long>()) }
    LaunchedEffect(items) { selected = selected.intersect(items.map { it.id }.toSet()) }
    if (items.isEmpty()) {
        EmptyState(Icons.Filled.CheckCircle, stringResource(R.string.empty_title), stringResource(R.string.empty_body))
        return
    }
    Column(Modifier.fillMaxSize()) {
        LazyVerticalGrid(
            columns = GridCells.Fixed(3),
            contentPadding = PaddingValues(4.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.weight(1f),
        ) {
            item(span = { GridItemSpan(3) }) {
                Row(Modifier.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(category.subtitleRes()), style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                    TextButton(onClick = {
                        selected = if (selected.size == items.size) emptySet() else items.map { it.id }.toSet()
                    }) { Text(stringResource(if (selected.size == items.size) R.string.deselect_all else R.string.select_all)) }
                }
            }
            items(items, key = { it.id }) { e ->
                MediaCell(e, e.id in selected, Modifier.clickable {
                    selected = if (e.id in selected) selected - e.id else selected + e.id
                })
            }
        }
        if (selected.isNotEmpty()) {
            val chosen = items.filter { it.id in selected }
            SelectionBar(chosen.size, chosen.sumOf { it.bytes }) { requestDelete(chosen) }
        }
    }
}

@Composable
private fun GroupedList(category: CleanCategory, state: UiState, requestDelete: (List<MediaEntry>) -> Unit) {
    val groups = state.result.groups(category)
    var selected by remember(category) { mutableStateOf(groups.flatMap { g -> g.items.drop(1).map { it.id } }.toSet()) }
    LaunchedEffect(groups) {
        val alive = groups.flatMap { g -> g.items.map { it.id } }.toSet()
        selected = selected.intersect(alive)
    }
    if (groups.isEmpty()) {
        EmptyState(Icons.Filled.CheckCircle, stringResource(R.string.empty_title), stringResource(R.string.empty_body))
        return
    }
    Column(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            item {
                Text(stringResource(category.subtitleRes()) + " " + stringResource(R.string.group_hint),
                    style = MaterialTheme.typography.bodySmall)
            }
            items(groups, key = { it.best.id }) { g -> GroupCard(g, selected) { selected = it } }
        }
        if (selected.isNotEmpty()) {
            val chosen = groups.flatMap { it.items }.filter { it.id in selected }
            SelectionBar(chosen.size, chosen.sumOf { it.bytes }) { requestDelete(chosen) }
        }
    }
}

@Composable
private fun GroupCard(group: MediaGroup, selected: Set<Long>, onChange: (Set<Long>) -> Unit) {
    val others = group.items.drop(1).map { it.id }
    val allSelected = others.all { it in selected }
    Card(shape = RoundedCornerShape(16.dp)) {
        Column(Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.group_header, group.items.size, Fmt.date(group.best.dateTaken)),
                    fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                TextButton(onClick = { onChange(if (allSelected) selected - others.toSet() else selected + others) }) {
                    Text(stringResource(if (allSelected) R.string.deselect else R.string.select))
                }
            }
            LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                itemsIndexed(group.items, key = { _, e -> e.id }) { i, e ->
                    MediaCell(
                        e, e.id in selected,
                        Modifier.width(112.dp).clickable { onChange(if (e.id in selected) selected - e.id else selected + e.id) },
                        badge = if (i == 0) stringResource(R.string.best) else null,
                    )
                }
            }
        }
    }
}

@Composable
fun VideoList(state: UiState, requestDelete: (List<MediaEntry>) -> Unit, onCompress: (MediaEntry) -> Unit) {
    val videos = state.result.videos
    var selected by remember { mutableStateOf(setOf<Long>()) }
    LaunchedEffect(videos) { selected = selected.intersect(videos.map { it.id }.toSet()) }
    if (videos.isEmpty()) {
        if (state.scanning) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        else EmptyState(Icons.Outlined.Movie, stringResource(R.string.videos_empty_title), stringResource(R.string.videos_empty_body))
        return
    }
    Column(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.weight(1f)) {
            item {
                Text(
                    stringResource(R.string.videos_header, videos.size, Fmt.bytes(videos.sumOf { it.bytes })) + "\n" +
                        stringResource(R.string.videos_footer),
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(16.dp),
                )
            }
            items(videos, key = { it.id }) { v ->
                val isSel = v.id in selected
                Row(
                    Modifier.fillMaxWidth().clickable { selected = if (isSel) selected - v.id else selected + v.id }
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(if (isSel) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                        null, tint = if (isSel) BColors.danger else MaterialTheme.colorScheme.outline)
                    Spacer(Modifier.width(12.dp))
                    Thumbnail(v.uri, Modifier.size(64.dp).clip(RoundedCornerShape(8.dp)))
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(Fmt.bytes(v.bytes), fontWeight = FontWeight.Bold)
                        Text("${Fmt.duration(v.durationMs)} · ${Fmt.date(v.dateTaken)}", style = MaterialTheme.typography.bodySmall)
                    }
                    IconButton(onClick = { onCompress(v) }) {
                        Icon(Icons.Filled.Compress, stringResource(R.string.compress), tint = BColors.teal)
                    }
                }
            }
        }
        if (selected.isNotEmpty()) {
            val chosen = videos.filter { it.id in selected }
            SelectionBar(chosen.size, chosen.sumOf { it.bytes }) { requestDelete(chosen) }
        }
    }
}

// endregion

// region Nén video

@Composable
fun CompressScreen(
    entry: MediaEntry,
    vm: AppViewModel,
    state: UiState,
    onDeleteOriginal: (android.content.IntentSender) -> Unit,
    onBack: () -> Unit,
) {
    var level by remember { mutableStateOf(CompressionLevel.BALANCED) }
    var deleteOriginal by remember { mutableStateOf(true) }
    val scope = rememberCoroutineScope()
    val working = state.compressProgress != null
    Scaffold(topBar = { BackTopBar(stringResource(R.string.compress_title), { if (!working) onBack() }) }) { pad ->
        Column(Modifier.padding(pad).padding(16.dp).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Thumbnail(entry.uri, Modifier.size(90.dp).clip(RoundedCornerShape(10.dp)))
                Spacer(Modifier.width(12.dp))
                Column {
                    Text(stringResource(R.string.original, Fmt.bytes(entry.bytes)), fontWeight = FontWeight.Bold)
                    Text("${entry.width}×${entry.height} · ${Fmt.duration(entry.durationMs)}", style = MaterialTheme.typography.bodySmall)
                }
            }
            Text(stringResource(R.string.compress_level), fontWeight = FontWeight.SemiBold)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CompressionLevel.entries.forEach { l ->
                    FilterChip(selected = level == l, onClick = { level = l }, label = { Text(stringResource(levelTitle(l))) })
                }
            }
            Text(stringResource(levelDetail(level)), style = MaterialTheme.typography.bodySmall)
            Row {
                Text(stringResource(R.string.estimated_after), modifier = Modifier.weight(1f))
                Text("~" + Fmt.bytes(level.estimate(entry)), fontWeight = FontWeight.Bold)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.delete_original), modifier = Modifier.weight(1f))
                Switch(checked = deleteOriginal, onCheckedChange = { deleteOriginal = it }, enabled = !working)
            }
            Text(stringResource(R.string.compress_footer), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            state.compressProgress?.let { p ->
                Text(stringResource(R.string.compressing))
                LinearProgressIndicator(progress = { p }, modifier = Modifier.fillMaxWidth())
            }
            state.compressResult?.let { Text(it, color = BColors.teal, fontWeight = FontWeight.SemiBold) }
            Spacer(Modifier.weight(1f))
            PrimaryButton(
                stringResource(if (state.compressResult == null) R.string.compress_now else R.string.done),
                enabled = !working,
                onClick = {
                    if (state.compressResult != null) onBack()
                    else scope.launch {
                        vm.compress(entry, level, deleteOriginal)?.let(onDeleteOriginal)
                    }
                },
            )
        }
    }
}

private fun levelTitle(l: CompressionLevel) = when (l) {
    CompressionLevel.LIGHT -> R.string.compress_light
    CompressionLevel.BALANCED -> R.string.compress_balanced
    CompressionLevel.STRONG -> R.string.compress_strong
}

private fun levelDetail(l: CompressionLevel) = when (l) {
    CompressionLevel.LIGHT -> R.string.compress_light_detail
    CompressionLevel.BALANCED -> R.string.compress_balanced_detail
    CompressionLevel.STRONG -> R.string.compress_strong_detail
}

// endregion

// region Lướt ảnh

private data class Month(val key: String, val title: String, val items: List<MediaEntry>)

@Composable
fun SwipeMonthsScreen(vm: AppViewModel, navigate: (Route) -> Unit) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("bclean_swipe", android.content.Context.MODE_PRIVATE) }
    var months by remember { mutableStateOf<List<Month>?>(null) }
    LaunchedEffect(Unit) {
        val all = vm.loadAllForSwipe()
        val cal = Calendar.getInstance()
        months = all.groupBy {
            cal.timeInMillis = it.dateTaken
            "%04d-%02d".format(cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1)
        }.map { (k, v) -> Month(k, Fmt.month(v.first().dateTaken), v) }
    }
    Column(Modifier.fillMaxSize()) {
        TopAppBar(title = { Text(stringResource(R.string.tab_swipe)) })
        val list = months
        when {
            list == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            list.isEmpty() -> EmptyState(Icons.Filled.PhotoLibrary, stringResource(R.string.swipe_empty_title), stringResource(R.string.swipe_empty_body))
            else -> LazyColumn {
                item { Text(stringResource(R.string.swipe_header), style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(16.dp)) }
                items(list, key = { it.key }) { m ->
                    val done = prefs.getInt(m.key, 0).coerceAtMost(m.items.size)
                    ListItem(
                        modifier = Modifier.clickable { navigate(Route.SwipeSession(m.key, m.title, m.items)) },
                        leadingContent = { Thumbnail(m.items.first().uri, Modifier.size(52.dp).clip(RoundedCornerShape(8.dp))) },
                        headlineContent = { Text(m.title, fontWeight = FontWeight.Bold) },
                        supportingContent = { Text(stringResource(R.string.swipe_month_count, m.items.size)) },
                        trailingContent = {
                            if (done >= m.items.size) Icon(Icons.Filled.CheckCircle, null, tint = BColors.teal)
                            else if (done > 0) Text("$done/${m.items.size}", style = MaterialTheme.typography.bodySmall)
                        },
                    )
                }
            }
        }
    }
}

@Composable
fun SwipeSessionScreen(route: Route.SwipeSession, requestDelete: (List<MediaEntry>) -> Unit, onBack: () -> Unit) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("bclean_swipe", android.content.Context.MODE_PRIVATE) }
    val items = route.items
    var index by remember { mutableIntStateOf(prefs.getInt(route.key, 0).let { if (it >= items.size) 0 else it }) }
    val marked = remember { mutableStateListOf<MediaEntry>() }
    val history = remember { mutableStateListOf<Boolean>() }
    var offsetX by remember { mutableFloatStateOf(0f) }
    var review by remember { mutableStateOf(false) }
    val finished = index >= items.size

    fun decide(delete: Boolean) {
        if (finished) return
        if (delete) marked.add(items[index])
        history.add(delete)
        index++
        offsetX = 0f
    }

    fun undo() {
        if (history.isEmpty() || index == 0) return
        if (history.removeAt(history.lastIndex)) marked.removeAt(marked.lastIndex)
        index--
    }

    fun saveProgress() { prefs.edit().putInt(route.key, index).apply() }

    Scaffold(topBar = { BackTopBar(route.title, { saveProgress(); onBack() }) }) { pad ->
        Column(Modifier.padding(pad).fillMaxSize().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            LinearProgressIndicator(progress = { if (items.isEmpty()) 1f else index.toFloat() / items.size }, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(6.dp))
            Text("${minOf(index + 1, items.size)} / ${items.size} · " + stringResource(R.string.marked, marked.size),
                style = MaterialTheme.typography.bodySmall)
            Spacer(Modifier.height(12.dp))
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                if (finished) {
                    EmptyState(Icons.Filled.CheckCircle, stringResource(R.string.swipe_finished_title),
                        if (marked.isEmpty()) stringResource(R.string.swipe_finished_none) else stringResource(R.string.swipe_finished_body, marked.size))
                } else {
                    val e = items[index]
                    Box(
                        Modifier.fillMaxSize()
                            .graphicsLayer { translationX = offsetX; rotationZ = offsetX / 40f }
                            .clip(RoundedCornerShape(24.dp))
                            .background(MaterialTheme.colorScheme.surfaceVariant)
                            .pointerInput(index) {
                                detectDragGestures(
                                    onDragEnd = {
                                        when {
                                            offsetX < -280f -> decide(true)
                                            offsetX > 280f -> decide(false)
                                            else -> offsetX = 0f
                                        }
                                    },
                                ) { change, drag ->
                                    change.consume()
                                    offsetX += drag.x
                                }
                            },
                    ) {
                        Thumbnail(e.uri, Modifier.fillMaxSize(), side = 1080, crop = false)
                        Text(
                            (if (e.isVideo) "▶ ${Fmt.duration(e.durationMs)} · " else "") + Fmt.date(e.dateTaken),
                            color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                            modifier = Modifier.align(Alignment.BottomStart).padding(12.dp)
                                .background(Color.Black.copy(alpha = 0.45f), RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 4.dp),
                        )
                        if (offsetX < -60f) Stamp(stringResource(R.string.stamp_delete), BColors.danger, Modifier.align(Alignment.TopEnd))
                        if (offsetX > 60f) Stamp(stringResource(R.string.stamp_keep), BColors.teal, Modifier.align(Alignment.TopStart))
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(28.dp), verticalAlignment = Alignment.CenterVertically) {
                RoundAction(Icons.Filled.Close, BColors.danger, 68, enabled = !finished) { decide(true) }
                RoundAction(Icons.AutoMirrored.Filled.Undo, Color.Gray, 52, enabled = history.isNotEmpty()) { undo() }
                RoundAction(Icons.Filled.Favorite, BColors.teal, 68, enabled = !finished) { decide(false) }
            }
            Spacer(Modifier.height(16.dp))
            PrimaryButton(
                if (marked.isEmpty()) stringResource(R.string.swipe_save_progress) else stringResource(R.string.review_delete, marked.size),
                color = if (marked.isEmpty()) BColors.teal else BColors.danger,
                onClick = {
                    if (marked.isEmpty()) { saveProgress(); onBack() } else review = true
                },
            )
        }
    }

    if (review) {
        ReviewDialog(marked.toList(), onDismiss = { review = false }) { chosen ->
            review = false
            saveProgress()
            marked.clear()
            history.clear()
            requestDelete(chosen)
        }
    }
}

@Composable
private fun Stamp(text: String, color: Color, modifier: Modifier) {
    Text(text, color = color, fontSize = 30.sp, fontWeight = FontWeight.Black,
        modifier = modifier.padding(24.dp).background(Color.White.copy(alpha = 0.85f), RoundedCornerShape(8.dp))
            .padding(horizontal = 12.dp, vertical = 4.dp))
}

@Composable
private fun RoundAction(icon: ImageVector, color: Color, size: Int, enabled: Boolean, onClick: () -> Unit) {
    Box(
        Modifier.size(size.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceVariant)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, tint = if (enabled) color else color.copy(alpha = 0.3f), modifier = Modifier.size((size / 2).dp))
    }
}

@Composable
private fun ReviewDialog(items: List<MediaEntry>, onDismiss: () -> Unit, onConfirm: (List<MediaEntry>) -> Unit) {
    var keep by remember { mutableStateOf(setOf<Long>()) }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(topBar = { BackTopBar(stringResource(R.string.review_title), onDismiss) }) { pad ->
            Column(Modifier.padding(pad).fillMaxSize()) {
                Text(stringResource(R.string.review_hint), style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(16.dp))
                LazyVerticalGrid(GridCells.Fixed(3), Modifier.weight(1f), contentPadding = PaddingValues(4.dp),
                    horizontalArrangement = Arrangement.spacedBy(4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    items(items, key = { it.id }) { e ->
                        val deleting = e.id !in keep
                        MediaCell(e, deleting, Modifier.graphicsLayer { alpha = if (deleting) 1f else 0.45f }
                            .clickable { keep = if (e.id in keep) keep - e.id else keep + e.id })
                    }
                }
                val toDelete = items.filter { it.id !in keep }
                SelectionBar(toDelete.size, toDelete.sumOf { it.bytes }) { onConfirm(toDelete) }
            }
        }
    }
}

// endregion

// region Cài đặt, mẹo, paywall

@Composable
fun SettingsScreen(vm: AppViewModel, state: UiState, navigate: (Route) -> Unit) {
    val context = LocalContext.current
    var debugPro by remember { mutableStateOf(vm.debugPro) }
    fun open(url: String) = runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
    LazyColumn(Modifier.fillMaxSize()) {
        item { TopAppBar(title = { Text(stringResource(R.string.tab_settings)) }) }
        item {
            if (state.isPro) {
                ListItem(headlineContent = { Text(stringResource(R.string.pro_active)) },
                    leadingContent = { Icon(Icons.Filled.WorkspacePremium, null, tint = Color(0xFFFFB300)) })
            } else {
                ListItem(modifier = Modifier.clickable { vm.showPaywall(null) },
                    headlineContent = { Text(stringResource(R.string.upgrade_pro), fontWeight = FontWeight.Bold) },
                    leadingContent = { Icon(Icons.Filled.WorkspacePremium, null, tint = Color(0xFFFFB300)) })
                ListItem(headlineContent = { Text(stringResource(R.string.free_deletes_left)) },
                    trailingContent = { Text("${vm.deletesQuota.remaining}/${vm.deletesQuota.limit}") })
                ListItem(headlineContent = { Text(stringResource(R.string.free_compress_left)) },
                    trailingContent = { Text("${vm.compressQuota.remaining}/${vm.compressQuota.limit}") })
            }
            HorizontalDivider()
        }
        item {
            ListItem(modifier = Modifier.clickable { navigate(Route.Tips) },
                headlineContent = { Text(stringResource(R.string.tips_title)) },
                leadingContent = { Icon(Icons.Filled.Lightbulb, null) })
            ListItem(modifier = Modifier.clickable { open("mailto:${AppConfig.SUPPORT_EMAIL}") },
                headlineContent = { Text(stringResource(R.string.contact_support)) })
            ListItem(modifier = Modifier.clickable { open("market://details?id=${context.packageName}") },
                headlineContent = { Text(stringResource(R.string.rate_app)) },
                leadingContent = { Icon(Icons.Filled.Star, null) })
            HorizontalDivider()
        }
        item {
            ListItem(modifier = Modifier.clickable(enabled = !state.scanning) { vm.startScan() },
                headlineContent = { Text(stringResource(R.string.rescan)) })
            ListItem(modifier = Modifier.clickable(enabled = !state.scanning) { vm.resetCache() },
                headlineContent = { Text(stringResource(R.string.reset_cache), color = BColors.danger) })
            HorizontalDivider()
        }
        item {
            ListItem(modifier = Modifier.clickable { open(AppConfig.PRIVACY_URL) }, headlineContent = { Text(stringResource(R.string.privacy_policy)) })
            ListItem(modifier = Modifier.clickable { open(AppConfig.TERMS_URL) }, headlineContent = { Text(stringResource(R.string.terms_of_use)) })
            ListItem(headlineContent = { Text(stringResource(R.string.version)) }, trailingContent = { Text(BuildConfig.VERSION_NAME) })
            Text(stringResource(R.string.privacy_footer), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(16.dp))
        }
        if (BuildConfig.DEBUG) {
            item {
                HorizontalDivider()
                Text("Developer (bản test)", fontWeight = FontWeight.Bold, modifier = Modifier.padding(16.dp))
                ListItem(headlineContent = { Text("Giả lập đã mua Pro") }, trailingContent = {
                    Switch(checked = debugPro, onCheckedChange = { debugPro = it; vm.debugPro = it })
                })
                ListItem(modifier = Modifier.clickable { vm.resetQuotas(); vm.toast("Đã reset hạn mức") },
                    headlineContent = { Text("Reset hạn mức miễn phí hôm nay") })
            }
        }
    }
}

@Composable
fun TipsScreen(onBack: () -> Unit) {
    val tips = listOf(
        R.string.tip_trash_title to R.string.tip_trash_body,
        R.string.tip_zalo_title to R.string.tip_zalo_body,
        R.string.tip_photos_title to R.string.tip_photos_body,
        R.string.tip_files_title to R.string.tip_files_body,
        R.string.tip_apps_title to R.string.tip_apps_body,
        R.string.tip_chrome_title to R.string.tip_chrome_body,
    )
    Scaffold(topBar = { BackTopBar(stringResource(R.string.tips_title), onBack) }) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            items(tips) { (t, b) ->
                Column {
                    Text(stringResource(t), fontWeight = FontWeight.Bold)
                    Text(stringResource(b), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            item {
                Text(stringResource(R.string.tips_footer), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
fun PaywallDialog(vm: AppViewModel, state: UiState) {
    val plans = listOf(
        Triple(R.string.plan_yearly, "499.000đ", R.string.period_year),
        Triple(R.string.plan_weekly, "79.000đ", R.string.period_week),
        Triple(R.string.plan_lifetime, "799.000đ", R.string.period_lifetime),
    )
    var selected by remember { mutableIntStateOf(0) }
    val features = listOf(R.string.pw_feat_unlimited, R.string.pw_feat_compress, R.string.pw_feat_private, R.string.pw_feat_support)
    Dialog(onDismissRequest = vm::dismissPaywall, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold { pad ->
            LazyColumn(
                Modifier.padding(pad).fillMaxSize(),
                contentPadding = PaddingValues(20.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                item {
                    Row(Modifier.fillMaxWidth()) {
                        Spacer(Modifier.weight(1f))
                        IconButton(onClick = vm::dismissPaywall) { Icon(Icons.Filled.Close, stringResource(R.string.close)) }
                    }
                    Icon(Icons.Filled.WorkspacePremium, null, tint = Color(0xFFFFB300), modifier = Modifier.size(56.dp))
                }
                item {
                    Text(stringResource(R.string.pw_title), fontSize = 24.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                    state.paywallReason?.let {
                        Text(it, color = BColors.danger, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
                            modifier = Modifier.padding(top = 8.dp))
                    }
                }
                items(features) { f ->
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.CheckCircle, null, tint = BColors.teal)
                        Spacer(Modifier.width(10.dp))
                        Text(stringResource(f))
                    }
                }
                itemsIndexed(plans) { i, (title, price, period) ->
                    Card(
                        Modifier.fillMaxWidth().clickable { selected = i },
                        shape = RoundedCornerShape(14.dp),
                        colors = CardDefaults.cardColors(
                            containerColor = if (selected == i) BColors.teal.copy(alpha = 0.12f) else MaterialTheme.colorScheme.surfaceVariant
                        ),
                    ) {
                        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(stringResource(title), fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                            Column(horizontalAlignment = Alignment.End) {
                                Text(price, fontWeight = FontWeight.Bold)
                                Text(stringResource(period), style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
                item {
                    PrimaryButton(stringResource(R.string.pw_continue), onClick = {
                        Analytics.log("purchase_tap", mapOf("plan" to selected))
                        vm.dismissPaywall()
                        vm.toast(vm.getApplication<android.app.Application>().getString(R.string.billing_coming_soon))
                    })
                    Text(stringResource(R.string.pw_legal_android), style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center,
                        modifier = Modifier.padding(top = 10.dp))
                }
            }
        }
    }
}

// endregion
