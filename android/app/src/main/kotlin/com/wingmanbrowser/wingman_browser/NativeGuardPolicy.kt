package com.wingmanbrowser.wingman_browser

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.icu.text.IDNA
import android.net.Uri
import java.io.File
import java.util.Locale
import java.net.InetAddress

/** Read-only indexed policy lookup. No networking, URL log or page-script bridge. */
class NativeGuardPolicy(private val context: Context) {
    private var database: SQLiteDatabase? = null
    private var databasePath: String? = null
    @Volatile private var config: Map<String, Any?> = emptyMap()

    @Synchronized fun update(next: Map<String, Any?>) {
        val path = next["databasePath"] as? String
        if (path != databasePath) {
            val replacement = if (path == null) null else {
                val file = File(path).canonicalFile
                check(file.path.startsWith(File(context.applicationInfo.dataDir).canonicalPath + "/") && file.isFile)
                SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS).also {
                    try { it.rawQuery("SELECT active_generation, active_version FROM guard_state WHERE id=1", null).use { cursor -> check(cursor.moveToFirst()) } }
                    catch (error: Exception) { it.close(); throw error }
                }
            }
            val old = database
            database = replacement; databasePath = path
            old?.close()
        }
        config = next.toMap()
    }

    private fun hosts(key: String): List<String> = (config[key] as? List<*>)?.filterIsInstance<String>() ?: emptyList()
    private fun matches(host: String, root: String) = host == root || (!root.contains(':') && host.endsWith(".$root"))
    private fun matchesAny(host: String, values: List<String>) = values.any { matches(host, it) }

    /** Called only for main-frame navigations/downloads, never every resource. */
    @Synchronized fun evaluate(url: String, tabId: String, filename: String? = null, mimeType: String? = null): Map<String, Any?>? {
        val uri = Uri.parse(url)
        if (uri.scheme !in listOf("http", "https")) return null
        val host = (if (uri.userInfo == null) normalizeHost(uri.host ?: "") else null) ?: return mapOf("action" to "requireAdditionalCheck", "host" to "", "ruleId" to "invalid-domain", "overrideAllowed" to false)
        val rules = mutableListOf<Rule>()
        var version: String? = null
        var lookupFailed = false
        try { database?.let { db ->
            val labels = host.split('.')
            val suffixes = if (host.contains(':') || host.matches(Regex("^[0-9.]+$"))) listOf(host) else
                (0 until (if (labels.size == 1) 1 else labels.size - 1)).map { labels.drop(it).joinToString(".") }
            val placeholders = suffixes.joinToString(",") { "?" }
            db.rawQuery("SELECT r.host,r.kind,r.category,r.include_subdomains,r.rule_id,s.active_version FROM guard_rules r JOIN guard_state s ON r.generation=s.active_generation WHERE s.id=1 AND r.host IN ($placeholders) ORDER BY length(r.host) DESC, r.kind, r.category", suffixes.toTypedArray()).use { cursor ->
                while (cursor.moveToNext()) {
                    if (cursor.getString(0) != host && cursor.getInt(3) != 1) continue
                    rules.add(Rule(cursor.getString(1), cursor.getString(2), cursor.getString(4)))
                    version = cursor.getString(5)
                }
            }
        }
        } catch (_: Exception) { lookupFailed = true; rules.clear() }
        fun blocked(action: String, category: String?, ruleId: String?, security: Boolean = false) = mapOf<String, Any?>(
            "action" to action, "host" to host, "category" to category,
            "ruleId" to ruleId, "packVersion" to version,
            "overrideAllowed" to (!security && config["overridesLocked"] != true),
        )
        rules.firstOrNull { it.kind == "malware" }?.let { return blocked("blockMalware", "malware", it.id, true) }
        rules.firstOrNull { it.kind == "phishing" }?.let { return blocked("blockPhishing", "phishing", it.id, true) }
        if (filename != null) {
            rules.firstOrNull { it.kind == "harmful-download" }?.let { return blocked("blockHarmfulDownload", "harmful-downloads", it.id, true) }
        }
        val grant = ((config["allowOnce"] as? Map<*, *>)?.get(tabId) as? List<*>)?.filterIsInstance<String>() ?: emptyList()
        val expires = (((config["allowOnceExpires"] as? Map<*, *>)?.get(tabId) as? Map<*, *>)?.get(host) as? Number)?.toLong() ?: 0L
        val onceAllowed = config["overridesLocked"] != true && host in grant && expires > System.currentTimeMillis()
        val customBlock = hosts("customBlock").filter { matches(host, it) }.maxByOrNull { it.length }
        val customAllow = hosts("customAllow").filter { matches(host, it) }.maxByOrNull { it.length }
        if (customBlock != null && (customAllow == null || customBlock.length >= customAllow.length) && !onceAllowed) return blocked("blockCustomRule", null, "custom-block")
        if (lookupFailed) return blocked("requireAdditionalCheck", null, "local-rules-unavailable", true)
        if (filename != null && config["blockHarmfulDownloads"] == true && riskyDownload(filename, mimeType)) {
            return blocked("requireAdditionalCheck", "harmful-downloads", "executable-download-type")
        }
        if (customAllow != null || onceAllowed) return null
        val focusUntil = (config["focusUntilEpochMs"] as? Number)?.toLong() ?: 0L
        val focus = focusUntil > System.currentTimeMillis()
        if (focus && matchesAny(host, hosts("focusHosts"))) return blocked("blockCustomRule", null, "focus-site")
        if (rules.any { it.kind == "support" }) return null
        val categories = if (config["guardEnabled"] == true) hosts("enabledCategories").toSet() else emptySet()
        val focusCategories = if (focus) hosts("focusCategories").toSet() else emptySet()
        rules.firstOrNull { it.kind == "category" && (it.category in categories || it.category in focusCategories) }?.let {
            return blocked("blockCategory", it.category, it.id)
        }
        return null
    }

    fun safeSearch(raw: String): String {
        if (config["guardEnabled"] != true || "adult" !in hosts("enabledCategories")) return raw
        val uri = Uri.parse(raw)
        if (uri.scheme !in setOf("http", "https") || uri.userInfo != null || uri.port !in setOf(-1, 80, 443)) return raw
        val host = uri.host?.lowercase(Locale.ROOT)?.removeSuffix(".") ?: return raw
        val path = uri.path ?: ""
        val target: Triple<String, String, String> = when {
            host in setOf("duckduckgo.com", "www.duckduckgo.com", "safe.duckduckgo.com", "html.duckduckgo.com", "lite.duckduckgo.com") && path in setOf("", "/", "/html", "/html/", "/lite", "/lite/") -> Triple("safe.duckduckgo.com", "kp", "1")
            host in setOf("google.com", "www.google.com") && path == "/search" -> Triple(host, "safe", "active")
            host in setOf("bing.com", "www.bing.com") && path in setOf("/search", "/images/search", "/videos/search") -> Triple(host, "adlt", "strict")
            host in setOf("search.brave.com", "safe.search.brave.com") && path in setOf("/search", "/images", "/videos", "/news", "/ask") -> Triple("safe.search.brave.com", "safesearch", "strict")
            else -> return raw
        }
        if (uri.scheme == "https" && uri.port != 80 && uri.host == target.first && uri.getQueryParameters(target.second) == listOf(target.third)) return raw
        val query = (uri.encodedQuery?.split('&') ?: emptyList()).filter { Uri.decode(it.substringBefore('=')) != target.second }.toMutableList()
        query.add(Uri.encode(target.second) + "=" + Uri.encode(target.third))
        return uri.buildUpon().scheme("https").encodedAuthority(target.first).encodedQuery(query.joinToString("&")).build().toString()
    }

    /** The licensed list consists of domain rules with third-party scope only. */
    fun isTracker(url: String, topHost: String): Boolean {
        if (config["trackingEnabled"] != true || matchesAny(topHost, hosts("trackingExceptions"))) return false
        val uri = Uri.parse(url)
        if (uri.scheme !in listOf("http", "https")) return false
        val host = uri.host?.lowercase(Locale.ROOT)?.trimEnd('.') ?: return false
        return hosts("trackerDomains").any { matches(host, it) && !matches(topHost, it) }
    }

    private data class Rule(val kind: String, val category: String, val id: String)
    companion object {
        private val idna = IDNA.getUTS46Instance(IDNA.NONTRANSITIONAL_TO_ASCII or IDNA.USE_STD3_RULES or IDNA.CHECK_BIDI or IDNA.CHECK_CONTEXTJ)
        fun normalizeHost(input: String): String? {
            if (input.isEmpty() || input.length > 1024 || input.any { it.isWhitespace() || it.code < 33 || it.code == 127 || it in "/\\@?#%" }) return null
            var raw = input.lowercase(Locale.ROOT)
            if (raw.startsWith('[') && raw.endsWith(']')) raw = raw.substring(1, raw.length - 1)
            if (raw.contains(':')) {
                if (!raw.matches(Regex("^[0-9a-f:.]+$"))) return null
                val bytes = try { InetAddress.getByName(raw).address } catch (_: Exception) { return null }
                val ipv6 = if (bytes.size == 4) ByteArray(16).also { it[10] = -1; it[11] = -1; bytes.copyInto(it, 12) } else bytes
                if (ipv6.size != 16) return null
                val words = (0..7).map { ((ipv6[it * 2].toInt() and 255) shl 8) or (ipv6[it * 2 + 1].toInt() and 255) }
                var best = -1; var length = 1; var i = 0
                while (i < 8) { if (words[i] != 0) { i++; continue }; val start = i; while (i < 8 && words[i] == 0) i++; if (i - start > length) { best = start; length = i - start } }
                if (best < 0) return words.joinToString(":") { it.toString(16) }
                return words.take(best).joinToString(":") { it.toString(16) } + "::" + words.drop(best + length).joinToString(":") { it.toString(16) }
            }
            val info = IDNA.Info()
            val output = StringBuilder()
            raw = raw.replace('\u3002', '.').replace('\uff0e', '.').replace('\uff61', '.').removeSuffix(".")
            idna.nameToASCII(raw, output, info)
            val host = output.toString().lowercase(Locale.ROOT)
            val labels = host.split('.')
            if (info.hasErrors() || host.isEmpty() || host.length > 253 || labels.any { it.isEmpty() || it.length > 63 || it.startsWith('-') || it.endsWith('-') }) return null
            if (labels.all { it.matches(Regex("^([0-9]+|0x[0-9a-f]+)$")) } && (labels.size != 4 || labels.any { !it.matches(Regex("^(0|[1-9][0-9]{0,2})$")) || (it.toIntOrNull() ?: 256) > 255 })) return null
            return host
        }
        fun riskyDownload(filename: String, mime: String?): Boolean {
            val extension = filename.substringAfterLast('.', "").lowercase(Locale.ROOT)
            return extension in setOf("exe", "msi", "scr", "com", "bat", "cmd", "ps1", "vbs", "js", "jar", "apk", "aab", "dmg", "pkg", "app", "deb", "rpm") ||
                mime?.substringBefore(';')?.lowercase(Locale.ROOT) in setOf("application/vnd.android.package-archive", "application/x-msdownload", "application/x-msi", "application/x-executable", "application/x-sh")
        }
    }
}
