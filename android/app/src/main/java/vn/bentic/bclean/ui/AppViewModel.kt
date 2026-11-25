package vn.bentic.bclean.ui

import android.Manifest
import android.app.Application
import android.content.Context
import android.content.IntentSender
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import vn.bentic.bclean.BuildConfig
import vn.bentic.bclean.R
import vn.bentic.bclean.core.AnalysisCache
import vn.bentic.bclean.core.AppConfig
import vn.bentic.bclean.core.CompressionLevel
import vn.bentic.bclean.core.FreeQuota
import vn.bentic.bclean.core.Fmt
import vn.bentic.bclean.core.MediaEntry
import vn.bentic.bclean.core.MediaScanner
import vn.bentic.bclean.core.ScanResult
import vn.bentic.bclean.core.VideoCompressor

enum class Access { NONE, PARTIAL, FULL }

data class UiState(
    val access: Access = Access.NONE,
    val scanning: Boolean = false,
    val progress: Float = 0f,
    val progressText: String = "",
    val result: ScanResult = ScanResult(),
    val storageTotal: Long = 0,
    val storageFree: Long = 0,
    val isPro: Boolean = false,
    val message: String? = null,
    val paywallReason: String? = null,
    val showPaywall: Boolean = false,
    val freedBytes: Long = 0,
    val deletedCount: Int = 0,
    val compressProgress: Float? = null,
    val compressResult: String? = null,
)

/** Nhật ký sự kiện tối giản. Khi phát hành: thay bằng Firebase / TelemetryDeck. */
object Analytics {
    fun log(event: String, params: Map<String, Any> = emptyMap()) {
        Log.i("BcleanAnalytics", "📊 $event $params")
    }
}

class AppViewModel(app: Application) : AndroidViewModel(app) {
    private val ctx: Context get() = getApplication()
    private val prefs = app.getSharedPreferences("bclean", Context.MODE_PRIVATE)
    val deletesQuota = FreeQuota(prefs, "quota_delete", AppConfig.FREE_DELETES_PER_DAY)
    val compressQuota = FreeQuota(prefs, "quota_compress", AppConfig.FREE_COMPRESS_PER_DAY)
    private val scanner = MediaScanner(app)
    private val compressor = VideoCompressor(app)

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    var onboarded: Boolean
        get() = prefs.getBoolean("onboarded", false)
        set(v) { prefs.edit().putBoolean("onboarded", v).apply() }

    var debugPro: Boolean
        get() = BuildConfig.DEBUG && prefs.getBoolean("debug_pro", false)
        set(v) { prefs.edit().putBoolean("debug_pro", v).apply(); refreshPro() }

    private var scanJob: Job? = null
    private var pendingDelete: List<MediaEntry> = emptyList()
    private var pendingCompressSaved: Long = 0

    init {
        refreshAccess()
        refreshStorage()
        refreshPro()
        refreshStats()
    }

    // region Quyền & thông tin máy

