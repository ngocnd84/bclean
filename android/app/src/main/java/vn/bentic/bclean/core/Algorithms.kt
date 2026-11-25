package vn.bentic.bclean.core

import android.content.SharedPreferences
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Gom nhóm các phần tử có quan hệ "giống nhau" (bắc cầu). */
class UnionFind(n: Int) {
    private val parent = IntArray(n) { it }
    private val rank = IntArray(n)

    fun find(x: Int): Int {
        var root = x
        while (parent[root] != root) root = parent[root]
        var cur = x
        while (parent[cur] != root) {
            val next = parent[cur]
            parent[cur] = root
            cur = next
        }
        return root
    }

    fun union(a: Int, b: Int) {
        val ra = find(a)
        val rb = find(b)
        if (ra == rb) return
        when {
            rank[ra] < rank[rb] -> parent[ra] = rb
            rank[ra] > rank[rb] -> parent[rb] = ra
            else -> { parent[rb] = ra; rank[ra]++ }
        }
    }

    fun groups(minSize: Int): List<List<Int>> {
        val map = HashMap<Int, MutableList<Int>>()
        for (i in parent.indices) map.getOrPut(find(i)) { mutableListOf() }.add(i)
        return map.values.filter { it.size >= minSize }.map { it.sorted() }.sortedBy { it[0] }
    }
}

/**
 * Ảnh trùng bằng dHash 64-bit + multi-index: chia hash thành 4 khúc 16 bit.
 * Hai hash lệch ≤ 3 bit chắc chắn trùng ít nhất 1 khúc → chỉ so trong cùng khúc.
 */
object DuplicateFinder {
    fun hamming(a: Long, b: Long): Int = java.lang.Long.bitCount(a xor b)

    fun groups(hashes: List<Long?>, aspects: List<Double>, maxHamming: Int = 3, maxBucket: Int = 800): List<List<Int>> {
        val maxH = minOf(maxHamming, 3)
        val uf = UnionFind(hashes.size)
        val buckets = List(4) { HashMap<Int, MutableList<Int>>() }
        hashes.forEachIndexed { i, h ->
            if (h != null) for (c in 0 until 4) {
                val key = ((h ushr (16 * c)) and 0xFFFF).toInt()
                buckets[c].getOrPut(key) { mutableListOf() }.add(i)
            }
        }
        for (c in 0 until 4) {
            for (list in buckets[c].values) {
                if (list.size < 2 || list.size > maxBucket) continue
                for (x in 0 until list.size - 1) for (y in x + 1 until list.size) {
                    val i = list[x]
                    val j = list[y]
                    val hi = hashes[i] ?: continue
                    val hj = hashes[j] ?: continue
                    if (hamming(hi, hj) > maxH) continue
                    val ai = aspects[i]
                    val aj = aspects[j]
                    if (Math.abs(ai - aj) > 0.05 * maxOf(ai, aj)) continue
                    uf.union(i, j)
                }
            }
        }
        return uf.groups(2)
    }
}

/** Ảnh giống nhau: chỉ so các ảnh chụp liên tiếp. `dates` phải tăng dần. */
object SimilarFinder {
    fun groups(
        dates: List<Long>,
        windowMs: Long,
        maxNeighbors: Int = 6,
        onProgress: ((Int) -> Unit)? = null,
        isSimilar: (Int, Int) -> Boolean,
    ): List<List<Int>> {
        val uf = UnionFind(dates.size)
        for (i in dates.indices) {
            var j = i + 1
            var checked = 0
            while (j < dates.size && checked < maxNeighbors && dates[j] - dates[i] <= windowMs) {
                if (isSimilar(i, j)) uf.union(i, j)
                j++
                checked++
            }
            if (i % 50 == 0) onProgress?.invoke(i)
        }
        return uf.groups(2)
    }
}

/** Hạn mức miễn phí theo ngày. */
class FreeQuota(
    private val prefs: SharedPreferences,
    private val key: String,
    val limit: Int,
    private val now: () -> Long = { System.currentTimeMillis() },
) {
    private fun today(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(now()))

    val used: Int
        get() = if (prefs.getString("${key}_day", null) == today()) prefs.getInt("${key}_count", 0) else 0

    val remaining: Int get() = maxOf(0, limit - used)

    fun canUse(n: Int): Boolean = n <= remaining

    fun consume(n: Int) {
        val total = used + n
        prefs.edit().putString("${key}_day", today()).putInt("${key}_count", total).apply()
    }

    fun reset() {
        prefs.edit().remove("${key}_day").remove("${key}_count").apply()
    }
}

object Fmt {
    fun bytes(value: Long): String {
        val v = maxOf(0L, value).toDouble()
        val units = listOf("B", "KB", "MB", "GB", "TB")
        var size = v
        var u = 0
        while (size >= 1000 && u < units.size - 1) { size /= 1000; u++ }
        return if (u == 0) "${size.toInt()} B" else String.format(Locale.US, if (size >= 100) "%.0f %s" else "%.1f %s", size, units[u])
    }

    fun duration(ms: Long): String {
        val s = (ms / 1000).toInt()
        val h = s / 3600
        val m = (s % 3600) / 60
        val sec = s % 60
        return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, sec) else String.format(Locale.US, "%d:%02d", m, sec)
    }

    fun date(ms: Long): String =
        if (ms <= 0) "" else java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM).format(Date(ms))

    fun month(ms: Long): String {
        val s = SimpleDateFormat("MMMM yyyy", Locale.getDefault()).format(Date(ms))
        return s.replaceFirstChar { it.titlecase(Locale.getDefault()) }
    }
}
