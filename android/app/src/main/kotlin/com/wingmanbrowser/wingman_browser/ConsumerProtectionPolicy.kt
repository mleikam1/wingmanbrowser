package com.wingmanbrowser.wingman_browser

import android.content.Context
import android.net.Uri
import io.flutter.FlutterInjector
import org.json.JSONObject
import java.net.URI
import java.security.MessageDigest
import java.util.Locale

/** Build-pinned local baseline. Unknown classification is permitted, never called verified safe. */
internal class ConsumerProtectionPolicy(context: Context) {
    companion object {
        const val ASSET = "assets/policy/consumer_protection.json"
        // Replaced with the reviewed compiler output before the build.
        const val SHA256 = "f397d8f87a02fbb7754ce9c77931f740ba10271370e1e09f8402607bef59098f"
        private val DOMAIN_LABEL = Regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
        val REQUIRED = setOf("sexual-explicit", "gambling", "alcohol-promotion", "recreational-drug-promotion", "tobacco-nicotine", "security-threat")
    }
    data class Decision(val allowed: Boolean, val url: String, val reason: String? = null)
    internal data class PathRule(val host: String, val path: String, val category: String)
    internal data class Snapshot(val sequence: Long, val sha256: String, val domains: Map<String, String>, val paths: List<PathRule>, val trackers: Set<String>)
    private val context = context
    @Volatile private var snapshot: Snapshot? = null
    var diagnostic = "loading"
        private set
    private data class Restrictions(val domains: Set<String> = emptySet(), val urls: Set<String> = emptySet(), val searchBlocked: Boolean = false)
    @Volatile private var restrictions = Restrictions()
    init {
        try {
            diagnostic = "asset"
            val bytes = context.assets.open(FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(ASSET)).use { it.readBytes() }
            check(bytes.size in 100..(16 * 1024 * 1024))
            diagnostic = "integrity"
            check(MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) } == SHA256)
            snapshot = parseSnapshot(bytes, SHA256)
            diagnostic = "valid"
        } catch (_: Exception) { snapshot = null }
    }
    internal fun parseSnapshot(bytes: ByteArray, hash: String): Snapshot {
        val json = JSONObject(String(bytes, Charsets.UTF_8))
        check(json.getInt("schemaVersion") == 1 && json.getLong("sequence") >= 1)
        val categories = json.getJSONObject("categories")
        check(categories.length() == REQUIRED.size)
        val loaded = mutableMapOf<String, String>()
        fun hostValid(host: String) = host.length <= 253 && host.contains('.') && host.split('.').all { it.matches(DOMAIN_LABEL) }
        REQUIRED.forEach { category ->
            val values = categories.getJSONArray(category); check(values.length() > 0)
            for (i in 0 until values.length()) {
                val host = values.getString(i); check(hostValid(host)); loaded[host] = category
            }
        }
        val rules = json.getJSONArray("pathRules")
        val paths = (0 until rules.length()).map { i ->
            val r = rules.getJSONObject(i)
            val host = r.getString("host"); val path = r.getString("pathPrefix")
            check(r.getString("category") in REQUIRED && hostValid(host) && path.startsWith('/') && !path.contains('%') && !path.contains('?'))
            PathRule(host, path.lowercase(Locale.ROOT).trimEnd('/'), r.getString("category"))
        }
        val tracking = json.getJSONArray("trackers")
        val trackers = (0 until tracking.length()).map { tracking.getString(it).also { value -> check(hostValid(value)) } }.toSet()
        return Snapshot(json.getLong("sequence"), hash, loaded.toMap(), paths, trackers)
    }
    internal fun currentSnapshot(): Snapshot = checkNotNull(snapshot)
    internal fun activate(candidate: Snapshot) { snapshot = candidate; diagnostic = "valid" }
    fun valid() = snapshot != null && BuildConfig.WINGMAN_EDITION == "consumer"
    fun setAdditional(values: List<String>) { restrictions = restrictions.copy(domains = values.take(5000).mapNotNull(NativeGuardPolicy::normalizeHost).toSet()) }
    fun setAdditionalRestrictions(ids: List<String>, collections: List<String>, explicitDomains: List<String> = emptyList(), explicitUrls: List<String> = emptyList(), blockSearch: Boolean = false) {
        val search = blockSearch || "web-search" in ids || "web-search" in collections
        val domains = explicitDomains.take(5000).mapNotNull(NativeGuardPolicy::normalizeHost).toSet()
        val urls = explicitUrls.take(5000).mapNotNull { canonicalWeb(it)?.buildUpon()?.fragment(null)?.build()?.toString() }.toMutableSet()
        if (ids.isEmpty() && collections.isEmpty()) { restrictions = Restrictions(domains, urls, search); return }
        try {
            val asset = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("assets/policy/live_sites.json")
            val catalog = JSONObject(context.assets.open(asset).bufferedReader().use { it.readText() }).getJSONArray("sites")
            for (i in 0 until catalog.length()) {
                val site = catalog.getJSONObject(i)
                if (site.getString("id") in ids || site.optString("collection") in collections) {
                    val documents = site.getJSONArray("documents")
                    for (j in 0 until documents.length()) canonicalWeb(documents.getJSONObject(j).getString("url"))?.toString()?.let { urls.add(it) }
                }
            }
            restrictions = Restrictions(domains, urls.toSet(), search)
        } catch (_: Exception) { snapshot = null }
    }
    private fun suffixes(host: String): Sequence<String> = generateSequence(host) { value -> value.substringAfter('.', "").ifEmpty { null } }
    fun decide(raw: String, topLevel: Boolean = true, initiator: String? = null, normalizeSearch: Boolean = true): Decision {
        fun deny(reason: String) = Decision(false, raw, reason)
        if (!valid()) return deny("Mandatory protection needs recovery.")
        val uri = canonicalWeb(raw) ?: return deny("This address is not a supported web destination.")
        val host = uri.host!!.lowercase(Locale.ROOT).trimEnd('.')
        val baseline = snapshot ?: return deny("Mandatory protection needs recovery.")
        val limits = restrictions
        if (topLevel && uri.buildUpon().fragment(null).build().toString() in limits.urls) return deny("Blocked by an additional restriction.")
        if (limits.searchBlocked && (host == "duckduckgo.com" || host.endsWith(".duckduckgo.com") || host in setOf("duck.com", "ddg.gg", "google.com", "www.google.com", "bing.com", "www.bing.com", "search.brave.com"))) return deny("Web search is restricted.")
        if ((host == "duckduckgo.com" || host.endsWith(".duckduckgo.com")) && (uri.path == "/ac" || uri.path.orEmpty().startsWith("/ac/"))) return deny("Search suggestions are disabled.")
        if (topLevel && normalizeSearch) {
            val normalized = normalizeSearch(uri) ?: return deny("Use a supported strict search without shortcut redirects.")
            if (normalized != uri.toString()) return decide(normalized, true, initiator, false)
        }
        suffixes(host).forEach { suffix ->
            baseline.domains[suffix]?.let { return deny("Blocked by mandatory ${it.replace('-', ' ')} protection.") }
            if (suffix in limits.domains) return deny("Blocked by an additional restriction.")
        }
        val path = try { URI(null, null, URI(uri.toString()).path, null).normalize().path.lowercase(Locale.ROOT).trimEnd('/') } catch (_: Exception) { return deny("Invalid destination path.") }
        baseline.paths.firstOrNull { (host == it.host || host.endsWith(".${it.host}")) && (path == it.path || path.startsWith("${it.path}/")) }?.let { return deny("Blocked by mandatory ${it.category.replace('-', ' ')} protection.") }
        if (!topLevel && host != canonicalWeb(initiator.orEmpty())?.host && suffixes(host).any { it in baseline.trackers }) return deny("Known tracking resource blocked.")
        return Decision(true, uri.toString())
    }
    private fun normalizeSearch(uri: Uri): String? {
        val host = uri.host.orEmpty()
        val isDdg = host == "duckduckgo.com" || host.endsWith(".duckduckgo.com") || host == "duck.com" || host == "www.duck.com" || host == "ddg.gg"
        if (isDdg && uri.path?.trimEnd('/') == "/l") {
            if (uri.getQueryParameters("uddg").size != 1) return null
            val target = canonicalWeb(uri.getQueryParameter("uddg") ?: return null) ?: return null
            if (target.scheme != "https" || target.host.orEmpty().endsWith("duckduckgo.com")) return null
            return target.toString()
        }
        val knownSearch = (host == "www.google.com" || host == "google.com" || host == "www.bing.com" || host == "bing.com" || host == "search.brave.com" || host == "safe.search.brave.com") && uri.path in listOf("/search", "/", "/images/search", "/videos/search", "/images", "/videos", "/news", "/ask")
        if (!isDdg && !knownSearch) return uri.toString()
        val path = uri.path.orEmpty().trimEnd('/')
        if (isDdg && path !in listOf("", "/html", "/lite")) return if (host == "safe.duckduckgo.com") uri.toString() else null
        if (uri.queryParameterNames.any { uri.getQueryParameters(it).size != 1 }) return null
        val query = uri.getQueryParameter("q")
        if (query == null) return if (isDdg) "https://safe.duckduckgo.com/?kp=1&kac=-1" else null
        val canonical = strictSearchURL(query) ?: return null
        if (!isDdg) return canonical
        val builder = Uri.parse(canonical).buildUpon().path(uri.path.ifNullOrEmpty("/"))
        uri.queryParameterNames.filter { it !in setOf("q", "kp", "kae", "kav", "kac", "kax", "safe") }.forEach { name -> builder.appendQueryParameter(name, uri.getQueryParameter(name)) }
        return builder.build().toString()
    }
}
private fun String?.ifNullOrEmpty(other: String) = if (this.isNullOrEmpty()) other else this

internal fun canonicalWeb(raw: String): Uri? {
    if (raw.isEmpty() || raw.length > 16384 || raw.any { it.code < 32 || it.code == 127 || it == '\\' }) return null
    return try {
        val uri = Uri.parse(raw)
        if (uri.scheme !in listOf("http", "https") || uri.userInfo != null || uri.host.isNullOrEmpty() || uri.port !in -1..65535 || uri.port == 0) return null
        val host = NativeGuardPolicy.normalizeHost(uri.host!!) ?: return null
        val authority = (if (host.contains(':')) "[$host]" else host) + (if (uri.port != -1) ":${uri.port}" else "")
        uri.buildUpon().encodedAuthority(authority).build()
    } catch (_: Exception) { null }
}
