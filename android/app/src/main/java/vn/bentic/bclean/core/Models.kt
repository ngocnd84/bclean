package vn.bentic.bclean.core

import android.net.Uri

/** Mọi thông số kinh doanh & kỹ thuật có thể chỉnh nằm ở đây. */
object AppConfig {
    const val FREE_DELETES_PER_DAY = 30
    const val FREE_COMPRESS_PER_DAY = 2

    /** Ảnh chụp cách nhau tối đa bao nhiêu ms thì xét "giống nhau" */
    const val SIMILAR_WINDOW_MS = 90_000L
    /** Ảnh giống nhau: số bit dHash khác nhau tối đa (Android chưa có Vision như iOS) */
    const val SIMILAR_MAX_HAMMING = 10
    /** Ảnh trùng: số bit dHash khác nhau tối đa (≤ 3) */
    const val DUPLICATE_MAX_HAMMING = 3
    /** Ảnh mờ: phương sai Laplacian dưới ngưỡng */
    const val BLUR_THRESHOLD = 60.0
    /** Video từ bao nhiêu byte thì coi là nặng */
    const val LARGE_VIDEO_BYTES = 50L * 1024 * 1024

    const val PRIVACY_URL = "https://bclean.vn/privacy"
    const val TERMS_URL = "https://bclean.vn/terms"
    const val SUPPORT_EMAIL = "support@bclean.vn"
}

enum class CleanCategory { DUPLICATES, SIMILAR, SCREENSHOTS, BLURRY, VIDEOS;
    val isGrouped: Boolean get() = this == DUPLICATES || this == SIMILAR
}

data class MediaEntry(
    val id: Long,
    val uri: Uri,
    val isVideo: Boolean,
    val bytes: Long,
    val dateTaken: Long,
    val width: Int,
    val height: Int,
    val durationMs: Long = 0,
    val orientation: Int = 0,
    val isScreenshot: Boolean = false,
    val sharpness: Double = -1.0,
)

/** Nhóm ảnh; phần tử đầu tiên luôn là ảnh "tốt nhất" (được giữ lại). */
data class MediaGroup(val items: List<MediaEntry>) {
    val best: MediaEntry get() = items.first()
    val reclaimableBytes: Long get() = items.drop(1).sumOf { it.bytes }

    companion object {
        fun make(raw: List<MediaEntry>): MediaGroup {
            val best = raw.maxBy { score(it) }
            return MediaGroup(listOf(best) + raw.filter { it.id != best.id }.sortedBy { it.dateTaken })
        }

        fun score(m: MediaEntry): Double =
            maxOf(0.0, m.sharpness) * 10 + m.width.toDouble() * m.height / 10_000 + m.bytes / 1e7
    }
}

data class ScanResult(
    val duplicates: List<MediaGroup> = emptyList(),
    val similar: List<MediaGroup> = emptyList(),
    val screenshots: List<MediaEntry> = emptyList(),
    val blurry: List<MediaEntry> = emptyList(),
    val videos: List<MediaEntry> = emptyList(),
    val totalPhotos: Int = 0,
    val totalVideos: Int = 0,
    val libraryBytes: Long = 0,
    val scannedAt: Long = 0,
) {
    fun groups(c: CleanCategory): List<MediaGroup> = when (c) {
        CleanCategory.DUPLICATES -> duplicates
        CleanCategory.SIMILAR -> similar
        else -> emptyList()
    }

    fun items(c: CleanCategory): List<MediaEntry> = when (c) {
        CleanCategory.DUPLICATES -> duplicates.flatMap { it.items }
        CleanCategory.SIMILAR -> similar.flatMap { it.items }
        CleanCategory.SCREENSHOTS -> screenshots
        CleanCategory.BLURRY -> blurry
        CleanCategory.VIDEOS -> videos
    }

    fun count(c: CleanCategory): Int = when (c) {
        CleanCategory.DUPLICATES, CleanCategory.SIMILAR -> groups(c).sumOf { it.items.size - 1 }
        CleanCategory.VIDEOS -> videos.count { it.bytes >= AppConfig.LARGE_VIDEO_BYTES }
        else -> items(c).size
    }

    fun reclaimable(c: CleanCategory): Long = when (c) {
        CleanCategory.DUPLICATES, CleanCategory.SIMILAR -> groups(c).sumOf { it.reclaimableBytes }
        CleanCategory.VIDEOS -> videos.filter { it.bytes >= AppConfig.LARGE_VIDEO_BYTES }.sumOf { it.bytes }
        else -> items(c).sumOf { it.bytes }
    }

    val headlineReclaimable: Long
        get() = reclaimable(CleanCategory.DUPLICATES) + reclaimable(CleanCategory.SIMILAR) +
            reclaimable(CleanCategory.SCREENSHOTS)

    fun without(ids: Set<Long>): ScanResult {
        if (ids.isEmpty()) return this
        fun clean(groups: List<MediaGroup>) = groups.mapNotNull { g ->
            val left = g.items.filter { it.id !in ids }
            when {
                left.size < 2 -> null
                left.first().id == g.items.first().id -> MediaGroup(left)
                else -> MediaGroup.make(left)
            }
        }
        return copy(
            duplicates = clean(duplicates),
            similar = clean(similar),
            screenshots = screenshots.filter { it.id !in ids },
            blurry = blurry.filter { it.id !in ids },
            videos = videos.filter { it.id !in ids },
        )
    }
}

enum class CompressionLevel(val shortSide: Int, val bitrate: Int) {
    LIGHT(1080, 6_000_000),
    BALANCED(720, 3_500_000),
    STRONG(540, 2_000_000);

    fun estimate(entry: MediaEntry): Long {
        val est = (entry.durationMs / 1000.0 * (bitrate + 128_000) / 8).toLong()
        return minOf(est, entry.bytes)
    }
}
