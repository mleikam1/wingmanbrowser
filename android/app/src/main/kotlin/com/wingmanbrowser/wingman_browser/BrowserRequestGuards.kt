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
    private var generation = 0L
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
