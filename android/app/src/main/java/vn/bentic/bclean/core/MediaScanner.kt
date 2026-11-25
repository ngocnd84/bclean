package vn.bentic.bclean.core

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.provider.MediaStore
import android.util.Size
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import org.json.JSONObject
import vn.bentic.bclean.R
import java.io.File
import java.util.concurrent.atomic.AtomicInteger

/** Phân tích ảnh trên máy: dHash (ảnh trùng/giống) và độ nét (ảnh mờ). */
object ImageAnalysis {
    private fun gray(c: Int): Int {
        val r = (c shr 16) and 0xFF
        val g = (c shr 8) and 0xFF
        val b = c and 0xFF
        return (r * 299 + g * 587 + b * 114) / 1000
    }

    private fun pixels(src: Bitmap, w: Int, h: Int): IntArray {
        val scaled = Bitmap.createScaledBitmap(src, w, h, true)
        val px = IntArray(w * h)
        scaled.getPixels(px, 0, w, 0, 0, w, h)
        if (scaled !== src) scaled.recycle()
        return px
    }

    fun dHash(src: Bitmap): Long {
        val px = pixels(src, 9, 8)
        var hash = 0L
        var bit = 0
        for (y in 0 until 8) for (x in 0 until 8) {
            if (gray(px[y * 9 + x]) > gray(px[y * 9 + x + 1])) hash = hash or (1L shl bit)
            bit++
        }
        return hash
    }

    fun sharpness(src: Bitmap): Double {
        val n = 128
        val p = pixels(src, n, n).map { gray(it) }
        var sum = 0.0
        var sumSq = 0.0
        var count = 0.0
        for (y in 1 until n - 1) for (x in 1 until n - 1) {
            val i = y * n + x
            val lap = (p[i - n] + p[i + n] + p[i - 1] + p[i + 1] - 4 * p[i]).toDouble()
            sum += lap
            sumSq += lap * lap
            count += 1
        }
        val mean = sum / count
        return sumSq / count - mean * mean
    }
}

/** Bộ nhớ đệm kết quả phân tích → lần quét sau nhanh hơn nhiều. */
class AnalysisCache(private val file: File) {
    data class Record(val modified: Long, val hash: Long?, val sharpness: Double)

    private val entries = HashMap<Long, Record>()

    init {
        runCatching {
            if (file.exists()) {
                val json = JSONObject(file.readText())
                for (k in json.keys()) {
                    val o = json.getJSONObject(k)
                    entries[k.toLong()] = Record(
                        o.getLong("m"),
                        if (o.has("h")) o.getLong("h") else null,
                        o.getDouble("s"),
                    )
                }
            }
        }
    }

    @Synchronized fun get(id: Long, modified: Long): Record? = entries[id]?.takeIf { it.modified == modified }

    @Synchronized fun put(id: Long, r: Record) { entries[id] = r }

    @Synchronized fun save(keep: Set<Long>) {
        val json = JSONObject()
        for ((id, r) in entries) {
            if (id !in keep) continue
            val o = JSONObject().put("m", r.modified).put("s", r.sharpness)
            r.hash?.let { o.put("h", it) }
            json.put(id.toString(), o)
        }
        runCatching { file.writeText(json.toString()) }
    }

    companion object {
        fun clear(context: Context) { File(context.filesDir, FILE).delete() }
        const val FILE = "bclean-analysis-v1.json"
    }
}

class MediaScanner(private val context: Context) {

    private data class Row(val entry: MediaEntry, val modified: Long)

