package com.wingmanbrowser.wingman_browser

import java.net.URI
import java.util.Locale

/** Values used by native callbacks; no credential or browsing data is persisted. */
internal fun browserOrigin(raw: String): String? = try {
    val uri = URI(raw)
    val scheme = uri.scheme?.lowercase(Locale.ROOT)
    val host = uri.host?.lowercase(Locale.ROOT)?.trimEnd('.')?.removeSurrounding("[", "]")
    if (scheme !in setOf("http", "https") || host.isNullOrEmpty() || uri.rawUserInfo != null ||
        uri.port !in -1..65535 || uri.port == 0) null else {
        val authority = if (host.contains(':')) "[$host]" else host
        val port = uri.port.takeUnless { it == -1 || (scheme == "https" && it == 443) || (scheme == "http" && it == 80) }
        "$scheme://$authority${port?.let { ":$it" } ?: ""}"
    }
} catch (_: Exception) { null }

internal data class BrowserDocumentTicket(val generation: Long, val origin: String)

internal class BrowserDocumentScope {
    @Volatile private var generation = 0L
    fun advance() { generation++ }
    fun issue(url: String): BrowserDocumentTicket? = browserOrigin(url)?.let { BrowserDocumentTicket(generation, it) }
    fun owns(ticket: BrowserDocumentTicket?, currentUrl: String) =
        ticket != null && ticket.generation == generation && ticket.origin == browserOrigin(currentUrl)
}

internal fun permitsHttpAuthentication(pageUrl: String, challengeHost: String): Boolean {
    val origin = browserOrigin(pageUrl) ?: return false
    if (!origin.startsWith("https://")) return false
    val host = runCatching { URI(origin).host.removeSurrounding("[", "]").trimEnd('.').lowercase(Locale.ROOT) }.getOrNull()
    return host != null && host == challengeHost.removeSurrounding("[", "]").trimEnd('.').lowercase(Locale.ROOT)
}

internal object BrowserDownloadHeaders {
    fun request(initialUrl: String, destination: String, userAgent: String, cookie: String?): Map<String, String> {
        val headers = mutableMapOf<String, String>()
        if (userAgent.length in 1..4096 && userAgent.none { it.code < 32 || it.code == 127 }) headers["User-Agent"] = userAgent
        if (browserOrigin(initialUrl) != null && browserOrigin(initialUrl) == browserOrigin(destination) &&
            cookie != null && cookie.length <= 32768 && cookie.none { it.code < 32 || it.code == 127 }) headers["Cookie"] = cookie
        return headers
    }

    fun responseCookies(initialUrl: String, destination: String, headers: Map<String?, List<String>>): List<String> {
        if (browserOrigin(initialUrl) == null || browserOrigin(initialUrl) != browserOrigin(destination)) return emptyList()
        return headers.filterKeys { it.equals("Set-Cookie", ignoreCase = true) }.values.flatten()
            .take(50).filter { it.length <= 8192 && it.none { c -> c.code < 32 || c.code == 127 } }
    }
}

/** One-use asynchronous child-window handoff. Waiting is allowed only on a
 * request interception worker, never on Android's UI thread. */
internal class BrowserWindowLease(
    private val renderer: Any,
    private val scope: BrowserDocumentScope,
    private val ticket: BrowserDocumentTicket,
    private val revision: Long,
    private val deadline: Long,
) {
    private val gate = java.util.concurrent.CountDownLatch(1)
    @Volatile private var claimed = false
    @Volatile var activated = false
        private set
    @Volatile private var cancelled = false
    fun current(renderer: Any?, url: String, revision: Long, now: Long) =
        !cancelled && now < deadline && this.renderer === renderer && this.revision == revision && scope.owns(ticket, url)
    @Synchronized fun claim(renderer: Any?, url: String, revision: Long, now: Long): Boolean {
        if (claimed || !current(renderer, url, revision, now)) return false
        claimed = true; return true
    }
    @Synchronized fun activate(renderer: Any?, url: String, revision: Long, now: Long): Boolean {
        if (!claimed || activated || !current(renderer, url, revision, now)) return false
        activated = true; gate.countDown(); return true
    }
    fun awaitActivation(now: Long): Boolean {
        if (cancelled) return false
        val remaining = deadline - now
        if (remaining <= 0) return false
        return gate.await(remaining, java.util.concurrent.TimeUnit.MILLISECONDS) && activated && !cancelled
    }
    @Synchronized fun cancel() { cancelled = true; gate.countDown() }
}

/** Private popup profiles live until their last renderer closes. */
internal class BrowserProfileReferences {
    private val counts = mutableMapOf<String, Int>()
    @Synchronized fun retain(name: String) { counts[name] = (counts[name] ?: 0) + 1 }
    @Synchronized fun contains(name: String) = (counts[name] ?: 0) > 0
    @Synchronized fun release(name: String): Boolean {
        val count = counts[name] ?: return false
        if (count > 1) { counts[name] = count - 1; return false }
        counts.remove(name); return true
    }
}
