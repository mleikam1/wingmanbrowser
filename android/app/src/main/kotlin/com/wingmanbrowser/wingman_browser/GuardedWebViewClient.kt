package com.wingmanbrowser.wingman_browser

import android.graphics.Bitmap
import android.net.http.SslError
import android.os.Message
import android.view.View
import android.view.KeyEvent
import android.webkit.*
import java.io.ByteArrayInputStream

/** Adds local policy while preserving the official Flutter client's callbacks. */
open class GuardedWebViewClient(
    protected val original: WebViewClient,
    protected val guard: NativeGuardSession,
) : WebViewClient() {
    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
        if (request.isForMainFrame && guard.deny(view, request.url.toString())) return true
        if (request.isForMainFrame && request.method == "GET" && guard.rewriteSearch(view, request.url.toString())) return true
        return original.shouldOverrideUrlLoading(view, request)
    }
    @Suppress("DEPRECATION")
    override fun shouldOverrideUrlLoading(view: WebView, url: String) = original.shouldOverrideUrlLoading(view, url)
    override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
        // Keep provisional content hidden until the final committed URL passes.
        // This covers provider callback gaps such as POST-preserving redirects.
        view.visibility = View.INVISIBLE
        guard.prepare(url)
        if (!guard.deny(view, url)) original.onPageStarted(view, url, favicon)
    }
    override fun onPageFinished(view: WebView, url: String) {
        if (!guard.isBlocked()) original.onPageFinished(view, url)
    }
    override fun onLoadResource(view: WebView, url: String) = original.onLoadResource(view, url)
    override fun onPageCommitVisible(view: WebView, url: String) {
        if (!guard.deny(view, url) && !guard.isBlocked()) {
            view.visibility = View.VISIBLE
            original.onPageCommitVisible(view, url)
        }
    }
    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
        if (request.isForMainFrame) {
            if (guard.deny(view, request.url.toString())) return emptyResponse()
            if (request.method == "GET" && guard.rewriteSearch(view, request.url.toString())) return emptyResponse()
        } else if (!guard.closed && guard.topHost.isNotEmpty() && guard.policy.isTracker(request.url.toString(), guard.topHost)) {
            guard.trackerBlocked()
            return emptyResponse()
        }
        return original.shouldInterceptRequest(view, request)
    }
    private fun emptyResponse() = WebResourceResponse("text/plain", "UTF-8", 200, "OK", mapOf("Cache-Control" to "no-store"), ByteArrayInputStream(ByteArray(0)))
    @Suppress("DEPRECATION")
    override fun shouldInterceptRequest(view: WebView, url: String): WebResourceResponse? = original.shouldInterceptRequest(view, url)
    @Suppress("DEPRECATION")
    override fun onTooManyRedirects(view: WebView, cancelMsg: Message, continueMsg: Message) = original.onTooManyRedirects(view, cancelMsg, continueMsg)
    @Suppress("DEPRECATION")
    override fun onReceivedError(view: WebView, errorCode: Int, description: String, failingUrl: String) = original.onReceivedError(view, errorCode, description, failingUrl)
    override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) = original.onReceivedError(view, request, error)
    override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) = original.onReceivedHttpError(view, request, response)
    override fun onFormResubmission(view: WebView, dontResend: Message, resend: Message) = original.onFormResubmission(view, dontResend, resend)
    override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) = original.doUpdateVisitedHistory(view, url, isReload)
    override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) = original.onReceivedSslError(view, handler, error)
    override fun onReceivedClientCertRequest(view: WebView, request: ClientCertRequest) = original.onReceivedClientCertRequest(view, request)
    override fun onReceivedHttpAuthRequest(view: WebView, handler: HttpAuthHandler, host: String, realm: String) = original.onReceivedHttpAuthRequest(view, handler, host, realm)
    override fun shouldOverrideKeyEvent(view: WebView, event: KeyEvent) = original.shouldOverrideKeyEvent(view, event)
    override fun onUnhandledKeyEvent(view: WebView, event: KeyEvent) = original.onUnhandledKeyEvent(view, event)
    override fun onScaleChanged(view: WebView, oldScale: Float, newScale: Float) = original.onScaleChanged(view, oldScale, newScale)
    override fun onReceivedLoginRequest(view: WebView, realm: String, account: String?, args: String) = original.onReceivedLoginRequest(view, realm, account, args)
}

/** Separate classes avoid resolving newer platform types on Android 7/API24. */
open class GuardedWebViewClient26(original: WebViewClient, guard: NativeGuardSession, private val rendererGone: (WebView) -> Unit)
    : GuardedWebViewClient(original, guard) {
    override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
        rendererGone(view)
        return true // The app owns teardown; Android must not kill the host process.
    }
}

/** Kept separate so API 26 never resolves API 27's SafeBrowsingResponse type. */
class GuardedWebViewClient27(original: WebViewClient, guard: NativeGuardSession, rendererGone: (WebView) -> Unit)
    : GuardedWebViewClient26(original, guard, rendererGone) {
    override fun onSafeBrowsingHit(view: WebView, request: WebResourceRequest, threatType: Int, callback: SafeBrowsingResponse) {
        callback.backToSafety(false)
        if (request.isForMainFrame) {
            val phishing = threatType == WebViewClient.SAFE_BROWSING_THREAT_PHISHING
            guard.report(view, request.url.toString(), mapOf(
                "action" to if (phishing) "blockPhishing" else "blockMalware",
                "host" to (request.url.host ?: ""), "category" to if (phishing) "phishing" else "malware",
                "ruleId" to "android-safe-browsing", "overrideAllowed" to false,
            ))
        }
    }
}
