package com.wingmanbrowser.wingman_browser

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.net.http.SslError
import android.os.Build
import android.os.Message
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.text.InputType
import android.text.InputFilter
import android.webkit.*
import android.widget.FrameLayout
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Toast
import androidx.webkit.*
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayInputStream
import java.net.HttpURLConnection
import java.net.URI
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Native networking and origin sandbox, with local mandatory policy before navigation. No page JS bridge. */
class ProtectedWebBridge(private val context: Context, private val channel: MethodChannel) {
    companion object {
        const val VIEW_TYPE = "wingman/protected-web"
        const val UPLOAD_REQUEST = 7110
        const val DOWNLOAD_REQUEST = 7111
        const val PERMISSION_REQUEST = 7112
    }
    private val activity get() = context as Activity
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val policy by lazy { ConsumerProtectionPolicy(context) }
    private val views = mutableMapOf<Int, ProtectedView>()
    private val pendingWindows = mutableMapOf<String, ProtectedView>()
    private var nextPendingId = -1
    private val profileReferences = BrowserProfileReferences()
    @Volatile private var restrictionRevision = 0L
    private var restrictionSignature = ""

    private val policyUpdates by lazy { ConsumerPolicyUpdates(context, policy) { action ->
        val prior = ready
        ready = false
        try { closeAll(); action() } finally { ready = prior }
    } }
    @Volatile private var ready = true
    @Volatile private var foreground = true
    @Volatile private var denied = false
    @Volatile private var cleanupPending = false
    private val loadedProfiles = mutableMapOf<String, Profile>()
    private val purgedProfiles = mutableSetOf<String>()
    private val retiringProfiles = java.util.Collections.synchronizedSet(mutableSetOf<String>())
    private val profilePurgeWaiters = mutableMapOf<String, MutableList<(Boolean) -> Unit>>()
    private var profilePurgeFailed = false
    private var uploadCallback: ValueCallback<Array<Uri>>? = null
    private var uploadOwner: ProtectedView? = null
    private var uploadOrigin: String? = null
    private var uploadTicket: BrowserDocumentTicket? = null
    private data class Download(val owner: ProtectedView, val url: String, val mime: String, val filename: String,
                                val cookies: CookieManager?, val userAgent: String, val epoch: Long)
    private var download: Download? = null
    private var permissionCompletion: (() -> Unit)? = null
    private val siteRequests = mutableSetOf<SiteRequest>()
    private var fullscreen: View? = null
    private var fullscreenBack: android.window.OnBackInvokedCallback? = null
    private var fullscreenCallback: WebChromeClient.CustomViewCallback? = null
    private val downloads = Executors.newSingleThreadExecutor()
    val factory = object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
            val values = args as? Map<*, *> ?: emptyMap<Any, Any>()
            check(views.size < 12)
            applyRestrictions(values)
            val token = values["windowToken"] as? String
            if (token != null) {
                val child = pendingWindows.remove(token)
                if (child != null && values["edition"] == "consumer" && child.privateMode == (values["private"] == true) &&
                    child.claimWindow() && (values["tabId"] as? String)?.let { it.isNotBlank() && it.length <= 100 } == true) {
                    child.id = viewId; child.tabId = values["tabId"] as String
                    views[viewId] = child; return child
                }
                child?.release()
            }
            return ProtectedView(context, viewId, values["tabId"] as? String ?: "", values["private"] == true).also { views[viewId] = it }
        }
    }
    init {
        channel.setMethodCallHandler(::handle)
        // Remove only incomplete app-owned download staging files after a process crash.
        context.cacheDir.listFiles()?.filter { it.name.startsWith("wingman-download-") && it.name.endsWith(".part") }?.forEach { it.delete() }
        if (privateAvailable()) {
            // Abandoned private profiles from a terminated process are never reused.
            try { ProfileStore.getInstance().allProfileNames.filter { it.startsWith("wingman_private_") }.forEach { ProfileStore.getInstance().deleteProfile(it) } }
            catch (_: Exception) { profilePurgeFailed = true }
        }
        installServiceWorkerPolicy(null)
    }
    fun quarantineCompleted() { ready = true }
    fun cleanupStarted() { cleanupPending = true; closeAll() }
    fun cleanupFinished() { cleanupPending = false }
    fun hideAll() { denied = true; hideFullscreen(); closeAll() }
    fun restoreOwner() { denied = false }
    fun pauseAll() { foreground = false; cancelPendingWindows(); hideFullscreen(); views.values.forEach { it.web?.onPause() }; CookieManager.getInstance().flush() }
    fun resume() { foreground = true; views.values.filter { it.active }.forEach { it.web?.onResume() } }
    fun closeAll() { hideFullscreen(); cancelPendingWindows(); views.values.toList().forEach { it.release() }; cancelUpload(); download = null }
    private fun applyRestrictions(values: Map<*, *>) {
        fun strings(key: String) = (values[key] as? List<*>)?.filterIsInstance<String>() ?: emptyList()
        val keys = listOf("blockedResourceIds", "blockedCollections", "blockedDomains", "blockedUrls")
        val signature = keys.map { strings(it).distinct().sorted() }.toString() + (values["searchBlocked"] == true)
        if (signature != restrictionSignature) {
            restrictionSignature = signature; restrictionRevision++; cancelPendingWindows()
        }
        policy.setAdditionalRestrictions(strings(keys[0]), strings(keys[1]), strings(keys[2]), strings(keys[3]), values["searchBlocked"] == true)
    }
    private fun cancelPendingWindows(opener: ProtectedView? = null) {
        val candidates = (pendingWindows.values + views.values).distinct().filter { it.windowPending && (opener == null || it.windowOpener === opener) }
        candidates.forEach { it.release() }
    }
    private fun stageWindow(opener: ProtectedView, transport: WebView.WebViewTransport, message: Message): Boolean {
        val renderer = opener.web ?: return false
        val ticket = opener.documentScope.issue(opener.currentUrl) ?: return false
        if (!mayOpen() || pendingWindows.size >= 4) return false
        val child = ProtectedView(context, nextPendingId--, UUID.randomUUID().toString(), opener.privateMode)
        val token = UUID.randomUUID().toString()
        child.windowOpener = opener; child.windowToken = token; child.scriptWindow = true; child.active = false
        child.windowLease = BrowserWindowLease(renderer, opener.documentScope, ticket, restrictionRevision, SystemClock.uptimeMillis() + 10000)
        try {
            val popup = child.createWeb(opener.profileName)
            pendingWindows[token] = child
            transport.webView = popup; message.sendToTarget()
            activity.window.decorView.postDelayed({ if (child.windowPending) child.release() }, 10000)
            return true
        } catch (_: Exception) { child.release(); return false }
    }
    fun privateAvailable() = WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE) && WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA) && !profilePurgeFailed
    fun liveAvailable() = ready && policy.valid() && policyUpdates.generationReady() && !cleanupPending
    private fun mayOpen() = liveAvailable() && foreground && !denied
    private fun purgeProfile(name: String, completion: (Boolean) -> Unit = {}) {
        if (name in purgedProfiles) { completion(true); return }
        profilePurgeWaiters[name]?.let { it.add(completion); return }
        if (profileReferences.contains(name)) { completion(false); return }
        val profile = loadedProfiles[name] ?: run { completion(false); return }
        profilePurgeWaiters[name] = mutableListOf(completion)
        fun done(success: Boolean) {
            if (success) purgedProfiles.add(name) else profilePurgeFailed = true
            profilePurgeWaiters.remove(name)?.forEach { it(success) }
        }
        try {
            WebStorageCompat.deleteBrowsingData(profile.webStorage) {
                profile.cookieManager.removeAllCookies { profile.cookieManager.flush(); done(true) }
            }
        } catch (_: Exception) { done(false) }
    }
    fun purgeRetiredProfiles(completion: (Boolean) -> Unit) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) { completion(true); return }
        val names = ProfileStore.getInstance().allProfileNames.filter { it.startsWith("wingman_private_") }
        if (names.isEmpty()) { completion(true); return }
        var count = names.size; var okay = true
        fun done(success: Boolean) { okay = okay && success; if (--count == 0) completion(okay) }
        names.forEach { name ->
            if (loadedProfiles.containsKey(name)) purgeProfile(name, ::done)
            else try { ProfileStore.getInstance().deleteProfile(name); done(true) } catch (_: Exception) { done(false) }
        }
    }
    private fun deniedResponse() = WebResourceResponse("text/plain", "UTF-8", 403, "Blocked", mapOf("Cache-Control" to "no-store"), ByteArrayInputStream(ByteArray(0)))
    private fun installServiceWorkerPolicy(profile: Profile?, profileName: String? = null) {
        if (Build.VERSION.SDK_INT < 24) return
        val controller = profile?.serviceWorkerController ?: ServiceWorkerController.getInstance()
        controller.serviceWorkerWebSettings.apply { allowFileAccess = false; allowContentAccess = false }
        controller.setServiceWorkerClient(object : ServiceWorkerClient() {
            override fun shouldInterceptRequest(request: WebResourceRequest): WebResourceResponse? =
                if (liveAvailable() && !denied && !cleanupPending && (profileName == null || profileName !in retiringProfiles) && policy.decide(request.url.toString(), false).allowed) null else deniedResponse()
        })
    }
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (call.method == "capabilities") {
                if (BuildConfig.DEBUG) android.util.Log.i("WingmanProtection", "baseline=${policy.diagnostic}; ready=$ready; cleanup=$cleanupPending; edition=${BuildConfig.WINGMAN_EDITION}")
                result.success(mapOf("supported" to liveAvailable(), "privateAvailable" to (liveAvailable() && privateAvailable()), "strictSearchAvailable" to liveAvailable(), "mode" to "consumerWeb", "javascript" to true, "cookies" to true, "storage" to true, "history" to true, "findInPage" to true, "uploads" to true, "downloads" to true, "media" to true, "permissions" to true, "newWindows" to true, "defaultBrowserAvailable" to true, "engine" to "Android System WebView", "engineVersion" to WebViewCompat.getCurrentWebViewPackage(context)?.versionName, "reason" to if (liveAvailable()) null else "Mandatory protection needs recovery.")); return
            }
            when (call.method) {
                "prepareConsumerPolicy" -> { result.success(policyUpdates.prepare(call.argument<ByteArray>("envelope") ?: throw IllegalArgumentException(), call.argument<ByteArray>("data") ?: throw IllegalArgumentException(), call.argument<Boolean>("restore") == true)); return }
                "activateConsumerPolicy" -> { result.success(policyUpdates.activate(call.argument<String>("token") ?: "")); return }
                "discardConsumerPolicy" -> { policyUpdates.discard(call.argument<String>("token") ?: ""); result.success(null); return }
                "revertConsumerPolicy" -> { result.success(policyUpdates.revert(call.argument<String>("token") ?: "")); return }
            }
            if (call.method == "configurePolicy") {
                restrictionRevision++; cancelPendingWindows()
                policy.setAdditional(call.argument<List<String>>("blockedDomains") ?: emptyList())
                views.values.forEach { view -> if (view.currentUrl.isNotEmpty() && !policy.decide(view.currentUrl).allowed) view.block(view.currentUrl, "Blocked by an additional restriction.") }
                result.success(null); return
            }
            if (call.method == "state" && call.argument<Number>("viewId") == null) {
                result.success(mapOf("views" to views.values.count { it.web != null }, "ready" to ready, "foreground" to foreground, "handoffBlocked" to denied, "cleanupPending" to cleanupPending, "baselineValid" to policy.valid(), "profilePurgesPending" to profilePurgeWaiters.size, "profilePurgeFailed" to profilePurgeFailed)); return
            }
            val view = views[call.argument<Number>("viewId")?.toInt()] ?: throw IllegalStateException()
            call.argument<Number>("requestId")?.toLong()?.let { view.acceptRequest(it) }
            when (call.method) {
                "adoptWindow" -> { check(view.activateWindow(call.argument<String>("windowToken") ?: "")); result.success(null) }
                "updateRestrictions" -> { applyRestrictions(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()); if (view.currentUrl.isNotEmpty() && !policy.decide(view.currentUrl).allowed) view.block(view.currentUrl, "Blocked by an additional restriction."); result.success(null) }
                "open" -> { view.open(call.argument<String>("url") ?: ""); result.success(null) }
                "openSearch" -> { view.open(strictSearchURL(call.argument<String>("query") ?: "") ?: throw IllegalArgumentException()); result.success(null) }
                "reload" -> {
                    check(mayOpen())
                    if (policy.decide(view.currentUrl).allowed) {
                        if (view.web == null) view.open(view.currentUrl) else view.web?.reload()
                    }
                    result.success(null)
                }
                "back" -> { check(mayOpen()); view.history(-1); result.success(null) }
                "forward" -> { check(mayOpen()); view.history(1); result.success(null) }
                "stop" -> { view.web?.stopLoading(); view.loading = false; view.emit(); result.success(null) }
                "close" -> { view.release(); views.remove(view.id); result.success(null) }
                "setActive" -> { view.setVisibilityActive(call.argument<Boolean>("active") == true); result.success(null) }
                "find" -> { view.web?.findAllAsync(call.argument<String>("query")?.take(1024) ?: ""); result.success(null) }
                "findNext" -> { view.web?.findNext(call.argument<Boolean>("forward") != false); result.success(null) }
                "clearFind" -> { view.web?.clearMatches(); result.success(null) }
                "share" -> { check(policy.decide(view.currentUrl).allowed); activity.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, view.currentUrl) }, "Share page")); result.success(null) }
                "state" -> result.success(view.state())
                else -> result.error("browser_method_unavailable", "This browser operation is unavailable.", null)
            }
        } catch (failure: Exception) {
            if (BuildConfig.DEBUG) android.util.Log.w("WingmanProtection", "method=${call.method}; failure=${failure.javaClass.simpleName}; location=${failure.stackTrace.firstOrNull()}")
            result.error("protected_navigation_denied", "The operation could not complete with the required protections.", null) }
    }
    private inner class ProtectedView(context: Context, var id: Int, var tabId: String, val privateMode: Boolean) : PlatformView {
        private val container = FrameLayout(context)
        @Volatile var web: WebView? = null
        @Volatile var currentUrl = ""
        var requestId = 0L
        @Volatile var downloadEpoch = 0L
        var active = true
        var loading = false
        private var disposed = false
        var profileName: String? = null
        private var progress = 0
        private var title = ""
        private var error: String? = null
        private var blocked = 0
        private var attempted = 0
        private var lastBlocked: String? = null
        val documentScope = BrowserDocumentScope()
        @Volatile var windowOpener: ProtectedView? = null
        var windowToken: String? = null
        @Volatile var windowLease: BrowserWindowLease? = null
        var scriptWindow = false
        private val windowDelivered = AtomicBoolean(false)
        val windowPending get() = windowLease?.activated == false
        private fun windowCurrent(): Boolean {
            val opener = windowOpener ?: return false
            return mayOpen() && windowLease?.current(opener.web, opener.currentUrl, restrictionRevision, SystemClock.uptimeMillis()) == true
        }
        fun claimWindow(): Boolean {
            val opener = windowOpener ?: return false
            return windowCurrent() && windowLease?.claim(opener.web, opener.currentUrl, restrictionRevision, SystemClock.uptimeMillis()) == true
        }
        fun activateWindow(token: String): Boolean {
            val opener = windowOpener ?: return false
            if (windowToken != token || !windowCurrent() || !policy.decide(currentUrl).allowed ||
                windowLease?.activate(opener.web, opener.currentUrl, restrictionRevision, SystemClock.uptimeMillis()) != true) return false
            windowToken = null; windowOpener = null; setVisibilityActive(true); emit(); return true
        }
        private fun deliverWindow(raw: String): Boolean {
            if (!windowPending) return true
            if (!windowCurrent()) { mainHandler.post { release() }; return false }
            val decision = policy.decide(raw)
            if (!decision.allowed || decision.url != raw) {
                mainHandler.post { windowOpener?.block(raw, decision.reason); release() }; return false
            }
            if (windowDelivered.compareAndSet(false, true)) {
                currentUrl = raw
                mainHandler.post {
                    val opener = windowOpener
                    if (opener != null && windowCurrent()) channel.invokeMethod("newWindowRequested", mapOf("viewId" to opener.id, "requestId" to opener.requestId, "url" to raw, "windowToken" to windowToken))
                    else release()
                }
            }
            return true
        }

        override fun getView(): View = container
        override fun dispose() { release(); disposed = true; views.remove(id) }
        fun acceptRequest(value: Long) { check(value >= requestId); requestId = value }
        fun state(): Map<String, Any?> = mapOf("viewId" to id, "requestId" to requestId, "url" to currentUrl, "title" to title, "progress" to progress, "isLoading" to loading, "error" to error, "blockedResources" to blocked, "requestAttempts" to attempted, "hasRenderer" to (web != null), "private" to privateMode, "javascript" to (web?.settings?.javaScriptEnabled ?: false), "engineNetworkBlocked" to false, "strictSearch" to currentUrl.startsWith("https://safe.duckduckgo.com/"), "canGoBack" to (web?.canGoBack() ?: false), "canGoForward" to (web?.canGoForward() ?: false))
        fun emit() { container.post { if (!disposed && !windowPending) channel.invokeMethod("pageState", state()) } }
        fun block(url: String, reason: String?) {
            web?.stopLoading(); loading = false
            // Retain the previous permitted committed page; the shell shows the denied destination separately.
            if (lastBlocked != url) channel.invokeMethod("navigationBlocked", mapOf("viewId" to id, "requestId" to requestId, "url" to url, "reason" to (reason ?: "Blocked by protection.")))
            lastBlocked = url
            emit()
        }
        fun setVisibilityActive(value: Boolean) {
            active = value
            web?.visibility = if (value && !denied) View.VISIBLE else View.INVISIBLE
            if (value && foreground && !denied) web?.onResume() else web?.onPause()
        }
        fun history(offset: Int) {
            val w = web ?: return
            val list = w.copyBackForwardList(); val position = list.currentIndex + offset
            if (position !in 0 until list.size) return
            val destination = list.getItemAtIndex(position).url
            val decision = policy.decide(destination)
            if (decision.allowed) w.goBackOrForward(offset) else block(destination, decision.reason)
        }
        fun open(raw: String) {
            check(!disposed && mayOpen() && tabId.isNotBlank() && tabId.length <= 100)
            val decision = policy.decide(raw)
            if (!decision.allowed) { block(raw, decision.reason); throw IllegalArgumentException() }
            if (web != null && currentUrl == decision.url && error == null) { setVisibilityActive(true); emit(); return }
            val w = web ?: createWeb()
            error = null; lastBlocked = null; currentUrl = decision.url; loading = true; progress = 0
            setVisibilityActive(true); emit(); w.loadUrl(decision.url)
        }
        fun createWeb(inheritedProfile: String? = null): WebView {
            check(!privateMode || privateAvailable())
            val w = object : WebView(container.context) {
                override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection? =
                    super.onCreateInputConnection(outAttrs).also {
                        if (privateMode && Build.VERSION.SDK_INT >= 26) outAttrs.imeOptions = outAttrs.imeOptions or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
                    }
            }
            web = w
            WebView.setWebContentsDebuggingEnabled(false)
            if (privateMode) {
                if (Build.VERSION.SDK_INT >= 26) w.importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
                val name = if (windowPending) {
                    checkNotNull(inheritedProfile).also { check(profileReferences.contains(it) && it !in retiringProfiles && loadedProfiles.containsKey(it)) }
                } else "wingman_private_${UUID.randomUUID()}"
                WebViewCompat.setProfile(w, name); profileName = name
                profileReferences.retain(name)
                loadedProfiles[name] = WebViewCompat.getProfile(w)
                installServiceWorkerPolicy(loadedProfiles[name], name)
            }
            with(w.settings) {
                blockNetworkLoads = false; javaScriptEnabled = true; javaScriptCanOpenWindowsAutomatically = false
                allowFileAccess = false; allowContentAccess = false
                @Suppress("DEPRECATION")
                allowFileAccessFromFileURLs = false
                @Suppress("DEPRECATION")
                allowUniversalAccessFromFileURLs = false
                domStorageEnabled = true
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                cacheMode = WebSettings.LOAD_DEFAULT
                setSupportMultipleWindows(true); mediaPlaybackRequiresUserGesture = true
                setGeolocationEnabled(true); builtInZoomControls = true; displayZoomControls = false
                useWideViewPort = true; loadWithOverviewMode = true
                disabledActionModeMenuItems = WebSettings.MENU_ITEM_WEB_SEARCH or WebSettings.MENU_ITEM_PROCESS_TEXT
            }
            if (WebViewFeature.isFeatureSupported(WebViewFeature.SAFE_BROWSING_ENABLE)) WebSettingsCompat.setSafeBrowsingEnabled(w.settings, true)
            cookieManager().apply { setAcceptCookie(true); setAcceptThirdPartyCookies(w, false) }
            w.webChromeClient = object : WebChromeClient() {
                override fun onConsoleMessage(message: ConsoleMessage?) = true
                override fun onProgressChanged(view: WebView, newProgress: Int) { if (view === web) { progress = newProgress; emit() } }
                override fun onReceivedTitle(view: WebView, value: String?) { if (view === web) { title = value.orEmpty().filter { it.code >= 32 }.take(160); emit() } }
                override fun onCreateWindow(view: WebView, isDialog: Boolean, isUserGesture: Boolean, resultMsg: Message): Boolean {
                    if (!isUserGesture || view !== web || !active || !mayOpen()) return false
                    val transport = resultMsg.obj as? WebView.WebViewTransport ?: return false
                    return stageWindow(this@ProtectedView, transport, resultMsg)
                }
                override fun onCloseWindow(window: WebView) {
                    if (window !== web || !scriptWindow) return
                    val adopted = !windowPending
                    release()
                    if (adopted) channel.invokeMethod("closeRequested", mapOf("viewId" to id, "requestId" to requestId))
                }
                override fun onPermissionRequest(request: PermissionRequest) { requestMediaPermission(this@ProtectedView, request) }
                override fun onPermissionRequestCanceled(request: PermissionRequest) { siteRequests.filter { it.key === request }.toList().forEach { it.finish {} } }
                override fun onGeolocationPermissionsShowPrompt(origin: String, callback: GeolocationPermissions.Callback) { requestLocation(this@ProtectedView, origin, callback) }
                override fun onShowFileChooser(view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean { chooseFiles(this@ProtectedView, callback, params); return true }
                override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                    if (!active || !mayOpen()) { callback.onCustomViewHidden(); return }
                    hideFullscreen(); fullscreen = view; fullscreenCallback = callback
                    if (Build.VERSION.SDK_INT >= 33) {
                        val back = android.window.OnBackInvokedCallback { hideFullscreen() }
                        fullscreenBack = back
                        activity.onBackInvokedDispatcher.registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_OVERLAY, back)
                    }
                    (activity.window.decorView as ViewGroup).addView(view, ViewGroup.LayoutParams(-1, -1))
                }
                override fun onHideCustomView() { hideFullscreen() }
            }
            w.webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                    if (view !== web) return deniedResponse()
                    val lease = windowLease
                    if (lease != null && !lease.activated) {
                        if (!request.isForMainFrame || request.method !in setOf("GET", "POST") || !deliverWindow(request.url.toString())) return deniedResponse()
                        // WebView invokes this on its request worker. Keeping the
                        // original request pending preserves Chromium's POST body.
                        val adopted = try { lease.awaitActivation(SystemClock.uptimeMillis()) } catch (_: InterruptedException) { false }
                        if (!adopted) { mainHandler.post { release() }; return deniedResponse() }
                    }
                    val decision = policy.decide(request.url.toString(), request.isForMainFrame, currentUrl)
                    synchronized(this@ProtectedView) { attempted++; if (!decision.allowed) blocked++ }
                    // A WebView POST can skip shouldOverrideUrlLoading. Never let a
                    // provider rewrite decision authorize the original non-strict endpoint.
                    val needsRewrite = request.isForMainFrame && decision.allowed && decision.url != request.url.toString()
                    val strictPost = request.method == "POST" && request.url.scheme == "https" && request.url.host == "safe.duckduckgo.com"
                    if (view !== web || !liveAvailable() || !decision.allowed || denied || cleanupPending || (needsRewrite && !strictPost)) {
                        if (request.isForMainFrame) container.post {
                            if (view === web && ready && needsRewrite && request.method == "GET" && !denied && !cleanupPending) view.loadUrl(decision.url)
                            else block(request.url.toString(), decision.reason ?: "This form cannot change the strict search endpoint.")
                        }
                        return deniedResponse()
                    }
                    // Chromium handles methods, request bodies, cookies, redirects, cache and TLS.
                    return null
                }
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    if (view !== web) return true
                    if (windowPending && (!request.isForMainFrame || request.method !in setOf("GET", "POST") || !deliverWindow(request.url.toString()))) return true
                    val decision = policy.decide(request.url.toString(), request.isForMainFrame, currentUrl)
                    if (!decision.allowed || !mayOpen()) { if (request.isForMainFrame) block(request.url.toString(), decision.reason); return true }
                    if (request.isForMainFrame && decision.url != request.url.toString()) {
                        if (request.method != "GET") { block(request.url.toString(), "This form cannot change the strict search endpoint."); return true }
                        view.loadUrl(decision.url); return true
                    }
                    return false
                }
                override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                    if (view !== web || !ready) return
                    if (windowPending && !deliverWindow(url)) return
                    invalidateDocument()
                    val decision = policy.decide(url)
                    if (!decision.allowed) { block(url, decision.reason); return }
                    if (decision.url != url) { view.stopLoading(); view.loadUrl(decision.url); return }
                    currentUrl = url; error = null; loading = true; progress = 0; lastBlocked = null; emit()
                }
                override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) {
                    if (view !== web || !ready) return
                    val decision = policy.decide(url)
                    if (decision.allowed) { currentUrl = url; emit() } else block(url, decision.reason)
                }
                override fun onPageFinished(view: WebView, url: String) {
                    if (view !== web || !policy.decide(url).allowed) return
                    currentUrl = url; loading = false; progress = 100; cookieManager().flush(); emit()
                }
                override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, sslError: SslError) { handler.cancel(); fail("The site's TLS certificate is invalid. The connection was blocked.") }
                override fun onReceivedError(view: WebView, request: WebResourceRequest, failure: WebResourceError) { if (request.isForMainFrame) fail("The page could not connect (${failure.errorCode}).") }
                override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) { if (request.isForMainFrame && response.statusCode >= 500) { error = "The website returned HTTP ${response.statusCode}."; emit() } }
                override fun onReceivedHttpAuthRequest(view: WebView, handler: HttpAuthHandler, host: String, realm: String) {
                    if (view !== web) handler.cancel() else requestHttpAuthentication(this@ProtectedView, handler, host, realm)
                }
                override fun onReceivedClientCertRequest(view: WebView, request: ClientCertRequest) { request.cancel() }
                override fun onSafeBrowsingHit(view: WebView, request: WebResourceRequest, threatType: Int, callback: SafeBrowsingResponse) { callback.backToSafety(false); if (request.isForMainFrame) fail("The platform blocked a known security threat.") }
                override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean { if (view === web) { release(); channel.invokeMethod("rendererGone", mapOf("viewId" to id, "requestId" to requestId)) }; return true }
            }
            w.setFindListener { position, count, done -> channel.invokeMethod("findResult", mapOf("viewId" to id, "requestId" to requestId, "activeMatch" to position, "matches" to count, "done" to done)) }
            w.setDownloadListener { url, userAgent, disposition, mime, _ -> requestDownload(this, url, disposition, mime, userAgent) }
            container.addView(w, FrameLayout.LayoutParams(-1, -1))
            return w
        }
        fun cookieManager(): CookieManager = if (privateMode) checkNotNull(profileName?.let { loadedProfiles[it]?.cookieManager }) else CookieManager.getInstance()
        private fun fail(message: String) { web?.stopLoading(); loading = false; error = message; emit() }
        private fun invalidateDocument() {
            cancelPendingWindows(this)
            documentScope.advance()
            cancelSiteRequests(this)
            if (uploadOwner === this) cancelUpload()
        }
        fun release() {
            windowLease?.cancel(); windowLease = null
            windowToken?.let { pendingWindows.remove(it) }; windowToken = null
            windowOpener = null
            invalidateDocument()
            downloadEpoch++
            if (download?.owner === this) download = null
            if (uploadOwner === this) cancelUpload()
            val retired = web
            web = null; loading = false
            retired?.let { it.stopLoading(); it.visibility = View.INVISIBLE; container.removeView(it); it.destroy() }
            profileName?.let { name ->
                if (profileReferences.release(name)) { retiringProfiles.add(name); purgeProfile(name) }
            }; profileName = null
        }
    }
    private fun origin(raw: String) = browserOrigin(raw)
    private inner class SiteRequest(val owner: ProtectedView, val key: Any, val ticket: BrowserDocumentTicket,
                                    private val decline: () -> Unit) {
        var dialog: AlertDialog? = null
        private var resolved = false
        fun stillBound() = !resolved && owner.web != null && liveAvailable() && !denied &&
            owner.documentScope.owns(ticket, owner.currentUrl) && policy.decide(owner.currentUrl).allowed
        fun finish(action: () -> Unit) {
            if (resolved) return
            resolved = true; siteRequests.remove(this); dialog?.dismiss(); dialog = null
            runCatching(action)
        }
        fun cancel() = finish(decline)
        fun show(builder: AlertDialog.Builder) {
            dialog = builder.create().also {
                it.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                it.show()
            }
        }
    }
    private fun cancelSiteRequests(owner: ProtectedView) { siteRequests.filter { it.owner === owner }.toList().forEach { it.cancel() } }
    private fun siteRequest(owner: ProtectedView, key: Any, cancel: () -> Unit): SiteRequest? {
        val ticket = owner.documentScope.issue(owner.currentUrl)
        if (ticket == null || siteRequests.isNotEmpty()) { cancel(); return null }
        return SiteRequest(owner, key, ticket, cancel).also { siteRequests.add(it) }
    }
    private fun permissionEligible(owner: ProtectedView, requestedOrigin: String) = owner.web != null && owner.active && mayOpen() && origin(owner.currentUrl) == origin(requestedOrigin) && requestedOrigin.startsWith("https://") && policy.decide(owner.currentUrl).allowed
    // Android returns OS permission results before Activity.onResume. Validate
    // retained ownership here; temporary OS-dialog inactivity is not a tab change.
    private fun permissionStillBound(owner: ProtectedView, requestedOrigin: String, epoch: Long) =
        owner.web != null && owner.downloadEpoch == epoch && liveAvailable() && !denied &&
            origin(owner.currentUrl) == origin(requestedOrigin) && requestedOrigin.startsWith("https://") && policy.decide(owner.currentUrl).allowed
    private fun requestMediaPermission(owner: ProtectedView, request: PermissionRequest) {
        val requestedOrigin = request.origin.toString()
        val epoch = owner.downloadEpoch
        val resources = request.resources.filter { it == PermissionRequest.RESOURCE_AUDIO_CAPTURE || it == PermissionRequest.RESOURCE_VIDEO_CAPTURE }
        if (!permissionEligible(owner, requestedOrigin) || resources.isEmpty() || resources.size != request.resources.size) { request.deny(); return }
        val pending = siteRequest(owner, request) { request.deny() } ?: return
        pending.show(AlertDialog.Builder(activity).setTitle("Website permission").setMessage("$requestedOrigin wants ${resources.joinToString { if (it == PermissionRequest.RESOURCE_VIDEO_CAPTURE) "camera" else "microphone" }} access for this page.")
            .setNegativeButton("Deny") { _, _ -> pending.cancel() }.setOnCancelListener { pending.cancel() }
            .setPositiveButton("Allow") { _, _ ->
                if (!pending.stillBound()) { pending.cancel(); return@setPositiveButton }
                val permissions = resources.map { if (it == PermissionRequest.RESOURCE_VIDEO_CAPTURE) Manifest.permission.CAMERA else Manifest.permission.RECORD_AUDIO }
                withPermissions(permissions) {
                    if (pending.stillBound() && permissionStillBound(owner, requestedOrigin, epoch) && permissions.all { activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) pending.finish { request.grant(resources.toTypedArray()) } else pending.cancel()
                }
            })
    }
    private fun requestLocation(owner: ProtectedView, requestedOrigin: String, callback: GeolocationPermissions.Callback) {
        val epoch = owner.downloadEpoch
        if (!permissionEligible(owner, requestedOrigin)) { callback.invoke(requestedOrigin, false, false); return }
        val pending = siteRequest(owner, callback) { callback.invoke(requestedOrigin, false, false) } ?: return
        pending.show(AlertDialog.Builder(activity).setTitle("Website location").setMessage("Allow $requestedOrigin to access location for this page?")
            .setNegativeButton("Deny") { _, _ -> pending.cancel() }.setOnCancelListener { pending.cancel() }
            .setPositiveButton("Allow") { _, _ ->
                if (!pending.stillBound()) { pending.cancel(); return@setPositiveButton }
                withPermissions(listOf(Manifest.permission.ACCESS_COARSE_LOCATION)) {
                    if (pending.stillBound() && permissionStillBound(owner, requestedOrigin, epoch) && activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED)
                        pending.finish { callback.invoke(requestedOrigin, true, false) } else pending.cancel()
                }
            })
    }
    private fun requestHttpAuthentication(owner: ProtectedView, handler: HttpAuthHandler, host: String, realm: String) {
        if (!owner.active || !mayOpen() || !policy.decide(owner.currentUrl).allowed || !permitsHttpAuthentication(owner.currentUrl, host)) { handler.cancel(); return }
        val pending = siteRequest(owner, handler) { handler.cancel() } ?: return
        val layout = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            val padding = (24 * resources.displayMetrics.density).toInt(); setPadding(padding, 0, padding, 0)
            if (Build.VERSION.SDK_INT >= 26) importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        }
        fun field(label: String, secret: Boolean) = EditText(activity).apply {
            hint = label; contentDescription = label; isSingleLine = true
            inputType = InputType.TYPE_CLASS_TEXT or if (secret) InputType.TYPE_TEXT_VARIATION_PASSWORD else InputType.TYPE_TEXT_VARIATION_NORMAL
            filters = arrayOf(InputFilter.LengthFilter(1024))
            if (Build.VERSION.SDK_INT >= 26) { importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO; imeOptions = imeOptions or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING }
        }
        val username = field("Username", false); val password = field("Password", true)
        layout.addView(username); layout.addView(password)
        val safeRealm = realm.filter { it.code >= 32 && it.code != 127 }.take(160)
        pending.show(AlertDialog.Builder(activity).setTitle("Website sign-in")
            .setMessage("$host\n$safeRealm\nThis HTTPS page requested sign-in for this host. The browser does not identify the request port.")
            .setView(layout).setNegativeButton("Cancel") { _, _ -> pending.cancel() }
            .setOnCancelListener { pending.cancel() }
            .setPositiveButton("Sign in") { _, _ ->
                val user = username.text.toString(); val secret = password.text.toString()
                username.text.clear(); password.text.clear()
                if (pending.stillBound() && permitsHttpAuthentication(owner.currentUrl, host)) pending.finish { handler.proceed(user, secret) } else pending.cancel()
            })
        pending.dialog?.setOnDismissListener { username.text.clear(); password.text.clear() }
    }
    private fun withPermissions(permissions: List<String>, completion: () -> Unit) {
        if (permissions.all { activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) { completion(); return }
        if (permissionCompletion != null) { completion(); return }
        permissionCompletion = completion; activity.requestPermissions(permissions.toTypedArray(), PERMISSION_REQUEST)
    }
    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val completion = permissionCompletion; permissionCompletion = null; completion?.invoke(); return true
    }
    private fun finishUpload(chosen: Array<Uri>?) {
        val callback = uploadCallback
        uploadCallback = null; uploadOwner = null; uploadOrigin = null; uploadTicket = null
        callback?.onReceiveValue(chosen)
    }
    private fun cancelUpload() = finishUpload(null)
    private fun chooseFiles(owner: ProtectedView, callback: ValueCallback<Array<Uri>>, params: WebChromeClient.FileChooserParams) {
        cancelUpload()
        if (!owner.active || !mayOpen() || !policy.decide(owner.currentUrl).allowed) { callback.onReceiveValue(null); return }
        uploadCallback = callback; uploadOwner = owner; uploadOrigin = origin(owner.currentUrl)
        uploadTicket = owner.documentScope.issue(owner.currentUrl)
        val types = params.acceptTypes.filter { it.matches(Regex("^[a-zA-Z0-9.+*-]+/[a-zA-Z0-9.+*-]+$")) }.toTypedArray()
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE); type = if (types.size == 1) types[0] else "*/*"
                if (types.size > 1) putExtra(Intent.EXTRA_MIME_TYPES, types)
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, params.mode == WebChromeClient.FileChooserParams.MODE_OPEN_MULTIPLE)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }, UPLOAD_REQUEST)
        } catch (_: Exception) { cancelUpload() }
    }
    private fun requestDownload(owner: ProtectedView, url: String, disposition: String?, mime: String?, userAgent: String?) {
        val decision = policy.decide(url)
        if (!decision.allowed || !owner.active || !mayOpen()) { owner.block(url, decision.reason); return }
        val filename = URLUtil.guessFileName(url, disposition, mime).replace(Regex("[^A-Za-z0-9._ -]"), "_").take(160)
        if (filename.substringAfterLast('.', "").lowercase() in setOf("apk", "exe", "msi", "dmg", "pkg", "bat", "cmd", "sh", "ps1", "js", "jar")) { owner.block(url, "Executable downloads are not supported."); return }
        val pending = siteRequest(owner, Any()) {} ?: return
        pending.show(AlertDialog.Builder(activity).setTitle("Save download?").setMessage("${origin(url)}\n$filename" + if (owner.privateMode) "\nThe saved file remains after closing this private tab." else "")
            .setNegativeButton("Cancel") { _, _ -> pending.cancel() }.setOnCancelListener { pending.cancel() }
            .setPositiveButton("Save") { _, _ ->
                if (!pending.stillBound()) { pending.cancel(); return@setPositiveButton }
                pending.finish {
                    download = Download(owner, decision.url, mime ?: "application/octet-stream", filename,
                        if (origin(url) == origin(owner.currentUrl)) owner.cookieManager() else null,
                        userAgent ?: owner.web?.settings?.userAgentString.orEmpty(), owner.downloadEpoch)
                    try { activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type = mime ?: "application/octet-stream"; putExtra(Intent.EXTRA_TITLE, filename) }, DOWNLOAD_REQUEST) }
                    catch (_: Exception) { download = null }
                }
            })
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == UPLOAD_REQUEST) {
            val owner = uploadOwner
            val chosen = if (resultCode == Activity.RESULT_OK && owner?.web != null && owner.documentScope.owns(uploadTicket, owner.currentUrl) && origin(owner.currentUrl) == uploadOrigin && liveAvailable() && !denied && policy.decide(owner.currentUrl).allowed) {
                val values = mutableListOf<Uri>(); data?.data?.let { values.add(it) }
                data?.clipData?.let { clips -> for (i in 0 until minOf(clips.itemCount, 20)) values.add(clips.getItemAt(i).uri) }
                values.distinct().filter { it.scheme == "content" && it.authority != context.packageName }.toTypedArray().takeIf { it.isNotEmpty() }
            } else null
            finishUpload(chosen); return true
        }
        if (requestCode == DOWNLOAD_REQUEST) {
            val item = download; download = null
            val target = data?.data
            if (resultCode == Activity.RESULT_OK && item != null && target?.scheme == "content") saveDownload(item, target)
            return true
        }
        return false
    }
    private fun saveDownload(item: Download, target: Uri) {
        downloads.execute {
            var okay = false
            val temporary = java.io.File.createTempFile("wingman-download-", ".part", context.cacheDir)
            try {
                var url = item.url
                var redirects = 0
                while (true) {
                    check(item.owner.downloadEpoch == item.epoch && !denied && !cleanupPending && policy.decide(url).allowed)
                    val connection = URI(url).toURL().openConnection() as HttpURLConnection
                    connection.instanceFollowRedirects = false; connection.connectTimeout = 15000; connection.readTimeout = 15000
                    val cookie = if (origin(url) == origin(item.url)) item.cookies?.getCookie(url) else null
                    BrowserDownloadHeaders.request(item.url, url, item.userAgent, cookie).forEach { (name, value) -> connection.setRequestProperty(name, value) }
                    try {
                        val code = connection.responseCode
                        updateDownloadCookies(item, url, connection.headerFields)
                        if (code in listOf(301, 302, 303, 307, 308)) {
                            check(++redirects <= 8)
                            val next = URI(url).resolve(connection.getHeaderField("Location") ?: error("redirect")).toString()
                            check(!(url.startsWith("https:") && !next.startsWith("https:")))
                            check(policy.decide(next).allowed); url = next; continue
                        }
                        check(code in 200..299 && connection.contentLengthLong <= 100L * 1024 * 1024)
                        connection.inputStream.use { input -> temporary.outputStream().use { output ->
                            val buffer = ByteArray(16384); var total = 0L
                            while (true) { check(item.owner.downloadEpoch == item.epoch && !denied && !cleanupPending); val count = input.read(buffer); if (count < 0) break; total += count; check(total <= 100L * 1024 * 1024); output.write(buffer, 0, count) }
                        } }
                        check(item.owner.downloadEpoch == item.epoch && !denied && !cleanupPending)
                        context.contentResolver.openOutputStream(target, "wt")!!.use { output -> temporary.inputStream().use { it.copyTo(output) } }
                        okay = true; break
                    } finally { connection.disconnect() }
                }
            } catch (_: Exception) { /* The picker destination is never opened or executed. */ }
            finally { temporary.delete(); activity.runOnUiThread { Toast.makeText(context, if (okay) "Download saved" else "Download could not complete safely", Toast.LENGTH_LONG).show() } }
        }
    }
    private fun updateDownloadCookies(item: Download, url: String, headers: Map<String?, List<String>>) {
        val manager = item.cookies ?: return
        val values = BrowserDownloadHeaders.responseCookies(item.url, url, headers)
        if (values.isEmpty()) return
        val remaining = CountDownLatch(values.size)
        val accepted = AtomicBoolean(true)
        activity.runOnUiThread {
            if (item.owner.downloadEpoch != item.epoch || denied || cleanupPending || !liveAvailable()) {
                accepted.set(false); repeat(values.size) { remaining.countDown() }
            } else values.forEach { cookie ->
                // This is the manager captured from the initiating profile. A
                // private owner being released can never fall back to normal.
                manager.setCookie(url, cookie) { okay -> if (!okay) accepted.set(false); remaining.countDown() }
            }
        }
        check(remaining.await(10, TimeUnit.SECONDS) && accepted.get() && item.owner.downloadEpoch == item.epoch && !denied && !cleanupPending)
    }
    fun hideFullscreen(): Boolean {
        val view = fullscreen ?: return false
        if (Build.VERSION.SDK_INT >= 33) fullscreenBack?.let { activity.onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it) }
        fullscreenBack = null
        (view.parent as? ViewGroup)?.removeView(view); fullscreen = null
        fullscreenCallback?.onCustomViewHidden(); fullscreenCallback = null
        return true
    }
}
