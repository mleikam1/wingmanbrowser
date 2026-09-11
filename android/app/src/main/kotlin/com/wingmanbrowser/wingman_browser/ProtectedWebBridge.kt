package com.wingmanbrowser.wingman_browser

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.net.http.SslError
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.webkit.*
import android.widget.FrameLayout
import androidx.webkit.*
import io.flutter.FlutterInjector
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.net.HttpURLConnection
import java.net.URI
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/** A separate scriptless renderer. Its allow set comes only from the packaged catalog. */
class ProtectedWebBridge(private val context: Context, private val channel: MethodChannel) {
    companion object {
        const val VIEW_TYPE = "wingman/protected-web"
        const val CATALOG_ASSET = "assets/policy/live_sites.json"
        // Updated by the reviewed-catalog build tool; no method-channel setter exists.
        const val CATALOG_SHA256 = "7937170f4c5605faff4e7fbfcc0ea4f27623b05a75c84e6adc8aba2243f965c1"
        private const val MAX_PAGE_BYTES = 12 * 1024 * 1024
        private const val MAX_REQUESTS = 80
        private const val CSP = "default-src 'none'; script-src 'none'; img-src https:; style-src 'unsafe-inline' https:; font-src https:; connect-src 'none'; frame-src 'none'; child-src 'none'; object-src 'none'; media-src 'none'; base-uri 'none'; form-action 'none'; sandbox allow-same-origin"
    }
    private val views = mutableMapOf<Int, ProtectedView>()
    private val policy by lazy { Catalog(context) }
    @Volatile private var ready = false
    @Volatile private var foreground = true
    @Volatile private var denied = false
    @Volatile private var cleanupPending = false
    private val loadedProfiles = mutableMapOf<String, Profile>()
    private val purgedProfiles = mutableSetOf<String>()
    private val profilePurgeWaiters = mutableMapOf<String, MutableList<(Boolean) -> Unit>>()
    @Volatile private var profilePurgeFailed = false

