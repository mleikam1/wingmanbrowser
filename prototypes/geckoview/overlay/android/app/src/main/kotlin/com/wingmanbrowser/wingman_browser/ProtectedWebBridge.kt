package com.wingmanbrowser.wingman_browser

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.Toast
import io.flutter.plugin.common.*
import io.flutter.plugin.platform.*
import org.json.JSONArray
import org.json.JSONObject
import org.mozilla.geckoview.*
import java.util.UUID
import java.util.concurrent.Executors

/** Isolated Gecko prototype. The mandatory background extension must acknowledge every configuration. */
class ProtectedWebBridge(private val context: Context, private val channel: MethodChannel) {
    companion object {
        const val VIEW_TYPE = "wingman/protected-web"
        const val UPLOAD_REQUEST = 7110
        const val DOWNLOAD_REQUEST = 7111
        const val PERMISSION_REQUEST = 7112
        const val EXTENSION_ID = "wingman-policy@wingmanbrowser.test"
        const val ENGINE = "155.0.20260903215306"
    }
    private val activity get() = context as Activity
    private val handler = Handler(Looper.getMainLooper())
    private val policy = ConsumerProtectionPolicy(context)
    private val runtime = GeckoRuntime.create(context, GeckoRuntimeSettings.Builder()
        .javaScriptEnabled(true).remoteDebuggingEnabled(false).consoleOutput(false)
        .aboutConfigEnabled(false).extensionsWebAPIEnabled(false).loginAutofillEnabled(false)
        .contentBlocking(ContentBlocking.Settings.Builder()
            .antiTracking(ContentBlocking.AntiTracking.DEFAULT)
            .safeBrowsing(ContentBlocking.SafeBrowsing.DEFAULT)
            .safeBrowsingRealTimeEnabled(false)
            .cookieBehavior(ContentBlocking.CookieBehavior.ACCEPT_FIRST_PARTY)
            .cookieBehaviorPrivateMode(ContentBlocking.CookieBehavior.ACCEPT_FIRST_PARTY).build()).build())
    private val views = mutableMapOf<Int, ProtectedView>()
    private val capabilityWaiters = mutableListOf<MethodChannel.Result>()
    private var extension: WebExtension? = null
    private var port: WebExtension.Port? = null
    private var privateEnabled = false
    private var policyStage = "installing"
    @Volatile private var extensionReady = false
    private var revision = 1
    private var restrictions = JSONObject().put("blockedDomains", JSONArray()).put("blockedUrls", JSONArray()).put("searchBlocked", false)
    private var denied = false
    private var foreground = true
    private var cleanup = false
    private var full: ProtectedView? = null
    private var fullscreenBack: android.window.OnBackInvokedCallback? = null
    private var upload: PendingFile? = null
    private var pendingDownload: PendingDownload? = null
    private val requests = mutableSetOf<PendingPrompt>()
    private var permissionCompletion: (() -> Unit)? = null
    private val workers = Executors.newSingleThreadExecutor()
    private data class PendingFile(val owner: ProtectedView, val ticket: BrowserDocumentTicket?, val prompt: GeckoSession.PromptDelegate.FilePrompt, val result: GeckoResult<GeckoSession.PromptDelegate.PromptResponse>)
    private data class PendingDownload(val owner: ProtectedView, val epoch: Long, val response: WebResponse, val name: String)
    val factory = object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
            val values = args as? Map<*, *> ?: emptyMap<Any, Any>()
            check(views.size < 12)
            configureRestrictions(values)
            return ProtectedView(context, viewId, values["tabId"] as? String ?: "", values["private"] == true).also { views[viewId] = it }
        }
    }
    init {
        channel.setMethodCallHandler(::handle)
        context.cacheDir.listFiles()?.filter { it.name.startsWith("wingman-gecko-download-") && it.name.endsWith(".part") }?.forEach { it.delete() }
        runtime.setDelegate(object : GeckoRuntime.Delegate { override fun onShutdown() { failGate(); closeAll() } })
        runtime.webExtensionController.ensureBuiltIn("resource://android/assets/wingman-policy/", EXTENSION_ID).accept({ installed ->
            if (installed == null || installed.id != EXTENSION_ID || !installed.isBuiltIn) { failGate(); return@accept }
            extension = installed
            policyStage = "enabling-private"
            installed.setMessageDelegate(messages, "wingman_policy")
            runtime.webExtensionController.setAllowedInPrivateBrowsing(installed, true).accept({ updated ->
                if (updated == null || !updated.isBuiltIn || !updated.metaData.allowedInPrivateBrowsing) { failGate(); return@accept }
                extension = updated; privateEnabled = true; policyStage = "awaiting-policy"
                updated.setMessageDelegate(messages, "wingman_policy")
                configureExtension()
            }, { failGate() })
        }, { failGate() })
    }
    private val messages get() = object : WebExtension.MessageDelegate {
        override fun onConnect(value: WebExtension.Port) {
            val sender = value.sender
            if (value.name != "wingman_policy" || sender.webExtension.id != EXTENSION_ID || !sender.webExtension.isBuiltIn || sender.session != null || sender.environmentType != WebExtension.MessageSender.ENV_TYPE_EXTENSION) { value.disconnect(); return }
            port?.let { if (it !== value) it.disconnect() }; port = value; extensionReady = false
            value.setDelegate(object : WebExtension.PortDelegate {
                override fun onPortMessage(message: Any, source: WebExtension.Port) {
                    if (source !== port || !privateEnabled || denied || cleanup) return
                    val json = message as? JSONObject ?: return
                    if (json.optString("type") == "error") policyStage = "extension-" + json.optString("code").take(64)
                    if (json.optString("type") == "ready" && json.optInt("protocol") == 1 && json.optInt("revision") == revision && json.optLong("sequence") == 1L && json.optString("sha256") == ConsumerProtectionPolicy.SHA256 && json.optString("purpose") == "consumer-policy" && policy.valid()) {
                        extensionReady = true; policyStage = "ready"; flushCapabilities()
                    }
                }
                override fun onDisconnect(source: WebExtension.Port) { if (source === port) { port = null; extensionReady = false; policyStage = "port-disconnected"; views.values.forEach { it.session?.stop() } } }
            })
            configureExtension()
        }
    }
    private fun configureExtension() {
        if (!privateEnabled || denied || cleanup || !policy.valid()) return
        val target = port ?: return
        extensionReady = false
        revision++
        target.postMessage(JSONObject().put("type", "configure").put("protocol", 1).put("edition", "consumer").put("revision", revision).put("restrictions", restrictions))
    }
    private fun failGate() { extensionReady = false; policyStage = "initialization-failed"; flushCapabilities() }
    private fun suspendGate() { extensionReady = false; port?.postMessage(JSONObject().put("type", "suspend").put("protocol", 1)) }
    private fun configureRestrictions(values: Map<*, *>) {
        fun strings(name: String) = (values[name] as? List<*>)?.filterIsInstance<String>() ?: emptyList()
        policy.setAdditionalRestrictions(strings("blockedResourceIds"), strings("blockedCollections"), strings("blockedDomains"), strings("blockedUrls"), values["searchBlocked"] == true)
        val next = JSONObject().put("blockedDomains", JSONArray(strings("blockedDomains"))).put("blockedUrls", JSONArray(strings("blockedUrls"))).put("searchBlocked", values["searchBlocked"] == true || "web-search" in strings("blockedResourceIds") || "web-search" in strings("blockedCollections"))
        if (next.toString() != restrictions.toString()) { restrictions = next; revision++; suspendGate(); views.values.forEach { it.session?.stop() }; configureExtension() }
    }
    fun liveAvailable() = extensionReady && privateEnabled && policy.valid() && !cleanup
    fun privateAvailable() = liveAvailable()
    private fun mayOpen() = liveAvailable() && !denied && foreground
    fun quarantineCompleted() { configureExtension() }
    fun cleanupStarted() { cleanup = true; suspendGate(); closeAll() }
    fun cleanupFinished() { cleanup = false; revision++; configureExtension() }
    fun hideAll() { denied = true; suspendGate(); closeAll() }
    fun restoreOwner() { denied = false; revision++; configureExtension() }
    fun pauseAll() { foreground = false; hideFullscreen(); views.values.forEach { it.session?.setActive(false) } }
    fun resume() { foreground = true; views.values.filter { it.active }.forEach { it.session?.setActive(true) } }
    fun closeAll() { hideFullscreen(); views.values.toList().forEach { it.release() }; cancelUpload(); pendingDownload?.response?.body?.close(); pendingDownload = null }
    // No persisted private profile is restored at startup. This does not claim
    // acknowledgement of Gecko's void clearDataForSessionContext API after close.
    fun purgeRetiredProfiles(completion: (Boolean) -> Unit) { completion(true) }
    fun clearBrowsingData(completion: (Boolean) -> Unit) { runtime.storageController.clearData(StorageController.ClearFlags.ALL).accept({ completion(true) }, { completion(false) }) }
    private fun caps() = mapOf("supported" to liveAvailable(), "privateAvailable" to privateAvailable(), "strictSearchAvailable" to liveAvailable(), "mode" to "consumerWeb", "javascript" to true, "cookies" to true, "storage" to true, "history" to true, "findInPage" to true, "uploads" to true, "downloads" to true, "media" to true, "permissions" to true, "newWindows" to true, "defaultBrowserAvailable" to true, "engine" to "GeckoView isolated prototype", "engineVersion" to ENGINE, "reason" to if (liveAvailable()) null else "Mandatory prototype policy extension needs recovery.")
    private fun flushCapabilities() { val waiting = capabilityWaiters.toList(); capabilityWaiters.clear(); waiting.forEach { it.success(caps()) } }
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (call.method == "capabilities") {
                if (liveAvailable()) result.success(caps()) else { capabilityWaiters.add(result); handler.postDelayed({ if (capabilityWaiters.remove(result)) result.success(caps()) }, 20000) }; return
            }
            if (call.method in setOf("prepareConsumerPolicy", "activateConsumerPolicy", "discardConsumerPolicy", "revertConsumerPolicy")) { result.error("prototype_update_unavailable", "The comparison uses the pinned mandatory baseline only.", null); return }
            if (call.method == "state" && call.argument<Number>("viewId") == null) { result.success(mapOf("ready" to liveAvailable(), "extensionReady" to extensionReady, "privateEnabled" to privateEnabled, "views" to views.size, "revision" to revision, "privateCleanupAcknowledgement" to false, "policyStage" to policyStage, "nativePolicy" to policy.diagnostic, "portConnected" to (port != null))); return }
            if (call.method == "configurePolicy") { configureRestrictions(call.arguments as? Map<*, *> ?: emptyMap<Any,Any>()); result.success(null); return }
            val view = views[call.argument<Number>("viewId")?.toInt()] ?: error("view unavailable")
            call.argument<Number>("requestId")?.toLong()?.let { check(it >= view.requestId); view.requestId = it }
            when (call.method) {
                "open" -> view.open(call.argument<String>("url") ?: "")
                "openSearch" -> view.open(strictSearchURL(call.argument<String>("query") ?: "") ?: error("query"))
                "reload" -> { check(mayOpen()); if (view.session == null) view.open(view.url) else view.session?.reload() }
                "back" -> { check(mayOpen()); view.session?.goBack() }
                "forward" -> { check(mayOpen()); view.session?.goForward() }
                "stop" -> { view.session?.stop(); view.loading = false; view.emit() }
                "close" -> { view.release(); views.remove(view.id) }
                "setActive" -> view.setVisibilityActive(call.argument<Boolean>("active") == true)
                "find" -> view.find(call.argument<String>("query")?.take(1024), true)
                "findNext" -> view.find(null, call.argument<Boolean>("forward") != false)
                "clearFind" -> view.session?.finder?.clear()
                "share" -> { check(policy.decide(view.url).allowed); activity.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, view.url) }, "Share page")) }
                "updateRestrictions" -> configureRestrictions(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                "state" -> { result.success(view.state()); return }
                else -> error("method unavailable")
            }
            result.success(null)
        } catch (_: Exception) { result.error("protected_navigation_denied", "The operation could not complete with the required protections.", null) }
    }
    private inner class ProtectedView(context: Context, val id: Int, val tabId: String, val privateMode: Boolean) : PlatformView {
        val container = FrameLayout(context)
        var surface: GeckoView? = null
        var session: GeckoSession? = null
        var url = ""; var title = ""; var requestId = 0L; var progress = 0; var loading = false
        var error: String? = null; var active = true; var back = false; var forward = false
        @Volatile var epoch = 0L
        val scope = BrowserDocumentScope()
        private var disposed = false
        private val privateContext = if (privateMode) "wingman-private-${UUID.randomUUID()}" else null
        fun ownsSession(candidate: GeckoSession) = !disposed && session === candidate
        override fun getView(): View = container
        override fun dispose() { release(); disposed = true; views.remove(id) }
        fun state(): Map<String,Any?> = mapOf("viewId" to id,"requestId" to requestId,"url" to url,"title" to title,"progress" to progress,"isLoading" to loading,"error" to error,"hasRenderer" to (session != null),"private" to privateMode,"javascript" to true,"engineNetworkBlocked" to !liveAvailable(),"strictSearch" to url.startsWith("https://safe.duckduckgo.com/"),"canGoBack" to back,"canGoForward" to forward,"blockedResources" to 0,"requestAttempts" to 0)
        fun emit() { if (!disposed) channel.invokeMethod("pageState", state()) }
        fun block(raw: String, reason: String?) { session?.stop(); loading = false; channel.invokeMethod("navigationBlocked", mapOf("viewId" to id,"requestId" to requestId,"url" to raw,"reason" to (reason ?: "Blocked by protection."))); emit() }
        fun setVisibilityActive(value: Boolean) { active = value; surface?.visibility = if (value && !denied) View.VISIBLE else View.INVISIBLE; session?.setActive(value && foreground && !denied) }
        fun open(raw: String) {
            check(mayOpen() && !disposed && tabId.isNotBlank())
            val decision = policy.decide(raw); if (!decision.allowed) { block(raw,decision.reason); error("blocked") }
            if (session != null && url == decision.url && error == null) { setVisibilityActive(true); emit(); return }
            if (session == null) create()
            url = decision.url; error = null; loading = true; setVisibilityActive(true); emit(); session!!.loadUri(url)
        }
        private fun create() {
            var initialEmptyDocument = true
            check(liveAvailable() && (!privateMode || privateAvailable()))
            val gecko = GeckoSession(GeckoSessionSettings.Builder().usePrivateMode(privateMode).contextId(privateContext).suspendMediaWhenInactive(true).build())
            session = gecko
            val view = object : GeckoView(activity) {
                override fun onCreateInputConnection(info: EditorInfo): InputConnection? = super.onCreateInputConnection(info).also { if (privateMode && Build.VERSION.SDK_INT >= 26) info.imeOptions = info.imeOptions or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING }
            }
            view.setViewBackend(GeckoView.BACKEND_TEXTURE_VIEW)
            surface = view; if (privateMode) view.setAutofillEnabled(false)
            gecko.navigationDelegate = object : GeckoSession.NavigationDelegate {
                override fun onLoadRequest(session: GeckoSession, request: GeckoSession.NavigationDelegate.LoadRequest): GeckoResult<AllowOrDeny> {
                    if (!ownsSession(session)) return GeckoResult.fromValue(AllowOrDeny.DENY)
                    val decision = policy.decide(request.uri)
                    if (!liveAvailable() || denied || !decision.allowed) { block(request.uri,decision.reason); return GeckoResult.fromValue(AllowOrDeny.DENY) }
                    // This delegate has no HTTP method/body. The mandatory
                    // method-aware extension rewrites GET or denies unsupported POST.
                    // App-owned open/search already serialize their own GET URLs.
                    if (request.target == GeckoSession.NavigationDelegate.TARGET_WINDOW_NEW && !request.hasUserGesture) return GeckoResult.fromValue(AllowOrDeny.DENY)
                    return GeckoResult.fromValue(AllowOrDeny.ALLOW)
                }
                override fun onNewSession(session: GeckoSession, uri: String): GeckoResult<GeckoSession>? {
                    if (!ownsSession(session)) return null
                    if (active && mayOpen() && policy.decide(uri).allowed) channel.invokeMethod("newWindowRequested",mapOf("viewId" to id,"requestId" to requestId,"url" to uri))
                    return null
                }
                override fun onLocationChange(session: GeckoSession, location: String?, perms: MutableList<GeckoSession.PermissionDelegate.ContentPermission>, hasUserGesture: Boolean) {
                    if (!ownsSession(session) || location == null) return
                    if (initialEmptyDocument && location == "about:blank") return
                    val decision = policy.decide(location)
                    if (!decision.allowed) {
                        // History API changes can occur without a network request.
                        // Retire this document before any queued callback can restore it.
                        error = decision.reason ?: "Blocked by protection."
                        release()
                        block(location, error)
                        return
                    }
                    url = location; emit()
                }
                override fun onCanGoBack(session: GeckoSession, value: Boolean) { if (!ownsSession(session)) return; back = value; emit() }
                override fun onCanGoForward(session: GeckoSession, value: Boolean) { if (!ownsSession(session)) return; forward = value; emit() }
                override fun onLoadError(session: GeckoSession, uri: String?, failure: WebRequestError): GeckoResult<String>? { if (!ownsSession(session)) return null; error = "The page could not connect safely (${failure.code})."; loading = false; emit(); return null }
            }
            gecko.progressDelegate = object : GeckoSession.ProgressDelegate {
                override fun onPageStart(session: GeckoSession, location: String) {
                    if (!ownsSession(session)) return
                    // A new GeckoSession starts with an engine-owned empty document.
                    // Stopping it would race the app's already queued first web load.
                    // User requests still pass the normal scheme/policy gate.
                    if (initialEmptyDocument && location == "about:blank") return
                    initialEmptyDocument = false
                    invalidateDocument(); if (!policy.decide(location).allowed) { block(location,null); return }; url = location; loading = true; progress = 0; error = null; emit() }
                override fun onProgressChange(session: GeckoSession, value: Int) { if (!ownsSession(session) || initialEmptyDocument) return; progress = value; emit() }
                override fun onPageStop(session: GeckoSession, success: Boolean) { if (!ownsSession(session) || initialEmptyDocument) return; loading = false; if (success) progress = 100; emit() }
            }
            gecko.contentDelegate = object : GeckoSession.ContentDelegate {
                override fun onTitleChange(session: GeckoSession, value: String?) { if (!ownsSession(session) || initialEmptyDocument) return; title = value?.take(1024) ?: ""; emit() }
                override fun onFocusRequest(session: GeckoSession) { if (ownsSession(session) && active && mayOpen()) view.requestFocus() }
                override fun onCloseRequest(session: GeckoSession) { if (!ownsSession(session)) return; channel.invokeMethod("closeRequested",mapOf("viewId" to id,"requestId" to requestId)) }
                override fun onFullScreen(session: GeckoSession, fullscreen: Boolean) { if (!ownsSession(session)) return; if (fullscreen && active && mayOpen()) showFullscreen(this@ProtectedView) else hideFullscreen() }
                override fun onExternalResponse(session: GeckoSession, response: WebResponse) { if (ownsSession(session)) download(this@ProtectedView,response) else runCatching { response.body?.close() } }
                override fun onCrash(session: GeckoSession) { crashed(session) }
                override fun onKill(session: GeckoSession) { crashed(session) }
                private fun crashed(candidate: GeckoSession) {
                    if (!ownsSession(candidate)) return
                    error = "The page renderer stopped. Reload to try again."
                    release(); emit(); channel.invokeMethod("rendererGone",mapOf("viewId" to id,"requestId" to requestId)) }
            }
            gecko.selectionActionDelegate = BasicSelectionActionDelegate(activity).apply { enableExternalActions(false) }
            gecko.permissionDelegate = permissions(this)
            gecko.promptDelegate = prompts(this)
            gecko.open(runtime); view.setSession(gecko); container.addView(view,FrameLayout.LayoutParams(-1,-1))
        }
        fun find(query: String?, next: Boolean) {
            val ownerSession = session ?: return
            val ticket = scope.issue(url)
            ownerSession.finder.apply {
                setDisplayFlags(GeckoSession.FINDER_DISPLAY_HIGHLIGHT_ALL)
                find(query,if (next) GeckoSession.FINDER_FIND_FORWARD else GeckoSession.FINDER_FIND_BACKWARDS).accept({ found ->
                    if (found != null && ownsSession(ownerSession) && scope.owns(ticket,url)) channel.invokeMethod("findResult",mapOf("viewId" to id,"requestId" to requestId,"activeMatch" to maxOf(0,found.current - 1),"matches" to maxOf(0,found.total),"done" to true))
                }, {})
            }
        }
        private fun invalidateDocument() { scope.advance(); requests.filter { it.owner === this }.toList().forEach { it.cancel() }; if (upload?.owner === this) cancelUpload() }
        fun release() { val retired = session; session = null; invalidateDocument(); epoch++; if (pendingDownload?.owner === this) { pendingDownload?.response?.body?.close(); pendingDownload = null }; if (full === this) hideFullscreen(); surface?.releaseSession(); if (retired?.isOpen == true) retired.close(); surface?.let { container.removeView(it) }; surface = null; loading = false; privateContext?.let { runtime.storageController.clearDataForSessionContext(it) } }
    }
    private inner class PendingPrompt(val owner: ProtectedView, private val reject: () -> Unit) {
        private val ticket = owner.scope.issue(owner.url)
        var dialog: AlertDialog? = null
        private var done = false
        fun valid() = !done && owner.session != null && owner.scope.owns(ticket,owner.url) && liveAvailable() && !denied && policy.decide(owner.url).allowed
        fun finish(action: () -> Unit) { if (done) return; done = true; requests.remove(this); dialog?.dismiss(); dialog = null; runCatching(action) }
        fun cancel() = finish(reject)
        fun show(builder: AlertDialog.Builder) { dialog = builder.create().also { it.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE); it.show() } }
    }
    private fun pending(owner: ProtectedView, reject: () -> Unit): PendingPrompt? {
        if (owner.session == null || requests.isNotEmpty() || !owner.active || !mayOpen()) { reject(); return null }
        return PendingPrompt(owner,reject).also { requests.add(it) }
    }
    private fun permissions(owner: ProtectedView) = object : GeckoSession.PermissionDelegate {
        override fun onAndroidPermissionsRequest(session: GeckoSession, permissions: Array<out String>?, callback: GeckoSession.PermissionDelegate.Callback) {
            if (!owner.ownsSession(session)) { callback.reject(); return }
            val names = permissions?.toList().orEmpty()
            val accepted = setOf(Manifest.permission.CAMERA,Manifest.permission.RECORD_AUDIO,Manifest.permission.ACCESS_FINE_LOCATION,Manifest.permission.ACCESS_COARSE_LOCATION)
            if (!owner.url.startsWith("https://") || names.isEmpty() || names.any { it !in accepted }) { callback.reject(); return }
            val request = pending(owner) { callback.reject() } ?: return
            request.show(AlertDialog.Builder(activity).setTitle("Website permission").setMessage("${browserOrigin(owner.url)} wants ${names.joinToString { it.substringAfterLast('.').lowercase().replace('_',' ') }} for this page.")
                .setNegativeButton("Deny") { _,_ -> request.cancel() }.setOnCancelListener { request.cancel() }
                .setPositiveButton("Allow") { _,_ -> if (!request.valid()) request.cancel() else withPermissions(names) { if (request.valid() && names.all { activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) request.finish { callback.grant() } else request.cancel() } })
        }
        override fun onContentPermissionRequest(session: GeckoSession, permission: GeckoSession.PermissionDelegate.ContentPermission): GeckoResult<Int> {
            if (!owner.ownsSession(session) || permission.permission != GeckoSession.PermissionDelegate.PERMISSION_GEOLOCATION || browserOrigin(permission.uri) != browserOrigin(owner.url) || !permission.uri.startsWith("https://")) return GeckoResult.fromValue(GeckoSession.PermissionDelegate.ContentPermission.VALUE_DENY)
            val result = GeckoResult<Int>()
            val request = pending(owner) { result.complete(GeckoSession.PermissionDelegate.ContentPermission.VALUE_DENY) } ?: return result
            request.show(AlertDialog.Builder(activity).setTitle("Website location").setMessage("Allow ${browserOrigin(owner.url)} to access location for this page?")
                .setNegativeButton("Deny") { _,_ -> request.cancel() }.setOnCancelListener { request.cancel() }
                .setPositiveButton("Allow") { _,_ -> withPermissions(listOf(Manifest.permission.ACCESS_FINE_LOCATION,Manifest.permission.ACCESS_COARSE_LOCATION)) { if (request.valid() && activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) request.finish { result.complete(GeckoSession.PermissionDelegate.ContentPermission.VALUE_ALLOW) } else request.cancel() } })
            return result
        }
        override fun onMediaPermissionRequest(session: GeckoSession, uri: String, video: Array<out GeckoSession.PermissionDelegate.MediaSource>?, audio: Array<out GeckoSession.PermissionDelegate.MediaSource>?, callback: GeckoSession.PermissionDelegate.MediaCallback) {
            if (!owner.ownsSession(session) || !uri.startsWith("https://") || browserOrigin(uri) != browserOrigin(owner.url)) { callback.reject(); return }
            val request = pending(owner) { callback.reject() } ?: return
            val names = listOfNotNull(if (!video.isNullOrEmpty()) Manifest.permission.CAMERA else null,if (!audio.isNullOrEmpty()) Manifest.permission.RECORD_AUDIO else null)
            request.show(AlertDialog.Builder(activity).setTitle("Website permission").setMessage("${browserOrigin(uri)} wants ${names.joinToString { if (it == Manifest.permission.CAMERA) "camera" else "microphone" }} for this page.")
                .setNegativeButton("Deny") { _,_ -> request.cancel() }.setOnCancelListener { request.cancel() }
                .setPositiveButton("Allow") { _,_ -> withPermissions(names) { if (request.valid() && names.all { activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) request.finish { callback.grant(video?.firstOrNull(),audio?.firstOrNull()) } else request.cancel() } })
        }
    }
    private fun withPermissions(names: List<String>, completion: () -> Unit) {
        if (names.all { activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) { completion(); return }
        if (permissionCompletion != null) { completion(); return }
        permissionCompletion = completion; activity.requestPermissions(names.toTypedArray(),PERMISSION_REQUEST)
    }
    fun onRequestPermissionsResult(code: Int): Boolean { if (code != PERMISSION_REQUEST) return false; val callback = permissionCompletion; permissionCompletion = null; callback?.invoke(); return true }
    private fun prompts(owner: ProtectedView) = object : GeckoSession.PromptDelegate {
        override fun onAuthPrompt(session: GeckoSession, prompt: GeckoSession.PromptDelegate.AuthPrompt): GeckoResult<GeckoSession.PromptDelegate.PromptResponse> {
            val result = GeckoResult<GeckoSession.PromptDelegate.PromptResponse>()
            if (!owner.ownsSession(session)) { result.complete(prompt.dismiss()); return result }
            val uri = prompt.authOptions.uri.orEmpty()
            val flags = prompt.authOptions.flags
            val forbidden = GeckoSession.PromptDelegate.AuthPrompt.AuthOptions.Flags.PROXY or GeckoSession.PromptDelegate.AuthPrompt.AuthOptions.Flags.CROSS_ORIGIN_SUB_RESOURCE
            if (!uri.startsWith("https://") || browserOrigin(uri) != browserOrigin(owner.url) || flags and forbidden != 0 || prompt.authOptions.level != GeckoSession.PromptDelegate.AuthPrompt.AuthOptions.Level.SECURE) { result.complete(prompt.dismiss()); return result }
            val request = pending(owner) { result.complete(prompt.dismiss()) } ?: return result
            val layout = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setPadding(48,0,48,0); if (Build.VERSION.SDK_INT >= 26) importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS }
            fun field(label: String, secret: Boolean) = EditText(activity).apply { hint = label; contentDescription = label; isSingleLine = true; inputType = InputType.TYPE_CLASS_TEXT or if (secret) InputType.TYPE_TEXT_VARIATION_PASSWORD else InputType.TYPE_TEXT_VARIATION_NORMAL; filters = arrayOf(android.text.InputFilter.LengthFilter(1024)); if (Build.VERSION.SDK_INT >= 26) imeOptions = imeOptions or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING }
            val username = field("Username",false); val password = field("Password",true); layout.addView(username); layout.addView(password)
            request.show(AlertDialog.Builder(activity).setTitle("Website sign-in").setMessage("${browserOrigin(uri)}\nCredentials are sent only to this HTTPS site.").setView(layout)
                .setNegativeButton("Cancel") { _,_ -> request.cancel() }.setOnCancelListener { request.cancel() }
                .setPositiveButton("Sign in") { _,_ -> val user = username.text.toString(); val secret = password.text.toString(); username.text.clear(); password.text.clear(); if (request.valid()) request.finish { result.complete(prompt.confirm(user,secret)) } else request.cancel() })
            request.dialog?.setOnDismissListener { username.text.clear(); password.text.clear() }
            return result
        }
        override fun onFilePrompt(session: GeckoSession, prompt: GeckoSession.PromptDelegate.FilePrompt): GeckoResult<GeckoSession.PromptDelegate.PromptResponse> {
            val result = GeckoResult<GeckoSession.PromptDelegate.PromptResponse>()
            if (!owner.ownsSession(session)) { result.complete(prompt.dismiss()); return result }
            cancelUpload()
            if (!owner.active || !mayOpen() || prompt.type == GeckoSession.PromptDelegate.FilePrompt.Type.FOLDER) { result.complete(prompt.dismiss()); return result }
            upload = PendingFile(owner,owner.scope.issue(owner.url),prompt,result)
            val types = prompt.mimeTypes?.filter { it.matches(Regex("^[a-zA-Z0-9.+*-]+/[a-zA-Z0-9.+*-]+$")) }.orEmpty()
            try { activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type = if (types.size == 1) types[0] else "*/*"; if (types.size > 1) putExtra(Intent.EXTRA_MIME_TYPES,types.toTypedArray()); putExtra(Intent.EXTRA_ALLOW_MULTIPLE,prompt.type == GeckoSession.PromptDelegate.FilePrompt.Type.MULTIPLE); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION) },UPLOAD_REQUEST) } catch (_: Exception) { cancelUpload() }
            return result
        }
        override fun onRepostConfirmPrompt(session: GeckoSession, prompt: GeckoSession.PromptDelegate.RepostConfirmPrompt): GeckoResult<GeckoSession.PromptDelegate.PromptResponse> {
            val result = GeckoResult<GeckoSession.PromptDelegate.PromptResponse>(); if (!owner.ownsSession(session)) { result.complete(prompt.dismiss()); return result }; val request = pending(owner) { result.complete(prompt.dismiss()) } ?: return result
            request.show(AlertDialog.Builder(activity).setTitle("Resubmit form?").setMessage("This sends the form again to ${browserOrigin(owner.url)}.").setNegativeButton("Cancel") { _,_ -> request.cancel() }.setOnCancelListener { request.cancel() }.setPositiveButton("Resubmit") { _,_ -> if (request.valid()) request.finish { result.complete(prompt.confirm(AllowOrDeny.ALLOW)) } else request.cancel() }); return result
        }
    }
    private fun cancelUpload() { val item = upload; upload = null; item?.let { runCatching { it.result.complete(it.prompt.dismiss()) } } }
    private fun download(owner: ProtectedView, response: WebResponse) {
        if (!owner.active || !mayOpen() || !policy.decide(response.uri).allowed || response.body == null) { response.body?.close(); return }
        val mime = response.headers.entries.firstOrNull { it.key.equals("content-type",true) }?.value ?: "application/octet-stream"
        val disposition = response.headers.entries.firstOrNull { it.key.equals("content-disposition",true) }?.value
        val name = android.webkit.URLUtil.guessFileName(response.uri,disposition,mime).replace(Regex("[^A-Za-z0-9._ -]"),"_").take(160)
        if (name.substringAfterLast('.',"").lowercase() in setOf("apk","exe","msi","dmg","pkg","bat","cmd","sh","ps1","js","jar")) { response.body?.close(); owner.block(response.uri,"Executable downloads are not supported."); return }
        val request = pending(owner) { response.body?.close() } ?: return
        request.show(AlertDialog.Builder(activity).setTitle("Save download?").setMessage("${browserOrigin(response.uri)}\n$name" + if (owner.privateMode) "\nThe saved file remains after closing this private tab." else "")
            .setNegativeButton("Cancel") { _,_ -> request.cancel() }.setOnCancelListener { request.cancel() }.setPositiveButton("Save") { _,_ ->
                if (!request.valid()) { request.cancel(); return@setPositiveButton }
                request.finish {
                    pendingDownload?.response?.body?.close(); pendingDownload = PendingDownload(owner,owner.epoch,response,name)
                    try { activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type = mime.substringBefore(';'); putExtra(Intent.EXTRA_TITLE,name) },DOWNLOAD_REQUEST) } catch (_: Exception) { pendingDownload = null; response.body?.close() }
                }
            })
    }
    fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code == UPLOAD_REQUEST) {
            val item = upload; upload = null
            if (item != null) {
                val values = mutableListOf<Uri>(); data?.data?.let { values.add(it) }; data?.clipData?.let { clip -> for (i in 0 until minOf(20,clip.itemCount)) values.add(clip.getItemAt(i).uri) }
                val files = values.distinct().filter { it.scheme == "content" && it.authority != context.packageName }
                if (resultCode == Activity.RESULT_OK && files.isNotEmpty() && item.owner.session != null && item.owner.scope.owns(item.ticket,item.owner.url) && liveAvailable() && !denied) item.result.complete(item.prompt.confirm(context,files.toTypedArray())) else item.result.complete(item.prompt.dismiss())
            }; return true
        }
        if (code == DOWNLOAD_REQUEST) {
            val item = pendingDownload; pendingDownload = null; val target = data?.data
            if (item != null) { if (resultCode == Activity.RESULT_OK && target?.scheme == "content") save(item,target) else item.response.body?.close() }; return true
        }; return false
    }
    private fun save(item: PendingDownload, target: Uri) {
        workers.execute {
            var okay = false; val temp = java.io.File.createTempFile("wingman-gecko-download-",".part",context.cacheDir)
            try {
                check(liveAvailable() && !denied && item.owner.epoch == item.epoch && policy.decide(item.response.uri).allowed)
                val deadline = System.nanoTime() + 120_000_000_000L
                item.response.body!!.use { input -> temp.outputStream().use { output -> val buffer = ByteArray(16384); var total = 0L; while (true) { check(System.nanoTime() < deadline && item.owner.epoch == item.epoch && liveAvailable() && !denied); val count = input.read(buffer); if (count < 0) break; total += count; check(total <= 100L*1024*1024); output.write(buffer,0,count) } } }
                check(item.owner.epoch == item.epoch && liveAvailable() && !denied)
                context.contentResolver.openOutputStream(target,"wt")!!.use { output -> temp.inputStream().use { it.copyTo(output) } }; okay = true
            } catch (_: Exception) { runCatching { item.response.body?.close() } }
            finally { temp.delete(); handler.post { Toast.makeText(context,if (okay) "Download saved" else "Download could not complete safely",Toast.LENGTH_LONG).show() } }
        }
    }
    private fun showFullscreen(owner: ProtectedView) {
        hideFullscreen(); val view = owner.surface ?: return; full = owner
        owner.container.removeView(view); (activity.window.decorView as ViewGroup).addView(view,ViewGroup.LayoutParams(-1,-1))
        if (Build.VERSION.SDK_INT >= 33) { val callback = android.window.OnBackInvokedCallback { hideFullscreen() }; fullscreenBack = callback; activity.onBackInvokedDispatcher.registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_OVERLAY,callback) }
    }
    fun hideFullscreen(): Boolean {
        val owner = full ?: return false; full = null
        if (Build.VERSION.SDK_INT >= 33) fullscreenBack?.let { activity.onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it) }; fullscreenBack = null
        owner.surface?.let { (it.parent as? ViewGroup)?.removeView(it); owner.container.addView(it,FrameLayout.LayoutParams(-1,-1)) }; owner.session?.exitFullScreen(); return true
    }
}
