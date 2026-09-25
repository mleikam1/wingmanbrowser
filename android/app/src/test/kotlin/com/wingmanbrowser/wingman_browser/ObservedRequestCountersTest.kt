package com.wingmanbrowser.wingman_browser

import org.junit.Assert.*
import org.junit.Test

class ObservedRequestCountersTest {
    @Test fun onlyReportedPolicyOutcomesIncreaseBlockedRequests() {
        val counters = ObservedRequestCounters()
        val token = counters.beginRenderer()
        counters.record(token, false)
        counters.record(token, true)
        counters.record(token, true)
        val expected = ObservedRequestCounters.Snapshot(3, 2, false)
        assertEquals(expected, counters.snapshot())
        // Bridge replays are snapshots, never a second enforcement outcome.
        assertEquals(expected, counters.snapshot())
    }

    @Test fun closingAndReplacingRendererRejectsStaleCallbacksAndErasesCounts() {
        val counters = ObservedRequestCounters()
        val old = counters.beginRenderer()
        counters.record(old, true)
        counters.release()
        assertFalse(counters.record(old, true))
        assertEquals(ObservedRequestCounters.Snapshot(0, 0, false), counters.snapshot())
        val current = counters.beginRenderer()
        assertFalse(counters.record(old, true))
        assertTrue(counters.record(current, false))
        assertEquals(ObservedRequestCounters.Snapshot(1, 0, false), counters.snapshot())
    }

    @Test fun normalAndPrivateRenderersNeverShareCounters() {
        val normal = ObservedRequestCounters()
        val private = ObservedRequestCounters()
        val normalToken = normal.beginRenderer()
        val privateToken = private.beginRenderer()
        normal.record(normalToken, true)
        private.record(privateToken, true)
        private.record(privateToken, true)
        private.release()
        assertEquals(ObservedRequestCounters.Snapshot(1, 1, false), normal.snapshot())
        assertEquals(ObservedRequestCounters.Snapshot(0, 0, false), private.snapshot())
    }

    @Test fun countersAreBoundedAndReportSaturation() {
        val counters = ObservedRequestCounters(maximum = 2)
        val token = counters.beginRenderer()
        repeat(3) { counters.record(token, true) }
        assertEquals(ObservedRequestCounters.Snapshot(2, 2, true), counters.snapshot())
    }

    @Test fun concurrentInterceptionDoesNotLoseOutcomes() {
        val counters = ObservedRequestCounters()
        val token = counters.beginRenderer()
        val workers = List(4) {
            Thread { repeat(500) { counters.record(token, true) } }.also { it.start() }
        }
        workers.forEach { it.join() }
        assertEquals(ObservedRequestCounters.Snapshot(2000, 2000, false), counters.snapshot())
    }
}