    // Android cannot unregister a profile loaded in this process. Purge its
    // storage explicitly now; the next startup unregisters the empty UUID name.
    private fun purgeProfile(name: String, completion: (Boolean) -> Unit = {}) {
        if (name in purgedProfiles) { completion(true); return }
        profilePurgeWaiters[name]?.let { it.add(completion); return }
        val profile = loadedProfiles[name] ?: run { completion(false); return }
        profilePurgeWaiters[name] = mutableListOf(completion)
        fun finish(success: Boolean) {
            if (success) purgedProfiles.add(name) else profilePurgeFailed = true
            profilePurgeWaiters.remove(name)?.forEach { it(success) }
            if (!success) closeAll()
        }
        try {
            WebStorageCompat.deleteBrowsingData(profile.webStorage) {
                try {
                    profile.cookieManager.removeAllCookies {
                        try { profile.cookieManager.flush(); finish(true) }
                        catch (_: Exception) { finish(false) }
                    }
                } catch (_: Exception) { finish(false) }
            }
        } catch (_: Exception) { finish(false) }
    }
    fun purgeRetiredProfiles(completion: (Boolean) -> Unit) {
        if (!privateAvailable()) { completion(true); return }
        val store = ProfileStore.getInstance()
        val names = store.allProfileNames.filter { it.startsWith("wingman_private_") }
        if (names.isEmpty()) { completion(true); return }
        var remaining = names.size
        var success = true
        fun finished(ok: Boolean) { success = success && ok; remaining--; if (remaining == 0) completion(success) }
        names.forEach { name ->
            if (loadedProfiles.containsKey(name)) purgeProfile(name, ::finished)
            else try { store.deleteProfile(name); finished(true) } catch (_: Exception) { finished(false) }
        }
    }
    val factory = object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
            val values = args as? Map<*, *> ?: emptyMap<Any, Any>()
            val view = ProtectedView(context, viewId, values["tabId"] as? String ?: "", values["private"] == true)
            views[viewId] = view
            return view
        }
    }
    init { channel.setMethodCallHandler(::handle) }
    fun quarantineCompleted() { ready = true }
    fun cleanupStarted() { cleanupPending = true; closeAll() }
    fun cleanupFinished() { cleanupPending = false }
    fun hideAll() { denied = true; views.values.toList().forEach { it.release() } }
    fun restoreOwner() { denied = false }
    fun pauseAll() { foreground = false; views.values.toList().forEach { it.release() } }
    fun resume() { foreground = true }
    fun closeAll() { views.values.toList().forEach { it.release() } }
    private fun privateAvailable() = WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE) && WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA)
    private fun mayOpen() = ready && foreground && !denied && !cleanupPending && !profilePurgeFailed && policy.valid()
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (call.method == "capabilities") {
                val supported = ready && !cleanupPending && !profilePurgeFailed && policy.valid()
                result.success(mapOf("supported" to supported, "privateAvailable" to (supported && privateAvailable()), "mode" to "reviewedScriptlessWeb", "reason" to if (supported) null else "Reviewed website protection is unavailable.")); return
            }
            if (call.method == "state" && call.argument<Number>("viewId") == null) {
                result.success(mapOf("views" to views.values.count { it.web != null }, "ready" to ready, "foreground" to foreground, "handoffBlocked" to denied, "cleanupPending" to cleanupPending, "catalogValid" to policy.valid(), "profilePurgesPending" to profilePurgeWaiters.size, "profilePurgesCompleted" to purgedProfiles.size, "profilePurgeFailed" to profilePurgeFailed, "profilesRemaining" to if (privateAvailable()) ProfileStore.getInstance().allProfileNames.count { it.startsWith("wingman_private_") } else null)); return
            }
            val view = views[call.argument<Number>("viewId")?.toInt()] ?: throw IllegalStateException()
            when (call.method) {
                "open", "reload" -> {
                    check(mayOpen())
                    val url = call.argument<String>("url") ?: view.currentUrl
                    val requestId = call.argument<Number>("requestId")?.toLong() ?: throw IllegalStateException()
                    view.open(url, requestId)
                    result.success(null)
                }
                "stop" -> { view.suspendView(); result.success(null) }
                "close" -> { view.release(); views.remove(view.id); result.success(null) }
                "setActive" -> { if (call.argument<Boolean>("active") != true) view.suspendView() else view.activate(); result.success(null) }
                "state" -> view.diagnosticState(result)
                else -> result.error("protected_method_unavailable", "This browser operation is unavailable.", null)
            }
        } catch (_: Exception) { result.error("protected_navigation_denied", "This page is outside the current reviewed website scope.", null) }
    }

    private inner class ProtectedView(context: Context, val id: Int, val tabId: String, val privateMode: Boolean) : PlatformView {
        private val container = FrameLayout(context)
        @Volatile var web: WebView? = null
        var currentUrl = ""
        private var requestId = 0L
        private var active = false
        private var disposed = false
        private var profileName: String? = null
        private var site: Site? = null
        private var epoch = 0L
        private var requests = 0
        private var networkRequests = 0
        private var byteCount = 0
        private var reservedBytes = 0
        private var loaded = 0
        private var blocked = 0
        private var progress = 0
        private var loading = false
        private var error: String? = null
        private var title = ""
        private var loadedImages = 0
        private var decodedImages = 0
        private var expiryTask: Runnable? = null
        private var deadlineNanos = 0L
        private val connections = mutableSetOf<HttpURLConnection>()
        private val lock = Any()
        override fun getView(): View = container
        override fun dispose() { release(); disposed = true; views.remove(id) }
        fun state(): Map<String, Any?> = synchronized(lock) { mapOf("viewId" to id, "requestId" to requestId, "url" to currentUrl, "title" to title, "progress" to progress, "isLoading" to loading, "error" to error, "blockedResources" to blocked, "loadedResources" to loaded, "bytesReceived" to byteCount, "requests" to requests, "requestAttempts" to requests, "networkRequests" to networkRequests, "hasRenderer" to (web != null), "private" to privateMode, "javascript" to (web?.settings?.javaScriptEnabled ?: false), "networkFallback" to false, "engineNetworkBlocked" to (web?.settings?.blockNetworkLoads ?: true), "loadedImageResponses" to loadedImages, "decodedImageResponses" to decodedImages) }
        fun diagnosticState(result: MethodChannel.Result) {
            // Android disables even app-requested script evaluation when JavaScript is off.
            // Do not briefly enable it for diagnostics; decoded native image responses are counted instead.
            result.success(state().toMutableMap().apply { put("imagesTotal", null); put("imagesComplete", null) })
        }
        private fun emit() { container.post { if (!disposed) channel.invokeMethod("pageState", state()) } }
        fun open(raw: String, request: Long) {
            check(!disposed && mayOpen() && tabId.isNotEmpty() && tabId.length <= 100 && (!privateMode || privateAvailable()))
            val canonical = canonical(raw) ?: throw IllegalStateException()
            val match = policy.document(canonical) ?: throw IllegalStateException()
            check(request > requestId)
            release()
            synchronized(lock) { currentUrl = raw; requestId = request; site = match; epoch++; active = true; requests = 0; networkRequests = 0; byteCount = 0; reservedBytes = 0; loaded = 0; loadedImages = 0; decodedImages = 0; blocked = 0; error = null; progress = 0; loading = true; title = match.title; deadlineNanos = System.nanoTime() + 45_000_000_000L }
            val view = object : WebView(container.context) {
                override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection? = null
                override fun onCheckIsTextEditor() = false
            }
            web = view
            WebView.setWebContentsDebuggingEnabled(false)
            if (privateAvailable()) {
                // Both modes use disposable cookie-free profiles; application saves live in Flutter.
                val name = "wingman_private_${UUID.randomUUID()}"
                WebViewCompat.setProfile(view, name)
                profileName = name
                loadedProfiles[name] = WebViewCompat.getProfile(view)
            } else check(!privateMode)
            with(view.settings) {
                // Only our native exact-URL fetcher may supply network responses.
                // Chromium still invokes interception with its own network disabled.
                blockNetworkLoads = true
                javaScriptEnabled = false; javaScriptCanOpenWindowsAutomatically = false
                allowFileAccess = false; allowContentAccess = false
                @Suppress("DEPRECATION")
                allowFileAccessFromFileURLs = false
                @Suppress("DEPRECATION")
                allowUniversalAccessFromFileURLs = false
                domStorageEnabled = false; databaseEnabled = false
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                cacheMode = WebSettings.LOAD_NO_CACHE
                setSupportMultipleWindows(true); mediaPlaybackRequiresUserGesture = true
                @Suppress("DEPRECATION")
                saveFormData = false
                setGeolocationEnabled(false)
                disabledActionModeMenuItems = WebSettings.MENU_ITEM_SHARE or WebSettings.MENU_ITEM_WEB_SEARCH or WebSettings.MENU_ITEM_PROCESS_TEXT
            }
            if (WebViewFeature.isFeatureSupported(WebViewFeature.SAFE_BROWSING_ENABLE)) WebSettingsCompat.setSafeBrowsingEnabled(view.settings, true)
            val cookies = if (profileName != null) WebViewCompat.getProfile(view).cookieManager else CookieManager.getInstance()
            cookies.setAcceptCookie(false); cookies.setAcceptThirdPartyCookies(view, false)
            view.isLongClickable = false
            view.setOnLongClickListener { true }
            if (Build.VERSION.SDK_INT >= 26) view.importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            view.webChromeClient = object : WebChromeClient() {
                override fun onConsoleMessage(message: ConsoleMessage?) = true
                override fun onProgressChanged(view: WebView, value: Int) { if (view === web && active) { progress = value; emit() } }
                override fun onReceivedTitle(view: WebView, value: String?) { /* Only reviewed titles enter application metadata. */ }
                override fun onCreateWindow(view: WebView?, isDialog: Boolean, isUserGesture: Boolean, resultMsg: android.os.Message?) = false
                override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
                override fun onGeolocationPermissionsShowPrompt(origin: String?, callback: GeolocationPermissions.Callback) { callback.invoke(origin, false, false) }
                override fun onShowFileChooser(view: WebView?, callback: ValueCallback<Array<Uri>>?, params: FileChooserParams?): Boolean { callback?.onReceiveValue(null); return true }
            }
            val generation = synchronized(lock) { epoch }
            view.webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse = intercept(request, generation, view)
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    if (view === web && active && request.isForMainFrame && request.hasGesture() && request.method == "GET") {
                        canonical(request.url.toString())?.let { channel.invokeMethod("navigationRequested", mapOf("viewId" to id, "requestId" to requestId, "url" to request.url.toString())) }
                    }
                    return true
                }
                @Suppress("DEPRECATION")
                override fun shouldOverrideUrlLoading(view: WebView, url: String) = true
                override fun onPageFinished(view: WebView, url: String) { if (view === web && active && error == null) { loading = false; progress = 100; emit() } }
                override fun onReceivedSslError(view: WebView?, handler: SslErrorHandler, error: SslError?) { handler.cancel(); if (view === web) fail() }
                override fun onReceivedHttpAuthRequest(view: WebView?, handler: HttpAuthHandler, host: String?, realm: String?) { handler.cancel() }
                override fun onReceivedClientCertRequest(view: WebView?, request: ClientCertRequest) { request.cancel() }
                override fun onReceivedError(view: WebView, request: WebResourceRequest, failure: WebResourceError) { if (view === web && request.isForMainFrame) fail() }
                override fun onSafeBrowsingHit(view: WebView, request: WebResourceRequest, threatType: Int, callback: SafeBrowsingResponse) { callback.backToSafety(false); if (view === web && request.isForMainFrame) fail() }
                override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean { if (view === web) { release(); channel.invokeMethod("rendererGone", mapOf("viewId" to id, "requestId" to requestId)) }; return true }
            }
            view.setDownloadListener { _, _, _, _, _ -> if (view === web) fail() }
            container.addView(view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            emit()
            val expiry = Runnable { if (web === view) fail() }
            expiryTask = expiry
            container.postDelayed(expiry, (match.expires - System.currentTimeMillis()).coerceAtLeast(1L))
            view.loadUrl(raw)
        }
        private fun intercept(request: WebResourceRequest, capture: Long, owner: WebView): WebResourceResponse {
            fun deny(): WebResourceResponse {
                synchronized(lock) { if (capture == epoch) blocked++ }
                if (request.isForMainFrame) container.post { if (capture == epoch) fail() } else emit()
                return WebResourceResponse("text/plain", "UTF-8", 403, "Unavailable", mapOf("Cache-Control" to "no-store"), ByteArrayInputStream(ByteArray(0)))
            }
            val url = canonical(request.url.toString()) ?: return deny()
            val entry = synchronized(lock) {
                if (owner !== web || !active || !mayOpen() || capture != epoch || request.method != "GET" || ++requests > MAX_REQUESTS) null
                else if (request.isForMainFrame && url == canonical(currentUrl)) site?.documents?.get(url)
                else if (policy.resourceDenied(url, currentUrl)) null else site?.resources?.get(url)
            } ?: return deny()
            // Never return null: Chromium has no fallback network permission for a resource.
            var connection: HttpURLConnection? = null
            try {
                check(java.net.CookieHandler.getDefault() == null)
                connection = URI(url).toURL().openConnection() as HttpURLConnection
                synchronized(lock) { check(active && capture == epoch); connections.add(connection) }
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 12_000; connection.readTimeout = 12_000
                connection.useCaches = false
                connection.requestMethod = "GET"
                connection.setRequestProperty("Accept", entry.mimeTypes.joinToString(","))
                connection.setRequestProperty("Accept-Encoding", "identity")
                connection.setRequestProperty("DNT", "1")
                connection.setRequestProperty("Sec-GPC", "1")
                connection.setRequestProperty("User-Agent", "Wingman/0.8 (Protected Visual Browsing)")
                connection.setRequestProperty("Cache-Control", "no-store")
                // Redirects are deliberately rejected; they must be explicitly reviewed as a document URL.
                synchronized(lock) { check(active && capture == epoch && mayOpen()); networkRequests++ }
                check(connection.responseCode == 200)
                val mime = connection.contentType?.substringBefore(';')?.trim()?.lowercase() ?: ""
                check(mime in entry.mimeTypes)
                check(connection.getHeaderField("Content-Disposition")?.lowercase()?.contains("attachment") != true)
                check(connection.contentLengthLong <= entry.maxBytes)
                val bytes = connection.inputStream.use { input ->
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(16 * 1024)
                    while (true) {
                        val size = synchronized(lock) {
                            check(active && capture == epoch && mayOpen() && System.nanoTime() < deadlineNanos)
                            val available = MAX_PAGE_BYTES - byteCount - reservedBytes
                            check(available > 0)
                            minOf(buffer.size, available).also { reservedBytes += it }
                        }
                        val count: Int
                        try { count = input.read(buffer, 0, size) }
                        catch (failure: Exception) { synchronized(lock) { if (capture == epoch) reservedBytes -= size }; throw failure }
                        synchronized(lock) {
                            check(active && capture == epoch && mayOpen())
                            reservedBytes -= size
                            if (count > 0) byteCount += count
                        }
                        if (count < 0) break
                        check(output.size() + count <= entry.maxBytes)
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                }
                var decodedRaster = false
                if (mime.startsWith("image/") && mime != "image/svg+xml") {
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                    check(bounds.outWidth in 1..10_000 && bounds.outHeight in 1..10_000 && bounds.outWidth.toLong() * bounds.outHeight <= 40_000_000)
                    val options = BitmapFactory.Options().apply { inSampleSize = 1 }
                    while (bounds.outWidth / options.inSampleSize > 512 || bounds.outHeight / options.inSampleSize > 512) options.inSampleSize *= 2
                    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
                    check(bitmap != null)
                    decodedRaster = true
                    bitmap.recycle()
                }
                synchronized(lock) { check(active && capture == epoch && mayOpen()); loaded++; if (mime.startsWith("image/")) loadedImages++; if (decodedRaster) decodedImages++ }
                val headers = mutableMapOf("Cache-Control" to "no-store", "X-Content-Type-Options" to "nosniff", "Referrer-Policy" to "no-referrer", "Content-Security-Policy" to CSP)
                connection.getHeaderField("Content-Security-Policy")?.let { headers["Content-Security-Policy"] = "$CSP, $it" }
                emit()
                return WebResourceResponse(mime, if (mime.startsWith("text/")) "UTF-8" else null, 200, "OK", headers, ByteArrayInputStream(bytes))
            } catch (_: Exception) { return deny() }
            finally { connection?.disconnect(); synchronized(lock) { connections.remove(connection) } }
        }
        private fun fail() { release(); error = "This page could not load within its reviewed website scope."; emit() }
        fun suspendView() { release() }
        fun activate() { /* Resuming requires an explicit new open and current policy checks. */ }
        fun release() {
            val pendingConnections = synchronized(lock) { active = false; epoch++; loading = false; connections.toList().also { connections.clear() } }
            pendingConnections.forEach { it.disconnect() }
            expiryTask?.let { container.removeCallbacks(it) }; expiryTask = null
            val old = web; web = null
            old?.stopLoading(); old?.visibility = View.INVISIBLE
            container.removeAllViews()
            old?.removeAllViews(); old?.destroy()
            val name = profileName; profileName = null
            if (name != null && privateAvailable()) {
                // Destruction is immediate; storage cleanup is separately acknowledged.
                purgeProfile(name)
            }
        }
    }

    private data class Entry(val url: String, val mimeTypes: Set<String>, val maxBytes: Int)
    private data class Site(val title: String, val expires: Long, val documents: Map<String, Entry>, val resources: Map<String, Entry>)
    private class Catalog(context: Context) {
        private var sites = emptyList<Site>()
        private var expires = 0L
        private var privacyDomains = emptySet<String>()
        init {
            try {
                val path = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(CATALOG_ASSET)
                val bytes = context.assets.open(path).use { it.readBytes() }
                check(bytes.size <= 512 * 1024)
                val hash = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
                check(hash == CATALOG_SHA256)
                val json = JSONObject(String(bytes, Charsets.UTF_8))
                check(json.getInt("schemaVersion") == 1 && json.getInt("policyVersion") == 1 && json.getInt("sequence") > 0)
                expires = timestamp(json.getString("expiresAt"))
                check(timestamp(json.getString("reviewedAt")) <= System.currentTimeMillis())
                val domains = json.getJSONObject("privacy").getJSONArray("domains")
                privacyDomains = (0 until domains.length()).map { domains.getString(it) }.toSet()
                val rows = json.getJSONArray("sites")
                sites = (0 until rows.length()).mapNotNull { index ->
                    val row = rows.getJSONObject(index)
                    if (!row.getBoolean("enabled")) return@mapNotNull null
                    fun entries(name: String): Map<String, Entry> {
                        val data = row.getJSONArray(name)
                        return (0 until data.length()).map { i ->
                            val item = data.getJSONObject(i)
                            val url = item.getString("url")
                            check(canonical(url) == url)
                            val types = item.getJSONArray("mimeTypes")
                            val mime = (0 until types.length()).map { types.getString(it) }.toSet()
                            check(mime.isNotEmpty() && mime.all { it in setOf("text/html", "text/css", "image/jpeg", "image/png", "image/webp", "image/gif", "image/svg+xml", "font/woff", "font/woff2", "application/font-woff", "application/octet-stream") })
                            val max = item.getInt("maxBytes"); check(max in 1..(4 * 1024 * 1024))
                            if (name == "resources") check(item.getString("type") in setOf("image", "styleSheet", "font"))
                            url to Entry(url, mime, max)
                        }.toMap()
                    }
                    check(timestamp(row.getString("reviewedAt")) <= System.currentTimeMillis())
                    Site(row.getString("title"), minOf(timestamp(row.getString("expiresAt")), expires), entries("documents"), entries("resources"))
                }
            } catch (_: Exception) { sites = emptyList(); expires = 0L }
        }
        fun valid() = System.currentTimeMillis() < expires && sites.any { System.currentTimeMillis() < it.expires }
        fun document(url: String) = if (!valid()) null else sites.firstOrNull { System.currentTimeMillis() < it.expires && url in it.documents }
        fun resourceDenied(url: String, document: String): Boolean {
            val host = URI(url).host ?: return true
            if (host == URI(document).host) return false
            return privacyDomains.any { host == it || host.endsWith(".$it") }
        }
    }
}

private fun canonical(raw: String): String? {
    if (raw.isEmpty() || raw.length > 16_384 || raw.any { it.code < 33 || it.code > 126 || it == '\\' }) return null
    return try {
        val uri = URI(raw)
        if (uri.scheme != "https" || uri.rawUserInfo != null || uri.port != -1 || uri.host.isNullOrEmpty() || uri.host != uri.host.lowercase() || uri.host.endsWith('.') || Regex("%(00|0a|0d|2f|5c)", RegexOption.IGNORE_CASE).containsMatchIn(uri.rawPath) || uri.path.split('/').any { it == "." || it == ".." } || uri.normalize().rawPath != uri.rawPath) null
        else if (uri.rawPath.isEmpty()) "https://${uri.rawAuthority}/" + (uri.rawQuery?.let { "?$it" } ?: "") else raw.substringBefore('#')
    } catch (_: Exception) { null }
}

private fun timestamp(raw: String): Long {
    check(raw.matches(Regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")))
    val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.ROOT)
    format.timeZone = TimeZone.getTimeZone("UTC")
    format.isLenient = false
    return checkNotNull(format.parse(raw)).time
}
