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
    private val blocked: (String, Map<String, Any?>, Long) -> Unit,
    private val trackers: (Int) -> Unit,
) {
    @Volatile var topHost = ""
    @Volatile var closed = false
    @Volatile private var blockedUrl: String? = null
    @Volatile private var delivered = false
    @Volatile private var generation = 0L
    @Volatile private var request = 0L
    private val handler = Handler(Looper.getMainLooper())
    private val trackerCount = AtomicInteger(0)
    private val flushTrackers = Runnable {
        val count = trackerCount.getAndSet(0)
        if (!closed && count > 0) trackers(count)
    }

    @Synchronized fun prepare(url: String, request: Long = this.request) {
        generation++
        this.request = request
        topHost = NativeGuardPolicy.normalizeHost(Uri.parse(url).host ?: "") ?: ""
        blockedUrl = null
        delivered = false
    }

    @Synchronized fun invalidatePendingReports() {
        generation++
        if (!delivered) blockedUrl = null
    }

    fun pageStarted(view: WebView, url: String): Boolean {
        // An older callback must not adopt the identity of a newer app request.
        if (closed || blockedUrl != null || view.url != url) return false
        topHost = NativeGuardPolicy.normalizeHost(Uri.parse(url).host ?: "") ?: ""
        return true
    }

    fun deny(view: WebView, url: String, filename: String? = null, mime: String? = null): Boolean {
        if (closed) return false
        val (generation, request) = synchronized(this) { this.generation to this.request }
        val decision = try { policy.evaluate(url, tabId, filename, mime) } catch (_: Exception) { null }
            ?: return false
        report(view, url, decision, generation, request)
        return true
    }

    fun report(view: WebView, url: String, decision: Map<String, Any?>, generation: Long = this.generation, request: Long = this.request) {
        synchronized(this) {
            if (closed || this.generation != generation || this.request != request || blockedUrl == url) return
            blockedUrl = url
            delivered = false
        }
        val deliver = Runnable {
            if (!closed && this.generation == generation && this.request == request && blockedUrl == url) {
                delivered = true
                view.visibility = View.INVISIBLE
                view.stopLoading()
                blocked(url, decision, request)
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) deliver.run() else handler.post(deliver)
    }

    fun trackerBlocked() {
        if (trackerCount.getAndIncrement() == 0) handler.postDelayed(flushTrackers, 400)
    }

    fun rewriteSearch(view: WebView, url: String): Boolean {
        val safe = policy.safeSearch(url)
        if (safe == url) return false
        val generation = this.generation
        handler.post { if (!closed && this.generation == generation) { view.stopLoading(); prepare(safe); view.loadUrl(safe) } }
        return true
    }

    fun isBlocked() = blockedUrl != null
    fun close() { closed = true; handler.removeCallbacksAndMessages(null); trackerCount.set(0); topHost = ""; blockedUrl = null }
}