    private fun queryImages(): List<Row> {
        val out = ArrayList<Row>()
        val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        val projection = arrayOf(
            MediaStore.Images.Media._ID, MediaStore.Images.Media.SIZE, MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.DATE_ADDED, MediaStore.Images.Media.DATE_MODIFIED,
            MediaStore.Images.Media.WIDTH, MediaStore.Images.Media.HEIGHT, MediaStore.Images.Media.RELATIVE_PATH,
        )
        context.contentResolver.query(collection, projection, null, null, null)?.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val sizeCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)
            val takenCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_TAKEN)
            val addedCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED)
            val modCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_MODIFIED)
            val wCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.WIDTH)
            val hCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.HEIGHT)
            val pathCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.RELATIVE_PATH)
            while (c.moveToNext()) {
                val id = c.getLong(idCol)
                val taken = c.getLong(takenCol).takeIf { it > 0 } ?: (c.getLong(addedCol) * 1000)
                val path = c.getString(pathCol) ?: ""
                out += Row(
                    MediaEntry(
                        id = id,
                        uri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id),
                        isVideo = false,
                        bytes = c.getLong(sizeCol),
                        dateTaken = taken,
                        width = c.getInt(wCol),
                        height = c.getInt(hCol),
                        isScreenshot = path.contains("screenshot", ignoreCase = true),
                    ),
                    c.getLong(modCol),
                )
            }
        }
        return out.sortedBy { it.entry.dateTaken }
    }

    fun queryVideos(): List<MediaEntry> {
        val out = ArrayList<MediaEntry>()
        val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        val projection = arrayOf(
            MediaStore.Video.Media._ID, MediaStore.Video.Media.SIZE, MediaStore.Video.Media.DATE_TAKEN,
            MediaStore.Video.Media.DATE_ADDED, MediaStore.Video.Media.WIDTH, MediaStore.Video.Media.HEIGHT,
            MediaStore.Video.Media.DURATION, MediaStore.Video.Media.ORIENTATION,
        )
        context.contentResolver.query(collection, projection, null, null, null)?.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
            val sizeCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
            val takenCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_TAKEN)
            val addedCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)
            val wCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.WIDTH)
            val hCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.HEIGHT)
            val durCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
            val oriCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.ORIENTATION)
            while (c.moveToNext()) {
                val id = c.getLong(idCol)
                out += MediaEntry(
                    id = id,
                    uri = ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id),
                    isVideo = true,
                    bytes = c.getLong(sizeCol),
                    dateTaken = c.getLong(takenCol).takeIf { it > 0 } ?: (c.getLong(addedCol) * 1000),
                    width = c.getInt(wCol),
                    height = c.getInt(hCol),
                    durationMs = c.getLong(durCol),
                    orientation = c.getInt(oriCol),
                )
            }
        }
        return out
    }

    /** Tất cả ảnh + video, mới nhất trước (cho chế độ Lướt ảnh). */
    fun queryAllNewestFirst(): List<MediaEntry> =
        (queryImages().map { it.entry } + queryVideos()).sortedByDescending { it.dateTaken }

    private fun loadThumb(uri: Uri, side: Int): Bitmap? = runCatching {
        val bmp = context.contentResolver.loadThumbnail(uri, Size(side, side), null)
        if (bmp.config == Bitmap.Config.HARDWARE) bmp.copy(Bitmap.Config.ARGB_8888, false) else bmp
    }.getOrNull()

    suspend fun scan(onProgress: (Float, String) -> Unit): ScanResult = withContext(Dispatchers.IO) {
        val cache = AnalysisCache(File(context.filesDir, AnalysisCache.FILE))
        val rows = queryImages()
        val videos = queryVideos()

        // 1. Phân tích ảnh (dùng cache nếu ảnh chưa đổi)
        val records = arrayOfNulls<AnalysisCache.Record>(rows.size)
        val todo = ArrayList<Int>()
        rows.forEachIndexed { i, r ->
            val hit = cache.get(r.entry.id, r.modified)
            if (hit != null) records[i] = hit else todo += i
        }
        val done = AtomicInteger(0)
        val cached = rows.size - todo.size
        onProgress(0.02f, context.getString(R.string.scan_analyzing, cached, rows.size))
        val sem = Semaphore(4)
        coroutineScope {
            todo.map { i ->
                async {
                    sem.withPermit {
                        val r = rows[i]
                        val bmp = loadThumb(r.entry.uri, 256)
                        val rec = if (bmp != null) {
                            val result = AnalysisCache.Record(r.modified, ImageAnalysis.dHash(bmp), ImageAnalysis.sharpness(bmp))
                            bmp.recycle()
                            result
                        } else {
                            AnalysisCache.Record(r.modified, null, -1.0)
                        }
                        records[i] = rec
                        cache.put(r.entry.id, rec)
                        val d = done.incrementAndGet()
                        if (d % 20 == 0) {
                            onProgress(
                                0.02f + 0.7f * d / maxOf(1, todo.size),
                                context.getString(R.string.scan_analyzing, cached + d, rows.size),
                            )
                        }
                    }
                }
            }.awaitAll()
        }

        val entries = rows.mapIndexed { i, r -> r.entry.copy(sharpness = records[i]?.sharpness ?: -1.0) }

        // 2. Ảnh trùng
        onProgress(0.75f, context.getString(R.string.scan_duplicates))
        val hashes = records.map { it?.hash }
        val aspects = entries.map { it.width.toDouble() / maxOf(1, it.height) }
        val dupGroups = DuplicateFinder.groups(hashes, aspects, AppConfig.DUPLICATE_MAX_HAMMING)
        val inDup = dupGroups.flatten().toHashSet()

        // 3. Ảnh giống nhau (chụp liên tiếp)
        onProgress(0.82f, context.getString(R.string.scan_similar))
        val candidates = entries.indices.filter { it !in inDup && !entries[it].isScreenshot && hashes[it] != null }
        val simGroups = SimilarFinder.groups(
            dates = candidates.map { entries[it].dateTaken },
            windowMs = AppConfig.SIMILAR_WINDOW_MS,
        ) { a, b ->
            DuplicateFinder.hamming(hashes[candidates[a]]!!, hashes[candidates[b]]!!) <= AppConfig.SIMILAR_MAX_HAMMING
        }

        // 4. Phân loại còn lại
        onProgress(0.95f, context.getString(R.string.scan_finishing))
        val screenshots = entries.filter { it.isScreenshot }.sortedBy { it.dateTaken }
        val blurry = entries.filterIndexed { i, e ->
            !e.isScreenshot && i !in inDup && e.sharpness >= 0 && e.sharpness < AppConfig.BLUR_THRESHOLD
        }.sortedBy { it.sharpness }

        cache.save((rows.map { it.entry.id }).toHashSet())
        onProgress(1f, context.getString(R.string.scan_done))

        ScanResult(
            duplicates = dupGroups.map { g -> MediaGroup.make(g.map { entries[it] }) }.sortedByDescending { it.reclaimableBytes },
            similar = simGroups.map { g -> MediaGroup.make(g.map { entries[candidates[it]] }) }.sortedByDescending { it.reclaimableBytes },
            screenshots = screenshots,
            blurry = blurry,
            videos = videos.sortedByDescending { it.bytes },
            totalPhotos = rows.size,
            totalVideos = videos.size,
            libraryBytes = entries.sumOf { it.bytes } + videos.sumOf { it.bytes },
            scannedAt = System.currentTimeMillis(),
        )
    }
}
