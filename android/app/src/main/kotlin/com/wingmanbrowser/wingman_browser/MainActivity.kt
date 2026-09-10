package com.wingmanbrowser.wingman_browser

import android.Manifest
import android.app.AlertDialog
import android.app.DownloadManager
import android.app.role.RoleManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.GeolocationPermissions
import android.webkit.URLUtil
import android.webkit.WebSettings
import android.webkit.WebStorage
import android.webkit.WebView
import androidx.webkit.ProfileStore
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebStorageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterPlugin
import java.util.UUID
import com.google.android.gms.ads.MobileAds

/** Narrow, app-only platform channel. No JavaScript interface is installed. */
class MainActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private lateinit var engine: FlutterEngine
    private val profiles = mutableMapOf<Long, String>()
    private val destroyedViews = mutableSetOf<Long>()
    private val guardPolicy by lazy { NativeGuardPolicy(this) }
    private val guardSessions = mutableMapOf<Long, NativeGuardSession>()
    private var pendingLink: String? = null
    private var fileResult: MethodChannel.Result? = null
    private var permissionResult: MethodChannel.Result? = null
    private var requestedPermissions: Array<String> = emptyArray()
    private var initialized = false
    private var safeBrowsingReady: Boolean? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        engine = flutterEngine
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wingman/browser")
        channel.setMethodCallHandler(::handle)
        pendingLink = validWebUrl(intent?.dataString)
        WebView.setWebContentsDebuggingEnabled((applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0)
        // Delete abandoned private profiles before any are loaded in this process.
        if (WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
            val store = ProfileStore.getInstance()
            store.allProfileNames.filter { it.startsWith("wingman_private_") }.forEach {
                try { store.deleteProfile(it) } catch (_: IllegalStateException) { /* active hot restart */ }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        validWebUrl(intent.dataString)?.let {
            if (initialized) channel.invokeMethod("incomingUri", it) else pendingLink = it
        }
    }

    private fun validWebUrl(value: String?): String? {
        if (value == null || value.length > 16384) return null
        val uri = Uri.parse(value)
        return if (uri.scheme in listOf("http", "https") && !uri.host.isNullOrBlank()
            && uri.userInfo == null) value else null
    }

    private fun webView(call: MethodCall): WebView {
        val id = call.argument<Number>("id")!!.toLong()
        val plugin = engine.plugins.get(WebViewFlutterPlugin::class.java) as WebViewFlutterPlugin
        return plugin.instanceManager!!.getInstance<WebView>(id)
            ?: throw IllegalStateException("Browser view unavailable")
    }

    private fun privateAvailable(): Boolean =
        WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE) &&
        WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA)

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> { initialized = true; result.success(pendingLink); pendingLink = null }
                "privateAvailable" -> result.success(privateAvailable())
                "guardBenchmarkForTesting" -> {
                    check((applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0)
                    val samples = (0 until 1000).map { index ->
                        val start = System.nanoTime()
                        guardPolicy.evaluate("https://sub.host-${(index * 997 % 100000).toString().padStart(6, '0')}.benchmark.test/", "performance")
                        (System.nanoTime() - start) / 1000.0
                    }.sorted()
                    result.success(mapOf("count" to samples.size, "p50Micros" to samples[500], "p95Micros" to samples[950]))
                }
                "memoryForTesting" -> {
                    check((applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0)
                    val info = android.os.Debug.MemoryInfo(); android.os.Debug.getMemoryInfo(info)
                    val device = android.app.ActivityManager.MemoryInfo()
                    (getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager).getMemoryInfo(device)
                    result.success(mapOf("mainProcessPssKb" to info.totalPss, "deviceTotalMemoryMb" to device.totalMem / 1048576, "deviceAvailableMemoryMb" to device.availMem / 1048576))
                }
                "guardDecisionForTesting" -> {
                    check((applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0)
                    result.success(guardPolicy.evaluate(call.argument<String>("url") ?: "", call.argument<String>("tabId") ?: "", call.argument<String>("filename"), call.argument<String>("mimeType")))
                }
                "safeSearchForTesting" -> { check((applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0); result.success(guardPolicy.safeSearch(call.argument<String>("url") ?: "")) }
                "normalizeHost" -> result.success(NativeGuardPolicy.normalizeHost(call.argument<String>("host") ?: ""))
                "updateGuardPolicy" -> {
                    @Suppress("UNCHECKED_CAST")
                    guardPolicy.update(call.arguments as Map<String, Any?>)
                    result.success(null)
                }
                "prepareGuardNavigation" -> {
                    val id = call.argument<Number>("id")!!.toLong()
                    guardSessions[id]?.prepare(call.argument<String>("url") ?: "")
                    result.success(null)
                }
                "disablePublisherFirstPartyId" -> {
                    MobileAds.putPublisherFirstPartyIdEnabled(false)
                    result.success(null)
                }
                "configure" -> {
                    val web = webView(call)
                    val id = call.argument<Number>("id")!!.toLong()
                    val privateMode = call.argument<Boolean>("private") == true
                    val guard = NativeGuardSession(guardPolicy, call.argument<String>("tabId") ?: id.toString(),
                        blocked = { url, decision -> channel.invokeMethod("guardBlocked", mapOf("id" to id, "url" to url, "decision" to decision)) },
                        trackers = { count -> channel.invokeMethod("trackersBlocked", mapOf("id" to id, "count" to count)) })
                    guardSessions[id] = guard
                    if (privateMode) {
                        check(privateAvailable()) { "Private browsing needs an updated Android System WebView" }
                        val name = "wingman_private_${UUID.randomUUID()}"
                        WebViewCompat.setProfile(web, name)
                        profiles[id] = name
                    }
                    with(web.settings) {
                        allowFileAccess = false
                        // Block arbitrary provider-resource reads; file chooser uploads
                        // receive only the explicit user-selected URI grant.
                        allowContentAccess = false
                        @Suppress("DEPRECATION")
                        allowFileAccessFromFileURLs = false
                        @Suppress("DEPRECATION")
                        allowUniversalAccessFromFileURLs = false
                        mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                        javaScriptCanOpenWindowsAutomatically = false
                        // Open target=_blank in this tab. This avoids upstream's
                        // temporary default-profile popup WebView in private tabs.
                        setSupportMultipleWindows(false)
                        mediaPlaybackRequiresUserGesture = true
                        if (privateMode) cacheMode = WebSettings.LOAD_NO_CACHE
                        @Suppress("DEPRECATION")
                        saveFormData = false
                    }
                    if (WebViewFeature.isFeatureSupported(WebViewFeature.SAFE_BROWSING_ENABLE)) {
                        WebSettingsCompat.setSafeBrowsingEnabled(web.settings, true)
                    }
                    // Third-party cookies are unnecessary for Wingman and disabled for sites by default.
                    val cookies = if (privateMode) WebViewCompat.getProfile(web).cookieManager else CookieManager.getInstance()
                    cookies.setAcceptThirdPartyCookies(web, false)
                    check(WebViewFeature.isFeatureSupported(WebViewFeature.GET_WEB_VIEW_CLIENT)) { "An updated Android System WebView is required for local browser protection" }
                    if (WebViewFeature.isFeatureSupported(WebViewFeature.GET_WEB_VIEW_CLIENT)) {
                        val original = WebViewCompat.getWebViewClient(web)
                        val onRendererGone: (WebView) -> Unit = { failed ->
                            guardSessions.remove(id)?.close()
                            destroyedViews.add(id)
                            (failed.parent as? ViewGroup)?.removeView(failed)
                            failed.destroy()
                            profiles[id]?.let { name ->
                                ProfileStore.getInstance().getProfile(name)?.let { profile ->
                                    profile.geolocationPermissions.clearAll()
                                    WebStorageCompat.deleteBrowsingData(profile.webStorage) {}
                                }
                            }
                            channel.invokeMethod("rendererGone", id)
                        }
                        web.webViewClient = when {
                            Build.VERSION.SDK_INT >= 27 -> GuardedWebViewClient27(original, guard, onRendererGone)
                            Build.VERSION.SDK_INT >= 26 -> GuardedWebViewClient26(original, guard, onRendererGone)
                            else -> GuardedWebViewClient(original, guard)
                        }
                    }
                    web.setDownloadListener { url, userAgent, disposition, mimeType, _ ->
                        val filename = URLUtil.guessFileName(url, disposition, mimeType)
                        val decision = guardPolicy.evaluate(url, guard.tabId, filename, mimeType)
                        if (decision != null && (decision["action"] != "requireAdditionalCheck" || decision["overrideAllowed"] != true)) {
                            guard.report(web, url, decision)
                        } else {
                            offerDownload(url, userAgent, disposition, mimeType, privateMode, web, guard, decision != null)
                        }
                    }
                    if (safeBrowsingReady == null && WebViewFeature.isFeatureSupported(WebViewFeature.START_SAFE_BROWSING)) {
                        WebViewCompat.startSafeBrowsing(applicationContext) { ready ->
                            safeBrowsingReady = ready
                            if (!ready) channel.invokeMethod("message", "System threat checks are unavailable. Local Guard rules still apply.")
                            result.success(true)
                        }
                    } else {
                        if (safeBrowsingReady == null) {
                            safeBrowsingReady = false
                            channel.invokeMethod("message", "This WebView cannot report system threat-check readiness. Local Guard rules still apply.")
                        }
                        result.success(true)
                    }
                }
                "terminateRendererForTesting" -> {
                    check((applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0)
                    if (WebViewFeature.isFeatureSupported(WebViewFeature.GET_WEB_VIEW_RENDERER) &&
                        WebViewFeature.isFeatureSupported(WebViewFeature.WEB_VIEW_RENDERER_TERMINATE)) {
                        result.success(WebViewCompat.getWebViewRenderProcess(webView(call))?.terminate() == true)
                    } else result.success(false)
                }
                "hideForGuard" -> { val web = webView(call); web.stopLoading(); web.visibility = android.view.View.INVISIBLE; result.success(null) }
                "stop" -> { webView(call).stopLoading(); result.success(null) }
                "find" -> { webView(call).findAllAsync(call.argument<String>("query") ?: ""); result.success(null) }
                "findNext" -> { webView(call).findNext(call.argument<Boolean>("forward") != false); result.success(null) }
                "pause" -> { webView(call).onPause(); result.success(null) }
                "resume" -> { webView(call).onResume(); result.success(null) }
                "close" -> closeView(call, result)
                "clearData" -> clearData(call, result)
                "chooseFiles" -> {
                    if (fileResult != null) { result.success(emptyList<String>()); return }
                    fileResult = result
                    val types = call.argument<List<String>>("types")?.filter { it.contains('/') && !it.contains(';') } ?: emptyList()
                    val pick = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = if (types.size == 1) types.first() else "*/*"
                        if (types.size > 1) putExtra(Intent.EXTRA_MIME_TYPES, types.toTypedArray())
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, call.argument<Boolean>("multiple") == true)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivityForResult(pick, 7201)
                }
                "requestPermissions" -> {
                    if (permissionResult != null) { result.success(false); return }
                    val names = call.argument<List<String>>("types") ?: emptyList()
                    val permissions = names.mapNotNull {
                        when (it) { "camera" -> Manifest.permission.CAMERA
                            "microphone" -> Manifest.permission.RECORD_AUDIO
                            "location" -> Manifest.permission.ACCESS_COARSE_LOCATION
                            else -> null }
                    }.distinct()
                    if (permissions.isEmpty()) { result.success(false); return }
                    requestedPermissions = permissions.toTypedArray()
                    if (permissions.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) result.success(true)
                    else { permissionResult = result; requestPermissions(requestedPermissions, 7202) }
                }
                "defaultBrowser" -> {
                    if (Build.VERSION.SDK_INT >= 29) {
                        val role = getSystemService(RoleManager::class.java)
                        if (role.isRoleAvailable(RoleManager.ROLE_BROWSER) && !role.isRoleHeld(RoleManager.ROLE_BROWSER)) {
                            startActivityForResult(role.createRequestRoleIntent(RoleManager.ROLE_BROWSER), 7203)
                        }
                    } else startActivity(Intent(android.provider.Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            // Never propagate a platform exception containing site URLs, cookies or file names.
            result.error("browser_operation_failed", "The browser operation could not be completed.", null)
        }
    }

    private fun closeView(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Number>("id")!!.toLong()
        guardSessions.remove(id)?.close()
        val web = if (destroyedViews.remove(id)) null else webView(call)
        web?.stopLoading()
        web?.loadUrl("about:blank")
        web?.clearHistory()
        val name = profiles.remove(id)
        fun destroy() {
            (web?.parent as? ViewGroup)?.removeView(web)
            web?.removeAllViews()
            web?.destroy()
            result.success(null)
        }
        if (name != null && privateAvailable()) {
            val profile = ProfileStore.getInstance().getProfile(name)
            profile?.geolocationPermissions?.clearAll()
            if (profile != null) {
                profile.cookieManager.removeAllCookies(null)
                WebStorageCompat.deleteBrowsingData(profile.webStorage) { destroy() }
            } else destroy()
            // Android disallows deleting a loaded Profile; empty directory is removed next process start.
        } else destroy()
    }

    private fun clearData(call: MethodCall, result: MethodChannel.Result) {
        val storage = call.argument<Boolean>("storage") == true
        val cookies = call.argument<Boolean>("cookies") == true
        if (call.argument<Boolean>("cache") == true) {
            val transient = WebView(this)
            transient.clearCache(true)
            transient.destroy()
        }
        if (storage) {
            GeolocationPermissions.getInstance().clearAll()
            if (WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA)) {
                // The UI discloses that complete site-data removal also clears cookies/cache.
                WebStorageCompat.deleteBrowsingData(WebStorage.getInstance()) { result.success(null) }
                return
            }
            WebStorage.getInstance().deleteAllData()
            channel.invokeMethod("message", "Basic site storage cleared. Update Android System WebView for complete service-worker data removal.")
        }
        if (cookies) CookieManager.getInstance().removeAllCookies { CookieManager.getInstance().flush(); result.success(null) }
        else result.success(null)
    }

    private fun offerDownload(raw: String, agent: String?, disposition: String?, mime: String?, privateMode: Boolean, web: WebView, guard: NativeGuardSession, executableWarning: Boolean) {
        val url = validWebUrl(raw) ?: run { channel.invokeMethod("message", "This download type is not supported."); return }
        val uri = Uri.parse(url)
        val filename = URLUtil.guessFileName(url, disposition, mime)
            .replace(Regex("[^A-Za-z0-9._ -]"), "_").trim('.', ' ').take(120).ifBlank { "download" }
        val initiatingUrl = web.url
        AlertDialog.Builder(this)
            .setTitle(if (executableWarning) "This file can run software" else "Download file?")
            .setMessage("${uri.host}\n$filename" +
                (if (executableWarning) "\nOnly download if you trust the source. The file type is risky; Wingman has not scanned its contents." else "") +
                (if (privateMode) "\nDownloaded files remain after closing private tabs." else ""))
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Download") { _, _ ->
                if (guard.closed || web.url != initiatingUrl) return@setPositiveButton
                val latest = guardPolicy.evaluate(url, guard.tabId, filename, mime)
                if (latest != null && (latest["action"] != "requireAdditionalCheck" || latest["overrideAllowed"] != true || !executableWarning)) {
                    guard.report(web, url, latest); return@setPositiveButton
                }
                try {
                    val request = DownloadManager.Request(uri)
                        .setTitle(filename).setMimeType(mime ?: "application/octet-stream")
                        .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)

                    if (Build.VERSION.SDK_INT >= 29) request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, filename)
                    else request.setDestinationInExternalFilesDir(this, Environment.DIRECTORY_DOWNLOADS, filename)
                    // Credentials are not copied into the OS download database. Authenticated downloads may fail.
                    if (!agent.isNullOrBlank() && !agent.contains('\n')) request.addRequestHeader("User-Agent", agent)
                    (getSystemService(DOWNLOAD_SERVICE) as DownloadManager).enqueue(request)
                    channel.invokeMethod("message", "Download started. See your device Downloads.")
                } catch (_: Exception) { channel.invokeMethod("message", "The download could not be started.") }
            }.show()
    }

    @Deprecated("Activity result compatibility for FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 7201) {
            val uris = mutableListOf<String>()
            if (resultCode == RESULT_OK) {
                data?.clipData?.let { clip -> for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri.toString()) }
                if (uris.isEmpty()) data?.data?.let { uris.add(it.toString()) }
            }
            fileResult?.success(uris.filter { Uri.parse(it).scheme == "content" }); fileResult = null
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7202) {
            permissionResult?.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
            permissionResult = null
        }
    }
}
