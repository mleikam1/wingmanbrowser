package com.wingmanbrowser.wingman_browser

import org.junit.Assert.*
import org.junit.Test

class BrowserRequestGuardsTest {
    @Test fun originUsesBrowserDefaultPortSemantics() {
        assertEquals("https://example.com", browserOrigin("https://EXAMPLE.com:443/account?q=private"))
        assertEquals("http://example.com", browserOrigin("http://example.com:80/"))
        assertEquals("https://example.com:8443", browserOrigin("https://example.com:8443/"))
        assertEquals("https://[::1]", browserOrigin("https://[::1]:443/"))
        assertNull(browserOrigin("https://user:secret@example.com/"))
        assertNull(browserOrigin("file:///private/account"))
    }

    @Test fun reloadOrSameOriginNavigationInvalidatesPendingDocumentRequest() {
        val scope = BrowserDocumentScope()
        val ticket = scope.issue("https://example.com/one")
        assertTrue(scope.owns(ticket, "https://example.com:443/one#section"))
        scope.advance()
        assertFalse(scope.owns(ticket, "https://example.com/two"))
        assertFalse(scope.owns(ticket, "https://example.com/one"))
    }

    @Test fun backgroundPauseDoesNotInvalidateDocumentButOriginChangesDo() {
        val scope = BrowserDocumentScope()
        val ticket = scope.issue("https://example.com/one")
        // No generation change for an OS picker/permission overlay.
        assertTrue(scope.owns(ticket, "https://example.com/one"))
        assertFalse(scope.owns(ticket, "https://other.example/one"))
        assertFalse(scope.owns(ticket, "http://example.com/one"))
        assertFalse(scope.owns(ticket, "https://example.com:444/one"))
    }

    @Test fun authenticationRequiresSameHostAndValidHttpsOrigin() {
        assertTrue(permitsHttpAuthentication("https://example.com:8443/account", "EXAMPLE.com"))
        assertFalse(permitsHttpAuthentication("http://example.com/account", "example.com"))
        assertFalse(permitsHttpAuthentication("https://example.com/account", "tracker.example.com"))
        assertFalse(permitsHttpAuthentication("https://user@example.com/account", "example.com"))
    }

    @Test fun downloadKeepsBrowserAgentAndOnlySameOriginCookies() {
        val headers = BrowserDownloadHeaders.request("https://example.com/start", "https://example.com:443/final", "Mozilla/5.0 AppleWebKit/537.36", "session=synthetic; stage=ready")
        assertEquals("Mozilla/5.0 AppleWebKit/537.36", headers["User-Agent"])
        assertEquals("session=synthetic; stage=ready", headers["Cookie"])
        assertFalse(BrowserDownloadHeaders.request("https://example.com/start", "https://cdn.example.com/final", "Mozilla", "secret=x").containsKey("Cookie"))
        assertFalse(BrowserDownloadHeaders.request("https://example.com/start", "http://example.com/final", "Mozilla", "secret=x").containsKey("Cookie"))
    }

    @Test fun responseCookiesAreAdmittedOnlyForInitiatingOrigin() {
        val response = mapOf<String?, List<String>>(null to listOf("HTTP/1.1 302"), "set-cookie" to listOf("stage=ready; HttpOnly; Path=/"))
        assertEquals(listOf("stage=ready; HttpOnly; Path=/"), BrowserDownloadHeaders.responseCookies("https://example.com/start", "https://example.com/redirect", response))
        assertTrue(BrowserDownloadHeaders.responseCookies("https://example.com/start", "https://other.example/redirect", response).isEmpty())
    }

    @Test fun untrustedHeaderValuesCannotInjectAnotherHeaderOrAllocateUnboundedCookies() {
        assertFalse(BrowserDownloadHeaders.request("https://example.com", "https://example.com", "Mozilla\r\nInjected: yes", "a=1\r\nInjected: yes").containsKey("Cookie"))
        assertTrue(BrowserDownloadHeaders.request("https://example.com", "https://example.com", "x".repeat(4097), null).isEmpty())
        val cookies = BrowserDownloadHeaders.responseCookies("https://example.com", "https://example.com", mapOf("Set-Cookie" to List(60) { "a$it=1" }))
        assertEquals(50, cookies.size)
    }
}