    fun permissionsToRequest(): Array<String> = when {
        Build.VERSION.SDK_INT >= 34 -> arrayOf(
            Manifest.permission.READ_MEDIA_IMAGES,
            Manifest.permission.READ_MEDIA_VIDEO,
            Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
        )
        Build.VERSION.SDK_INT >= 33 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO)
        else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
    }

    private fun granted(p: String) = ContextCompat.checkSelfPermission(ctx, p) == PackageManager.PERMISSION_GRANTED

    fun refreshAccess() {
        val access = when {
            Build.VERSION.SDK_INT >= 33 && granted(Manifest.permission.READ_MEDIA_IMAGES) -> Access.FULL
            Build.VERSION.SDK_INT < 33 && granted(Manifest.permission.READ_EXTERNAL_STORAGE) -> Access.FULL
            Build.VERSION.SDK_INT >= 34 && granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) -> Access.PARTIAL
            else -> Access.NONE
        }
        val before = _state.value.access
        _state.update { it.copy(access = access) }
        Analytics.log("permission", mapOf("access" to access.name))
        if (before != access && access != Access.NONE) startScan()
    }

    fun refreshStorage() {
        runCatching {
            val stat = StatFs(Environment.getDataDirectory().path)
            _state.update { it.copy(storageTotal = stat.totalBytes, storageFree = stat.availableBytes) }
        }
    }

    private fun refreshPro() {
        _state.update { it.copy(isPro = debugPro) }
    }

    private fun refreshStats() {
        _state.update {
            it.copy(freedBytes = prefs.getLong("stats_freed", 0), deletedCount = prefs.getInt("stats_deleted", 0))
        }
    }

    private fun addStats(bytes: Long, items: Int) {
        prefs.edit()
            .putLong("stats_freed", prefs.getLong("stats_freed", 0) + bytes)
            .putInt("stats_deleted", prefs.getInt("stats_deleted", 0) + items)
            .apply()
        refreshStats()
    }

    // endregion

    // region Quét

    fun startScanIfNeeded() {
        if (_state.value.result.scannedAt == 0L && !_state.value.scanning) startScan()
    }

    fun startScan() {
        if (_state.value.access == Access.NONE || _state.value.scanning) return
        val started = System.currentTimeMillis()
        _state.update { it.copy(scanning = true, progress = 0f, progressText = ctx.getString(R.string.scan_preparing)) }
        scanJob = viewModelScope.launch {
            val result = runCatching {
                scanner.scan { p, text ->
                    _state.update { s -> s.copy(progress = maxOf(s.progress, p), progressText = text) }
                }
            }.getOrElse { e ->
                Log.e("Bclean", "scan failed", e)
                _state.update { it.copy(message = e.localizedMessage) }
                ScanResult()
            }
            _state.update { it.copy(scanning = false, progress = 1f, result = result) }
            refreshStorage()
            Analytics.log(
                "scan_completed",
                mapOf(
                    "seconds" to (System.currentTimeMillis() - started) / 1000,
                    "photos" to result.totalPhotos,
                    "videos" to result.totalVideos,
                    "reclaimable_mb" to result.headlineReclaimable / 1_000_000,
                ),
            )
        }
    }

    fun resetCache() {
        AnalysisCache.clear(ctx)
        _state.update { it.copy(result = ScanResult()) }
        startScan()
    }

    suspend fun loadAllForSwipe(): List<MediaEntry> = withContext(Dispatchers.IO) { scanner.queryAllNewestFirst() }

    // endregion

    // region Xoá (Android hiện hộp thoại xác nhận của hệ thống)

    /** Trả về IntentSender để UI mở hộp thoại xoá; null nếu vượt hạn mức (khi đó paywall hiện ra). */
    fun prepareDelete(items: List<MediaEntry>): IntentSender? {
        if (items.isEmpty()) return null
        val s = _state.value
        if (!s.isPro && !deletesQuota.canUse(items.size)) {
            val remaining = deletesQuota.remaining
            showPaywall(
                if (remaining > 0) ctx.getString(R.string.quota_remaining, remaining)
                else ctx.getString(R.string.quota_used_up)
            )
            Analytics.log("quota_hit", mapOf("type" to "delete", "wanted" to items.size))
            return null
        }
        pendingDelete = items
        return MediaStore.createDeleteRequest(ctx.contentResolver, items.map { it.uri }).intentSender
    }

    fun onDeleteResult(ok: Boolean) {
        val items = pendingDelete
        pendingDelete = emptyList()
        if (!ok || items.isEmpty()) return
        if (!_state.value.isPro) deletesQuota.consume(items.size)
        val bytes = items.sumOf { it.bytes } + pendingCompressSaved
        val wasCompress = pendingCompressSaved > 0
        pendingCompressSaved = 0
        addStats(bytes, items.size)
        _state.update {
            it.copy(
                result = it.result.without(items.map { e -> e.id }.toSet()),
                message = if (wasCompress) ctx.getString(R.string.compress_original_deleted)
                else ctx.getString(R.string.done_deleted, items.size, Fmt.bytes(bytes)),
            )
        }
        refreshStorage()
        Analytics.log("delete_done", mapOf("count" to items.size, "mb" to bytes / 1_000_000))
    }

    // endregion

    // region Nén video

    /** Nén xong → trả về IntentSender xoá bản gốc (nếu người dùng chọn), hoặc null. */
    suspend fun compress(entry: MediaEntry, level: CompressionLevel, deleteOriginal: Boolean): IntentSender? {
        val s = _state.value
        if (!s.isPro && !compressQuota.canUse(1)) {
            showPaywall(ctx.getString(R.string.quota_compress_used_up))
            return null
        }
        _state.update { it.copy(compressProgress = 0f, compressResult = null) }
        return try {
            val file = compressor.compress(entry, level) { p -> _state.update { it.copy(compressProgress = p) } }
            val newBytes = file.length()
            if (newBytes <= 0 || newBytes >= entry.bytes) {
                file.delete()
                _state.update { it.copy(compressProgress = null, compressResult = ctx.getString(R.string.compress_not_smaller)) }
                return null
            }
            withContext(Dispatchers.IO) { compressor.saveToGallery(file, entry) }
            if (!s.isPro) compressQuota.consume(1)
            val saved = entry.bytes - newBytes
            _state.update {
                it.copy(
                    compressProgress = null,
                    compressResult = ctx.getString(R.string.compress_done, Fmt.bytes(newBytes), Fmt.bytes(saved)),
                )
            }
            Analytics.log("video_compressed", mapOf("level" to level.name, "saved_mb" to saved / 1_000_000))
            if (deleteOriginal) {
                pendingDelete = listOf(entry)
                pendingCompressSaved = 0
                MediaStore.createDeleteRequest(ctx.contentResolver, listOf(entry.uri)).intentSender
            } else null
        } catch (e: Exception) {
            Log.e("Bclean", "compress failed", e)
            _state.update { it.copy(compressProgress = null, compressResult = ctx.getString(R.string.err_export_failed)) }
            null
        }
    }

    fun clearCompressResult() = _state.update { it.copy(compressResult = null, compressProgress = null) }

    // endregion

    // region Paywall & thông báo

    fun showPaywall(reason: String?) {
        _state.update { it.copy(showPaywall = true, paywallReason = reason) }
        Analytics.log("paywall_view", mapOf("reason" to (reason ?: "banner")))
    }

    fun dismissPaywall() = _state.update { it.copy(showPaywall = false, paywallReason = null) }

    fun consumeMessage() = _state.update { it.copy(message = null) }

    fun toast(text: String) = _state.update { it.copy(message = text) }

    fun resetQuotas() {
        deletesQuota.reset()
        compressQuota.reset()
        _state.update { it.copy() }
    }

    // endregion
}
