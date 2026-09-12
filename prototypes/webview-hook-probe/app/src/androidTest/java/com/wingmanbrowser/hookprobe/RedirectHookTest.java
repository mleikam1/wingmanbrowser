package com.wingmanbrowser.hookprobe;

import android.content.Intent;
import android.test.InstrumentationTestCase;
import android.webkit.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Isolated API probe, never the consumer application or its category data. */
public final class RedirectHookTest extends InstrumentationTestCase {
 public void testDirectDenyButRedirectHopEscapesCallback() throws Exception {
  ServerSocket server = new ServerSocket(0, 8, InetAddress.getByName("127.0.0.1"));
  ConcurrentHashMap<String,AtomicInteger> requests = new ConcurrentHashMap<>();
  AtomicBoolean running = new AtomicBoolean(true);
  Thread worker = new Thread(() -> {
   while (running.get()) try (Socket socket = server.accept()) {
    socket.setSoTimeout(3000);
    BufferedReader reader = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.US_ASCII));
    String line = reader.readLine(); if (line == null) continue;
    String path = line.split(" ")[1]; while ((line=reader.readLine()) != null && !line.isEmpty()) {}
    requests.computeIfAbsent(path,k->new AtomicInteger()).incrementAndGet();
    byte[] body; String headers;
    if (path.equals("/redirect.png")) { body=new byte[0]; headers="HTTP/1.1 302 Found\r\nLocation: /denied.png\r\n"; }
    else if (path.equals("/denied.png")) { body=android.util.Base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j4z8AAAAASUVORK5CYII=",0); headers="HTTP/1.1 200 OK\r\nContent-Type: image/png\r\n"; }
    else { String src=path.equals("/direct")?"/denied.png":"/redirect.png"; body=("<!doctype html><title>pending</title><p>Owned neutral image policy probe</p><img src='"+src+"' onload=\"document.title='loaded'\" onerror=\"document.title='denied'\">").getBytes(StandardCharsets.UTF_8); headers="HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n"; }
    socket.getOutputStream().write((headers+"Cache-Control: no-store\r\nConnection: close\r\nContent-Length: "+body.length+"\r\n\r\n").getBytes(StandardCharsets.US_ASCII)); socket.getOutputStream().write(body);
   } catch (Exception error) { if (running.get()) throw new RuntimeException(error); }
  },"owned-loopback-fixture"); worker.start();
  ProbeActivity activity = (ProbeActivity)getInstrumentation().startActivitySync(new Intent(getInstrumentation().getTargetContext(),ProbeActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
  AtomicInteger deniedCallbacks=new AtomicInteger();
  getInstrumentation().runOnMainSync(() -> activity.web.setWebViewClient(new WebViewClient() {
   @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
    if (request.getUrl().getPath().equals("/denied.png")) { deniedCallbacks.incrementAndGet(); return new WebResourceResponse("text/plain","UTF-8",403,"Blocked",java.util.Collections.singletonMap("Cache-Control","no-store"),new ByteArrayInputStream(new byte[0])); }
    return null;
   }
   @Override public boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) { return true; }
  }));
  try {
   load(activity,"http://127.0.0.1:"+server.getLocalPort()+"/direct");
   assertEquals("denied",waitTitle(activity,"denied")); assertEquals(1,deniedCallbacks.get()); assertFalse(requests.containsKey("/denied.png"));
   load(activity,"http://127.0.0.1:"+server.getLocalPort()+"/redirected");
   assertEquals("loaded",waitTitle(activity,"loaded")); assertEquals(1,deniedCallbacks.get()); assertEquals(1,requests.get("/redirect.png").get()); assertEquals(1,requests.get("/denied.png").get());
   android.util.Log.i("WingmanHookProbe","CONFIRMED directDenied=1 directTargetRequests=0 redirectedDeniedCallback=0 redirectedTargetRequests=1 imageLoaded=true");
  } finally { getInstrumentation().runOnMainSync(activity::finish); running.set(false); server.close(); worker.join(5000); }
 }
 private void load(ProbeActivity activity,String url) { getInstrumentation().runOnMainSync(()->activity.web.loadUrl(url)); }
 private String waitTitle(ProbeActivity activity,String expected) throws Exception {
  AtomicReference<String> title = new AtomicReference<>();
  for (int i=0;i<200;i++) { getInstrumentation().runOnMainSync(()->title.set(activity.web.getTitle())); if (expected.equals(title.get())) return title.get(); Thread.sleep(50); }
  fail("Owned fixture did not finish: "+title.get()); return "timeout";
 }
}
