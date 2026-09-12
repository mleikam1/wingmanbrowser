package com.wingmanbrowser.wingman_browser

import android.content.Intent
import android.os.Bundle
import android.test.InstrumentationTestCase
import android.util.Base64
import android.util.Log
import org.mozilla.geckoview.WebResponse
import java.io.ByteArrayInputStream
import java.io.Closeable
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URI
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * Opt-in, installed debug instrumentation. It uses real GeckoView networking,
 * the real bundled blocking extension and the actual native bridge. All test
 * pages and image bytes are served by this test's loopback server. A native
 * title callback provides DOM load/error observations; server counters prove
 * whether the denied destination was reached. This is not consumer UI evidence.
 */
@Suppress("DEPRECATION")
class GeckoResourcePolicyTest : InstrumentationTestCase() {
    fun testRealExtensionRedirectsAndServiceWorkerRequests() {
        LoopbackFixture().use { fixture ->
            val intent = Intent(instrumentation.targetContext, GeckoPolicyProbeActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            val activity = instrumentation.startActivitySync(intent) as GeckoPolicyProbeActivity
            try {
                assertReady(activity)
                runImageCase(activity, fixture, id = 71, privateMode = false)
                runImageCase(activity, fixture, id = 72, privateMode = true)
                // Firefox disables service workers in some private configurations;
                // this explicit normal-context case measures actual worker fetches.
                runWorkerCase(activity, fixture, id = 73)
                runSimulatedStaleCallbackCase(activity, fixture, id = 74)
            } finally {
                instrumentation.runOnMainSync { activity.finish() }
                instrumentation.waitForIdleSync()
            }
        }
    }

    private fun runImageCase(activity: GeckoPolicyProbeActivity, fixture: LoopbackFixture, id: Int, privateMode: Boolean) {
        instrumentation.runOnMainSync { activity.createProtectedView(id, privateMode) }
        assertReady(activity)
        val marker = if (privateMode) "private-$id" else "normal-$id"
        call(activity, "open", mapOf("viewId" to id, "requestId" to 1L, "url" to fixture.page(marker)))
        val title = awaitFixture(activity, fixture, id, marker)
        assertEquals("Normal image decoder must load the allowed positive control", "PROBE-$marker:allowed=load;direct=error;redirect=error", title)
        assertCounts(fixture, marker)
        report("image-$marker", title, fixture.counts(marker))
    }

    private fun runWorkerCase(activity: GeckoPolicyProbeActivity, fixture: LoopbackFixture, id: Int) {
        instrumentation.runOnMainSync { activity.createProtectedView(id, false) }
        assertReady(activity)
        val marker = "worker-$id"
        call(activity, "open", mapOf("viewId" to id, "requestId" to 1L, "url" to fixture.page(marker, worker = true)))
        val title = awaitFixture(activity, fixture, id, marker)
        assertEquals("Worker fetches must traverse the mandatory extension, including redirect targets", "PROBE-$marker:allowed=load;direct=error;redirect=error", title)
        assertCounts(fixture, marker)
        report("service-worker", title, fixture.counts(marker))
    }

    /** Simulated native callback ordering, explicitly not an actual process kill. */
    private fun runSimulatedStaleCallbackCase(activity: GeckoPolicyProbeActivity, fixture: LoopbackFixture, id: Int) {
        runImageCase(activity, fixture, id, privateMode = false)
        val marker = "normal-$id"
        val before = awaitSettledState(activity, id)
        lateinit var old: GeckoPolicyProbeActivity.SessionCallbacks
        instrumentation.runOnMainSync {
            old = activity.captureCurrentSessionCallbacks(id)
            old.content.onKill(old.session)
        }
        val crashed = call(activity, "state", mapOf("viewId" to id)) as Map<*, *>
        assertEquals("Simulated renderer loss must release the actual session", false, crashed["hasRenderer"])
        assertEquals(false, crashed["isLoading"])
        assertTrue("Renderer loss must retain a useful native recovery error", (crashed["error"] as? String)?.isNotBlank() == true)
        assertEquals(before["url"], crashed["url"])
        assertEquals(before["title"], crashed["title"])

        replayStaleCallbacks(activity, old, fixture.page("stale-$id"))
        val afterLate = call(activity, "state", mapOf("viewId" to id)) as Map<*, *>
        assertStableState(crashed, afterLate)

        instrumentation.runOnMainSync { activity.nativeEvents.clear() }
        call(activity, "reload", mapOf("viewId" to id))
        // The retained pre-crash title is published while the replacement is
        // opening. Only a second server response can produce this new marker.
        val title = awaitFixture(activity, fixture, id, marker, titleMarker = "reload-$marker")
        assertEquals("PROBE-reload-$marker:allowed=load;direct=error;redirect=error", title)
        val recovered = awaitSettledState(activity, id)
        assertEquals(true, recovered["hasRenderer"])
        assertEquals(null, recovered["error"])
        instrumentation.runOnMainSync {
            assertNotSame("Reload must allocate a new actual GeckoSession", old.session, activity.captureCurrentSessionCallbacks(id).session)
        }
        assertCounts(fixture, marker, expectedPermittedRequests = 2)

        // Old callbacks must also be inert after a replacement session exists;
        // checking only the null-session interval would miss this ownership bug.
        replayStaleCallbacks(activity, old, fixture.page("stale-after-reload-$id"))
        val afterReplacement = call(activity, "state", mapOf("viewId" to id)) as Map<*, *>
        assertStableState(recovered, afterReplacement)
        report("simulated-stale-callback-recovery", title, fixture.counts(marker))

        // Controlled current-session callback policy proof, not a page History
        // API interaction: cross-host history mutation would be forbidden by JS.
        lateinit var current: GeckoPolicyProbeActivity.SessionCallbacks
        instrumentation.runOnMainSync {
            current = activity.captureCurrentSessionCallbacks(id)
            current.navigation.onLocationChange(current.session, fixture.blockedHistory(), mutableListOf(), false)
        }
        val deniedLocation = call(activity, "state", mapOf("viewId" to id)) as Map<*, *>
        assertEquals("Denied current location must retire the renderer", false, deniedLocation["hasRenderer"])
        assertEquals(false, deniedLocation["isLoading"])
        assertTrue("Policy denial must remain visible in native state", (deniedLocation["error"] as? String)?.isNotBlank() == true)
        assertEquals(recovered["url"], deniedLocation["url"])
        assertEquals(recovered["title"], deniedLocation["title"])
        replayStaleCallbacks(activity, current, fixture.page("stale-after-policy-$id"))
        assertStableState(deniedLocation, call(activity, "state", mapOf("viewId" to id)) as Map<*, *>)
        assertCounts(fixture, marker, expectedPermittedRequests = 2)
        report("simulated-current-location-denial", title, fixture.counts(marker))
    }

    private fun replayStaleCallbacks(activity: GeckoPolicyProbeActivity, old: GeckoPolicyProbeActivity.SessionCallbacks, location: String) {
        val body = object : ByteArrayInputStream(byteArrayOf(1, 2, 3)) {
            var closedByAdapter = false
            override fun close() { closedByAdapter = true; super.close() }
        }
        instrumentation.runOnMainSync {
            old.progress.onPageStart(old.session, location)
            old.progress.onProgressChange(old.session, 7)
            old.content.onTitleChange(old.session, "STALE simulated native title")
            old.navigation.onLocationChange(old.session, location, mutableListOf(), false)
            old.navigation.onCanGoBack(old.session, true)
            old.navigation.onCanGoForward(old.session, true)
            old.progress.onPageStop(old.session, true)
            old.content.onExternalResponse(old.session, WebResponse.Builder(location).body(body).build())
            old.content.onKill(old.session)
        }
        assertTrue("A stale external response must close its body without opening a download", body.closedByAdapter)
    }

    private fun assertStableState(expected: Map<*, *>, actual: Map<*, *>) {
        for (field in listOf("url", "title", "error", "hasRenderer", "isLoading", "progress", "canGoBack", "canGoForward")) {
            assertEquals("A retired session callback must not mutate $field", expected[field], actual[field])
        }
    }

    private fun awaitSettledState(activity: GeckoPolicyProbeActivity, id: Int): Map<*, *> {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(15)
        while (System.nanoTime() < deadline) {
            val state = call(activity, "state", mapOf("viewId" to id)) as Map<*, *>
            if (state["isLoading"] == false && (state["progress"] as? Number)?.toInt() == 100) return state
            activity.nativeEvents.poll(100, TimeUnit.MILLISECONDS)
        }
        throw AssertionError("Controlled fixture did not finish native page loading")
    }

    private fun assertCounts(fixture: LoopbackFixture, marker: String, expectedPermittedRequests: Int = 1) {
        val counts = fixture.counts(marker)
        assertEquals("Allowed control must actually reach the server", expectedPermittedRequests, counts["allowed"])
        assertEquals("Allowed initial redirect URL must actually reach the server", expectedPermittedRequests, counts["redirect"])
        assertEquals("Direct blocked destination must never reach server", 0, counts["denied-direct"])
        assertEquals("Blocked redirected destination must never reach server", 0, counts["denied-redirect"])
    }

    private fun awaitFixture(activity: GeckoPolicyProbeActivity, fixture: LoopbackFixture, id: Int, marker: String, titleMarker: String = marker): String {
        try { return awaitTitle(activity, id, "PROBE-$titleMarker:") }
        catch (failure: Throwable) {
            val state = call(activity, "state", mapOf("viewId" to id)) as? Map<*, *>
            val fields = listOf("title", "progress", "isLoading", "error", "hasRenderer", "private", "engineNetworkBlocked")
                .associateWith { state?.get(it) }
            report("incomplete-$marker", fields.toString(), fixture.counts(marker))
            throw failure
        }
    }

    private fun assertReady(activity: GeckoPolicyProbeActivity) {
        val caps = call(activity, "capabilities") as? Map<*, *>
        android.util.Log.i("WingmanGeckoProbe", "readiness=" + call(activity, "state"))
        assertEquals("Native baseline, background sender, private permission and policy revision must acknowledge readiness", true, caps?.get("supported"))
        assertEquals(true, caps?.get("privateAvailable"))
        assertEquals(ProtectedWebBridge.ENGINE, caps?.get("engineVersion"))
    }

    private fun call(activity: GeckoPolicyProbeActivity, method: String, args: Map<String, Any?> = emptyMap()): Any? {
        val latch = CountDownLatch(1)
        var value: Any? = null
        var failure: Throwable? = null
        instrumentation.runOnMainSync {
            activity.invokeBridge(method, args) { result, error -> value = result; failure = error; latch.countDown() }
        }
        assertTrue("Native $method callback timed out", latch.await(30, TimeUnit.SECONDS))
        failure?.let { throw AssertionError("Actual native $method failed", it) }
        return value
    }

    private fun awaitTitle(activity: GeckoPolicyProbeActivity, id: Int, prefix: String): String {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(60)
        var lastTitle = ""
        var lastError: Any? = null
        while (System.nanoTime() < deadline) {
            val event = activity.nativeEvents.poll(500, TimeUnit.MILLISECONDS) ?: continue
            if (event.method != "pageState") continue
            val state = event.arguments as? Map<*, *> ?: continue
            if ((state["viewId"] as? Number)?.toInt() != id) continue
            lastTitle = state["title"] as? String ?: ""
            lastError = state["error"]
            if (lastTitle.startsWith(prefix)) return lastTitle
        }
        throw AssertionError("Native title did not finish controlled fixture; last title=$lastTitle; native error=$lastError")
    }

    private fun report(phase: String, title: String, counts: Map<String, Int>) {
        val summary = "phase=$phase engine=${ProtectedWebBridge.ENGINE} title=$title counts=$counts"
        Log.i("WingmanGeckoProbe", summary)
        instrumentation.sendStatus(0, Bundle().apply { putString("stream", "\n$summary\n") })
    }

    private class LoopbackFixture : Closeable {
        private val server = ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"))
        private val workers = Executors.newCachedThreadPool()
        private val requests = ConcurrentHashMap<String, AtomicInteger>()
        private val sockets = ConcurrentHashMap.newKeySet<Socket>()
        @Volatile private var closed = false
        private val base = "http://localhost:${server.localPort}"
        private val deniedBase = "http://127.0.0.1:${server.localPort}"
        // Generated 1x1 RGBA control with validated PNG chunk CRCs.
        private val png = Base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNg+M/wHwAEAQH/cetH5QAAAABJRU5ErkJggg==", Base64.DEFAULT)

        init {
            workers.execute {
                while (!closed) {
                    val socket = try { server.accept() } catch (_: Exception) { break }
                    sockets.add(socket)
                    try {
                        workers.execute { try { socket.use(::serve) } finally { sockets.remove(socket) } }
                    } catch (_: Exception) { sockets.remove(socket); socket.close() }
                }
            }
        }

        fun page(marker: String, worker: Boolean = false) = "$base/${if (worker) "worker-page" else "page"}?$marker"
        fun blockedHistory() = "$deniedBase/blocked-history"
        fun counts(marker: String): Map<String, Int> = listOf("page", "worker-page", "worker-script", "allowed", "redirect", "denied-direct", "denied-redirect")
            .associateWith { requests["$marker:$it"]?.get() ?: 0 }
        private fun hit(marker: String, key: String) { requests.computeIfAbsent("$marker:$key") { AtomicInteger() }.incrementAndGet() }

        private fun serve(socket: Socket) {
            try {
                socket.soTimeout = 5000
                val reader = socket.getInputStream().bufferedReader(Charsets.US_ASCII)
                val line = reader.readLine() ?: return
                val parts = line.split(' ')
                if (parts.size < 2) return
                var bytesRead = line.length
                while (true) {
                    val header = reader.readLine() ?: return
                    bytesRead += header.length
                    if (bytesRead > 16384) return
                    if (header.isEmpty()) break
                }
                val uri = URI(parts[1])
                val marker = uri.rawQuery.orEmpty()
                if (!marker.matches(Regex("[a-z0-9-]{1,80}"))) { respond(socket, 404, "text/plain", byteArrayOf()); return }
                when (uri.path) {
                    "/page" -> {
                        hit(marker, "page")
                        val titleMarker = if ((requests["$marker:page"]?.get() ?: 0) > 1) "reload-$marker" else marker
                        respond(socket, 200, "text/html; charset=utf-8", imagePage(marker, titleMarker).toByteArray())
                    }
                    "/worker-page" -> { hit(marker, "worker-page"); respond(socket, 200, "text/html; charset=utf-8", workerPage(marker).toByteArray()) }
                    "/worker.js" -> { hit(marker, "worker-script"); respond(socket, 200, "application/javascript", workerScript(marker).toByteArray()) }
                    "/allowed.png" -> { hit(marker, "allowed"); respond(socket, 200, "image/png", png) }
                    "/redirect" -> { hit(marker, "redirect"); respond(socket, 302, "text/plain", byteArrayOf(), "Location: $deniedBase/denied-redirect?$marker\r\n") }
                    "/denied-direct", "/denied-redirect" -> { hit(marker, uri.path.removePrefix("/")); respond(socket, 200, "image/png", png) }
                    else -> respond(socket, 404, "text/plain", byteArrayOf())
                }
            } catch (_: Exception) { /* Network cancellation is an expected negative observation. */ }
        }

        private fun respond(socket: Socket, code: Int, type: String, body: ByteArray, extra: String = "") {
            val reason = when (code) { 200 -> "OK"; 302 -> "Found"; else -> "Not Found" }
            val header = "HTTP/1.1 $code $reason\r\nContent-Type: $type\r\nContent-Length: ${body.size}\r\nCache-Control: no-store\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n$extra\r\n"
            socket.getOutputStream().apply { write(header.toByteArray(Charsets.US_ASCII)); write(body); flush() }
        }

        private fun targets(marker: String) = "{allowed:'$base/allowed.png?$marker',direct:'$deniedBase/denied-direct?$marker',redirect:'$base/redirect?$marker'}"
        private fun imagePage(marker: String, titleMarker: String) = """
            <!doctype html><html><head><meta charset="utf-8"><title>Controlled Gecko resource fixture</title></head>
            <body><h1>Test-owned image request fixture</h1><script>
            const results = {}, urls = ${targets(marker)};
            function record(key, value) { results[key] = value; if (Object.keys(results).length === 3)
              document.title = 'PROBE-$titleMarker:allowed=' + results.allowed + ';direct=' + results.direct + ';redirect=' + results.redirect; }
            for (const [key, url] of Object.entries(urls)) { const img = new Image();
              img.onload = () => record(key, 'load'); img.onerror = () => record(key, 'error');
              document.body.appendChild(img); img.src = url; }
            </script></body></html>
        """.trimIndent()

        private fun workerPage(marker: String) = """
            <!doctype html><html><head><meta charset="utf-8"><title>Controlled Gecko worker fixture</title></head>
            <body><h1>Test-owned service worker request fixture</h1><script>
            if (!('serviceWorker' in navigator)) {
              document.title = 'PROBE-$marker:worker-unavailable';
            } else {
            navigator.serviceWorker.addEventListener('message', event => {
              if (event.data && event.data.marker === '$marker') {
                const r = event.data.results;
                document.title = 'PROBE-$marker:allowed=' + r.allowed + ';direct=' + r.direct + ';redirect=' + r.redirect;
                navigator.serviceWorker.getRegistrations().then(all => Promise.all(all.map(reg => reg.unregister())));
              }
            });
            navigator.serviceWorker.register('/worker.js?$marker', {scope:'/'}).then(reg => {
              const worker = reg.installing || reg.waiting || reg.active;
              if (!worker) throw Error('worker absent');
              const start = () => { if (worker.state === 'activated') worker.postMessage({marker:'$marker'}); };
              if (worker.state === 'activated') start(); else worker.addEventListener('statechange', start);
            }).catch(() => { document.title = 'PROBE-$marker:worker-registration-error'; });
            }
            </script></body></html>
        """.trimIndent()

        private fun workerScript(marker: String) = """
            self.addEventListener('install', event => event.waitUntil(self.skipWaiting()));
            self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
            self.addEventListener('message', event => {
              if (!event.data || event.data.marker !== '$marker') return;
              event.waitUntil((async () => {
                const results = {}, urls = ${targets(marker)};
                await Promise.all(Object.entries(urls).map(async ([key, url]) => {
                  try { const response = await fetch(url, {cache:'no-store'}); await response.arrayBuffer();
                    results[key] = response.ok ? 'load' : 'http-error'; } catch (_) { results[key] = 'error'; }
                }));
                event.source.postMessage({marker:'$marker', results});
              })());
            });
        """.trimIndent()

        override fun close() {
            closed = true
            server.close()
            sockets.forEach { runCatching { it.close() } }
            sockets.clear()
            workers.shutdownNow()
        }
    }
}
