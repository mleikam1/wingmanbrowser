package com.wingmanbrowser.wingman_browser

import android.graphics.Bitmap
import android.net.http.SslError
import android.os.Message
import android.view.KeyEvent
import android.webkit.*

/** Keeps the official Flutter client's policy and callbacks; adds renderer-death recovery only. */
open class GuardedWebViewClient(
    protected val original: WebViewClient,
    private val rendererGone: (WebView) -> Unit,
) : WebViewClient() {
    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = original.shouldOverrideUrlLoading(view, request)
    @Suppress("DEPRECATION")
    override fun shouldOverrideUrlLoading(view: WebView, url: String) = original.shouldOverrideUrlLoading(view, url)
    override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) = original.onPageStarted(view, url, favicon)
    override fun onPageFinished(view: WebView, url: String) = original.onPageFinished(view, url)
    override fun onLoadResource(view: WebView, url: String) = original.onLoadResource(view, url)
    override fun onPageCommitVisible(view: WebView, url: String) = original.onPageCommitVisible(view, url)
    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? = original.shouldInterceptRequest(view, request)
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
    override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
        rendererGone(view)
        return true // The app owns teardown; Android must not kill the host process.
    }
}

/** Kept separate so API 26 never resolves API 27's SafeBrowsingResponse type. */
class GuardedWebViewClient27(original: WebViewClient, rendererGone: (WebView) -> Unit)
    : GuardedWebViewClient(original, rendererGone) {
    override fun onSafeBrowsingHit(view: WebView, request: WebResourceRequest, threatType: Int, callback: SafeBrowsingResponse) = original.onSafeBrowsingHit(view, request, threatType, callback)
}
