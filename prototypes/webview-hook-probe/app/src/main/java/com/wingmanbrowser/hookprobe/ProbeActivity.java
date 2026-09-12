package com.wingmanbrowser.hookprobe;
public final class ProbeActivity extends android.app.Activity {
 public android.webkit.WebView web;
 @Override public void onCreate(android.os.Bundle state) { super.onCreate(state); getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE); web = new android.webkit.WebView(this); android.webkit.WebView.setWebContentsDebuggingEnabled(false); web.getSettings().setJavaScriptEnabled(true); web.getSettings().setAllowFileAccess(false); web.getSettings().setAllowContentAccess(false); setContentView(web); }
 @Override protected void onDestroy() { web.destroy(); super.onDestroy(); }
}
