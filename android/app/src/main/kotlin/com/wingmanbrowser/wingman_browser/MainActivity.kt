package com.wingmanbrowser.wingman_browser

import android.app.DownloadManager
import android.app.KeyguardManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.GeolocationPermissions
import android.webkit.WebStorage
import androidx.webkit.ProfileStore
import androidx.webkit.WebStorageCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Bundled-content boundary. No WebView plugin, renderer, download or external opener. */
class MainActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private var pendingLink: String? = null
    private var initialized = false
    private var discardingHandoffLinks = false
    private var clearing = false

    override fun onCreate(savedInstanceState: Bundle?) {
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        if (Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wingman/browser")
        channel.setMethodCallHandler(::handle)
        // Flutter's embedding otherwise exposes third-party PROCESS_TEXT
        // activities independently of url_launcher. No external text processor
        // is part of the reviewed local renderer, including in debug builds.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flutter/processtext")
            .setMethodCallHandler { call, result ->
                if (call.method == "ProcessText.queryTextActions") result.success(emptyMap<String, String>())
                else result.error("bundled_content_only", "External text actions are unavailable.", null)
            }
        pendingLink = validWebUrl(intent?.dataString)
        // Do not initialize a content engine, restore a profile or allocate a
        // WebView. Explicit legacy cleanup uses only website-store APIs.
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (discardingHandoffLinks) return
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

    private fun contentViewCount(view: View): Int =
        (if (view is android.webkit.WebView) 1 else 0) +
        (if (view is ViewGroup) (0 until view.childCount).sumOf { contentViewCount(view.getChildAt(it)) } else 0)

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "discardHandoffIncoming" -> {
                    // Deny-only: guest addresses must never be replayed into the
                    // owner shell after authentication or process replacement.
                    pendingLink = null
                    initialized = false
                    discardingHandoffLinks = true
                    result.success(null)
                }
                "initialize" -> {
                    if (discardingHandoffLinks) pendingLink = null
                    discardingHandoffLinks = false
                    initialized = true
                    result.success(pendingLink)
                    pendingLink = null
                }
                "setSensitiveContent" -> result.success(null) // Cannot weaken the native baseline.
                "capabilityState" -> result.success(mapOf(
                    "capability" to "bundledPlainTextOnly", "liveBrowsing" to false,
                    "contentViews" to contentViewCount(window.decorView),
                    "handoffIncomingDiscarded" to discardingHandoffLinks, "incomingReady" to initialized,
                    "keyboardVisible" to (if (Build.VERSION.SDK_INT >= 30)
                        window.decorView.rootWindowInsets?.isVisible(android.view.WindowInsets.Type.ime()) else null),
                    "secureWindow" to ((window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0)))
                "handoffCapabilities" -> result.success(mapOf(
                    "staticOnly" to true, "liveBrowsing" to false,
                    "contentViews" to contentViewCount(window.decorView),
                    "deviceAuthenticationAvailable" to
                        (getSystemService(KEYGUARD_SERVICE) as KeyguardManager).isDeviceSecure))
                "privateAvailable", "defaultBrowser" -> result.success(false)
                "normalizeHost" -> result.success(NativeGuardPolicy.normalizeHost(call.argument<String>("host") ?: ""))
                "quarantineLegacyContent" -> {
                    cancelUnfinishedDownloads()
                    clearLegacyData(storage = true, cookies = true, cache = true, result = result)
                }
                "clearData" -> clearLegacyData(
                    storage = call.argument<Boolean>("storage") == true,
                    cookies = call.argument<Boolean>("cookies") == true,
                    cache = call.argument<Boolean>("cache") == true, result = result)
                "stop", "pause", "hideForGuard", "close" -> result.success(null) // No retained views.
                "closedViewReleased" -> result.success(true)
                // There is deliberately no setter, config flag, debug escape,
                // role exception or ID lookup that can create/bind a view.
                else -> result.error("bundled_content_only", "This capability is unavailable in the bundled library.", null)
            }
        } catch (_: Exception) {
            clearing = false
            result.error("local_cleanup_unavailable", "Local browser cleanup could not be completed.", null)
        }
    }

    /** DownloadManager scopes queries to the calling app. Preserve completed files. */
    private fun cancelUnfinishedDownloads() {
        val manager = getSystemService(DOWNLOAD_SERVICE) as DownloadManager
        val query = DownloadManager.Query().setFilterByStatus(
            DownloadManager.STATUS_PENDING or DownloadManager.STATUS_RUNNING or DownloadManager.STATUS_PAUSED)
        checkNotNull(manager.query(query)).use { cursor ->
            val column = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_ID)
            val ids = mutableListOf<Long>()
            while (cursor.moveToNext()) ids.add(cursor.getLong(column))
            if (ids.isNotEmpty()) manager.remove(*ids.toLongArray())
        }
    }

    private fun clearLegacyData(storage: Boolean, cookies: Boolean, cache: Boolean, result: MethodChannel.Result) {
        if (clearing) { result.error("cleanup_pending", "Legacy site-data cleanup is still pending.", null); return }
        if (!storage && !cookies && !cache) { result.success(null); return }
        clearing = true
        fun finish() { clearing = false; result.success(null) }
        fun fail() {
            clearing = false
            result.error("cleanup_unavailable", "Legacy site data could not be removed.", null)
        }
        if (!storage && !cache) {
            CookieManager.getInstance().removeAllCookies {
                try { CookieManager.getInstance().flush(); finish() }
                catch (_: Exception) { fail() }
            }
            return
        }
        // No temporary WebView is created, including on an older provider. An
        // unsupported complete deletion reports failure instead of partial success.
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA)) {
            clearing = false
            result.error("cleanup_unsupported", "Update Android System WebView to finish removing legacy site data.", null)
            return
        }
        GeolocationPermissions.getInstance().clearAll()
        WebStorageCompat.deleteBrowsingData(WebStorage.getInstance()) {
            try {
                // This API clears the default store, including cookies and cache.
                if (!WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) { finish(); return@deleteBrowsingData }
                val store = ProfileStore.getInstance()
                val names = store.allProfileNames.filter { it.startsWith("wingman_private_") }
                // Loading a profile with getProfile would prevent its deletion
                // in this process. These abandoned profiles have no live views:
                // unregister them by name without restoring any site context.
                names.forEach { store.deleteProfile(it) }
                check(store.allProfileNames.none { it.startsWith("wingman_private_") })
                // Android may finish physical profile-file removal async; the
                // profiles are already unusable and no renderer can restore them.
                finish()
            } catch (_: Exception) { fail() }
        }
    }
}
