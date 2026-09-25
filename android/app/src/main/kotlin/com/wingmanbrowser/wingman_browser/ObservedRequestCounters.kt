package com.wingmanbrowser.wingman_browser

/**
 * Counts only outcomes reported by one WebView request interceptor. The same
 * URL may represent many requests; these are not unique trackers or a complete
 * traffic log. Callers never pass addresses, titles, cookies or request bodies.
 *
 * A token binds worker-thread callbacks to a renderer lifetime. Releasing or
 * replacing that renderer invalidates its callbacks and erases its counts.
 * Reading/emitting snapshots cannot increment the count, so duplicated bridge
 * delivery is harmless. Service-worker, navigation-delegate, TLS and download
 * callbacks are deliberately excluded instead of counting one request twice.
 */
internal class ObservedRequestCounters(private val maximum: Int = 100000) {
    data class Snapshot(val attempted: Int, val blocked: Int, val saturated: Boolean)
    private var generation = 0L
    private var active = false
    private var attempted = 0
    private var blocked = 0
    private var saturated = false

    init { require(maximum > 0) }

    @Synchronized fun beginRenderer(): Long {
        generation++
        active = true
        attempted = 0
        blocked = 0
        saturated = false
        return generation
    }

    @Synchronized fun record(token: Long, policyDenied: Boolean): Boolean {
        if (!active || token != generation) return false
        if (attempted < maximum) attempted++ else saturated = true
        if (policyDenied) {
            if (blocked < maximum) blocked++ else saturated = true
        }
        return true
    }

    @Synchronized fun snapshot() = Snapshot(attempted, blocked, saturated)

    @Synchronized fun release() {
        generation++
        active = false
        attempted = 0
        blocked = 0
        saturated = false
    }
}
