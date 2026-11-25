package vn.bentic.bclean

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.bentic.bclean.core.DuplicateFinder
import vn.bentic.bclean.core.SimilarFinder

class AlgorithmsTest {
    @Test fun duplicatesGroupNearIdenticalHashes() {
        val a = 0x0F0F_0F0F_1234_5678L
        val b = a xor 0b101L
        val c = 0x7F0F_0F0F_ABCD_EF01L
        val groups = DuplicateFinder.groups(listOf(a, b, c, null), listOf(1.33, 1.33, 1.33, 1.33))
        assertEquals(listOf(listOf(0, 1)), groups)
    }

    @Test fun duplicatesRespectAspectRatio() {
        val a = 0x1111_2222_3333_4444L
        assertTrue(DuplicateFinder.groups(listOf(a, a), listOf(0.75, 1.33)).isEmpty())
    }

    @Test fun duplicatesAreTransitive() {
        val a = 0x1111_2222_3333_4444L
        assertEquals(listOf(listOf(0, 1, 2)), DuplicateFinder.groups(listOf(a, a xor 1L, a xor 3L), listOf(1.0, 1.0, 1.0)))
    }

    @Test fun similarOnlyWithinWindow() {
        val dates = listOf(0L, 5_000L, 500_000L, 505_000L)
        val compared = mutableListOf<Pair<Int, Int>>()
        val groups = SimilarFinder.groups(dates, 60_000L) { a, b -> compared += a to b; true }
        assertEquals(listOf(listOf(0, 1), listOf(2, 3)), groups)
        assertFalse(compared.contains(1 to 2))
    }
}
