package com.wingmanbrowser.wingman_browser

import android.app.Activity
import android.os.Bundle
import android.view.WindowManager
import android.widget.FrameLayout
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import io.flutter.plugin.platform.PlatformView
import org.mozilla.geckoview.GeckoSession
import java.nio.ByteBuffer
import java.util.concurrent.LinkedBlockingQueue

/**
 * Debug-only host for the actual prototype adapter, not an alternate policy engine.
 * The test reads normal native pageState events. No JavaScript/page message bridge
 * is registered, and the activity has no externally exported entry point.
 */
class GeckoPolicyProbeActivity : Activity() {
    val nativeEvents = LinkedBlockingQueue<MethodCall>()
    private val messenger = ProbeMessenger(nativeEvents)
    private lateinit var bridge: ProtectedWebBridge
    private lateinit var frame: FrameLayout
    private var platformView: PlatformView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        frame = FrameLayout(this)
        setContentView(frame)
        // ConsumerProtectionPolicy uses Flutter's real asset lookup key. Starting
        // a Dart isolate or overriding the policy asset would change the proof.
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        bridge = ProtectedWebBridge(this, MethodChannel(messenger, CHANNEL))
    }

    /** Must run on Android's main thread, just as PlatformViewFactory normally does. */
    fun createProtectedView(id: Int, privateMode: Boolean) {
        platformView?.dispose()
        frame.removeAllViews()
        nativeEvents.clear()
        platformView = bridge.factory.create(this, id, mapOf(
            "tabId" to "instrumentation-fixture-$id",
            "edition" to "consumer",
            "private" to privateMode,
            "blockedDomains" to listOf("127.0.0.1"),
            "blockedUrls" to emptyList<String>(),
            "blockedResourceIds" to emptyList<String>(),
            "blockedCollections" to emptyList<String>(),
            "searchBlocked" to false,
        ))
        frame.addView(platformView!!.view, FrameLayout.LayoutParams(-1, -1))
    }

    /** Sends the same StandardMethodCodec request that the Flutter surface sends. */
    fun invokeBridge(method: String, args: Map<String, Any?> = emptyMap(), reply: (Any?, Throwable?) -> Unit) {
        messenger.deliver(MethodCall(method, args), reply)
    }

    /**
     * Test-only reflection into the actual adapter. Retaining old delegates lets
     * instrumentation simulate callbacks already queued before renderer loss.
     * No release-build API, page bridge, or second GeckoRuntime is introduced.
     */
    fun captureCurrentSessionCallbacks(id: Int): SessionCallbacks {
        val views = bridge.javaClass.getDeclaredField("views").apply { isAccessible = true }.get(bridge) as Map<*, *>
        val owner = checkNotNull(views[id]) { "Actual protected view is missing" }
        val session = owner.javaClass.getDeclaredField("session").apply { isAccessible = true }.get(owner) as GeckoSession
        return SessionCallbacks(session, checkNotNull(session.contentDelegate), checkNotNull(session.progressDelegate), checkNotNull(session.navigationDelegate))
    }

    data class SessionCallbacks(
        val session: GeckoSession,
        val content: GeckoSession.ContentDelegate,
        val progress: GeckoSession.ProgressDelegate,
        val navigation: GeckoSession.NavigationDelegate,
    )

    override fun onResume() {
        super.onResume()
        if (::bridge.isInitialized) bridge.resume()
    }

    override fun onPause() {
        if (::bridge.isInitialized) bridge.pauseAll()
        super.onPause()
    }

    override fun onDestroy() {
        platformView?.dispose()
        platformView = null
        if (::bridge.isInitialized) bridge.closeAll()
        super.onDestroy()
    }

    private class ProbeMessenger(private val events: LinkedBlockingQueue<MethodCall>) : BinaryMessenger {
        private val codec = StandardMethodCodec.INSTANCE
        private val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()
        override fun send(channel: String, message: ByteBuffer?) = send(channel, message, null)
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
            if (channel == CHANNEL && message != null) events.offer(codec.decodeMethodCall(readable(message)))
            callback?.reply(readable(codec.encodeSuccessEnvelope(null)))
        }
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (handler == null) handlers.remove(channel) else handlers[channel] = handler
        }
        fun deliver(call: MethodCall, completion: (Any?, Throwable?) -> Unit) {
            val handler = handlers[CHANNEL]
            if (handler == null) {
                completion(null, IllegalStateException("Actual protected bridge handler is missing"))
                return
            }
            handler.onMessage(readable(codec.encodeMethodCall(call))) { response ->
                try {
                    check(response != null) { "Actual bridge did not implement ${call.method}" }
                    completion(codec.decodeEnvelope(readable(response)), null)
                } catch (failure: Throwable) { completion(null, failure) }
            }
        }
        // Flutter's engine transport flips the encoded, write-position buffer.
        // This in-process transport performs exactly that framing step.
        private fun readable(value: ByteBuffer): ByteBuffer = value.duplicate().apply { flip() }
    }

    companion object { private const val CHANNEL = "wingman/protected-browser" }
}
