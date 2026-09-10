package com.wingmanbrowser.wingman_browser

import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import android.webkit.WebView
import java.util.concurrent.atomic.AtomicInteger

/** Per-view state is bounded by the engine pool and is discarded on tab close. */
class NativeGuardSession(
    val policy: NativeGuardPolicy,
    val tabId: String,
    private val blocked: (String, Map<String, Any?>) -> Unit,
    private val trackers: (Int) -> Unit,
) {
    @Volatile var topHost = ""
    @Volatile var closed = false
    @Volatile private var blockedUrl: String? = null
    private val handler = Handler(Looper.getMainLooper())
    private val trackerCount = AtomicInteger(0)
    private val flushTrackers = Runnable {
        val count = trackerCount.getAndSet(0)
        if (!closed && count > 0) trackers(count)
    }

    fun prepare(url: String) {
        topHost = NativeGuardPolicy.normalizeHost(Uri.parse(url).host ?: "") ?: ""
        blockedUrl = null
    }

    fun deny(view: WebView, url: String, filename: String? = null, mime: String? = null): Boolean {
        if (closed) return false
        val decision = try { policy.evaluate(url, tabId, filename, mime) } catch (_: Exception) { null }
            ?: return false
        report(view, url, decision)
        return true
    }

    fun report(view: WebView, url: String, decision: Map<String, Any?>) {
        if (closed || blockedUrl == url) return
        blockedUrl = url
        handler.post {
            if (!closed && blockedUrl == url) {
                view.visibility = View.INVISIBLE
                view.stopLoading()
                blocked(url, decision)
            }
        }
    }

    fun trackerBlocked() {
        if (trackerCount.getAndIncrement() == 0) handler.postDelayed(flushTrackers, 400)
    }

    fun rewriteSearch(view: WebView, url: String): Boolean {
        val safe = policy.safeSearch(url)
        if (safe == url) return false
        handler.post { if (!closed) { view.stopLoading(); prepare(safe); view.loadUrl(safe) } }
        return true
    }

    fun isBlocked() = blockedUrl != null
    fun close() { closed = true; handler.removeCallbacksAndMessages(null); trackerCount.set(0); topHost = ""; blockedUrl = null }
}
