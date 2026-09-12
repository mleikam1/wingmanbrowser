#!/usr/bin/env python3
"""Loopback-only synthetic acceptance fixtures, never shipped as app runtime.

Android emulator: adb -s DEVICE reverse tcp:8810 tcp:8810
Browse http://127.0.0.1:8810 in the ordinary application. HTTP uses the same
mandatory destination policy; these fixtures never disable HTTPS validation.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from html import escape
from urllib.parse import urlsplit, parse_qs

STYLE = '<meta name="viewport" content="width=device-width,initial-scale=1"><style>body{font:18px system-ui;margin:20px;line-height:1.5}button,a,input{margin:12px 0;padding:10px;display:block}button{font:inherit}nav{display:flex;gap:12px;flex-wrap:wrap}nav a{padding:3px}</style>'
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def page(self, title, body, cookie=None):
        data = f'<!doctype html><html><head><title>{escape(title)}</title>{STYLE}</head><body><nav><a href="/">Home</a><a href="/session">Session</a><a href="/files">Files</a><a href="/security">Security</a></nav><h1>{escape(title)}</h1>{body}</body></html>'.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(data)))
        if cookie: self.send_header('Set-Cookie', cookie)
        self.end_headers(); self.wfile.write(data)

    def do_GET(self):
        path = urlsplit(self.path).path
        if path in ('/redirect', '/redirect-blocked', '/redirect-download-blocked'):
            self.send_response(302)
            self.send_header('Location', '/second' if path == '/redirect' else 'https://gambling.protection.test/')
            self.end_headers(); return
        if path == '/download':
            payload = b'Wingman synthetic download fixture. No private data.\n'
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.send_header('Content-Disposition', 'attachment; filename="wingman-test.txt"')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers(); self.wfile.write(payload); return
        if path == '/media':
            self.page('Synthetic media fixture', '<p id="status">Playback waiting</p><canvas id="canvas" width="320" height="180" hidden></canvas><video id="video" controls muted playsinline style="width:100%"></video><button id="play">Play generated video</button><button id="full">Fullscreen video</button><script>const c=document.getElementById("canvas"),v=document.getElementById("video"),ctx=c.getContext("2d");let n=0;setInterval(()=>{ctx.fillStyle=n%2?"#1466ac":"#397764";ctx.fillRect(0,0,320,180);ctx.fillStyle="white";ctx.font="24px sans-serif";ctx.fillText("Synthetic frame "+n++,30,90)},250);document.getElementById("play").onclick=async()=>{try{v.srcObject=c.captureStream(4);await v.play();document.getElementById("status").textContent="Playback started"}catch(e){document.getElementById("status").textContent="Playback unavailable"}};document.getElementById("full").onclick=()=>v.requestFullscreen()</script>'); return
        if path == '/session':
            signed = 'wingman_fixture=synthetic-user' in self.headers.get('Cookie', '')
            self.page('Session fixture', f'<p id="session">Server session: {"signed in as synthetic-user" if signed else "signed out"}</p><p id="storage">Storage: checking</p><script>document.getElementById("storage").textContent="Storage: "+(localStorage.getItem("fixture")||"empty")</script><form action="/login" method="post"><label>Fixture username<input name="username" value="synthetic-user"></label><button>Sign in fixture</button></form><button onclick="localStorage.setItem(\'fixture\',\'saved\');document.getElementById(\'storage\').textContent=\'Storage: saved\'">Save storage marker</button><a href="/session">Refresh session</a>'); return
        if path == '/files':
            self.page('File fixtures', '<a href="/download">Download harmless text file</a><form action="/upload" method="post" enctype="multipart/form-data"><label>Generated test file<input name="fixture" type="file"></label><button>Upload generated file</button></form>'); return
        if path == '/security':
            self.page('Security fixtures', '<a href="/redirect">Permitted redirect</a><a href="/redirect-blocked">Blocked-category redirect</a><a href="https://gambling.protection.test/" target="_blank">Blocked-category new window</a><a href="/second" target="_blank">Permitted new window</a><a href="https://expired.badssl.com/">Invalid TLS (must block)</a><a href="https://mixed.protection.test/promotion/alcohol">Synthetic alcohol path block</a>'); return
        if path == '/second':
            self.page('Second fixture page', '<p>Ordinary navigation completed.</p><a href="/third">Continue to third page</a>'); return
        if path == '/third':
            self.page('Third fixture page', '<p>Use browser Back and Forward to traverse real page history.</p>'); return
        if path == '/form':
            value = escape(parse_qs(urlsplit(self.path).query).get('q', [''])[0])
            self.page('Form submitted', f'<p>Site search received: {value}</p>'); return
        self.page('Wingman browser fixture', '<p id="js">JavaScript waiting</p><button onclick="document.getElementById(\'js\').textContent=\'JavaScript worked\'">Run JavaScript</button><form action="/form" method="get"><label>Site search<input name="q" value="neutral fixture query"></label><button>Submit site search</button></form><a href="/second">Second page</a><a href="/session">Login and storage fixture</a><a href="/files">Upload and download fixtures</a><a href="/security">Redirect and new-window fixtures</a>')

    def do_POST(self):
        try: length = int(self.headers.get('Content-Length', '0'))
        except ValueError: self.send_error(400); return
        if not 0 <= length <= 1048576: self.send_error(413); return
        self.rfile.read(length)  # Discard synthetic input. Never log or persist request bodies.
        if urlsplit(self.path).path == '/login':
            self.send_response(303)
            self.send_header('Set-Cookie', 'wingman_fixture=synthetic-user; HttpOnly; SameSite=Lax; Path=/; Max-Age=86400')
            self.send_header('Location', '/session'); self.end_headers(); return
        self.page('Upload received', f'<p>{length} request bytes received and discarded.</p><a href="/files">Return to file fixtures</a>')

if __name__ == '__main__':
    print('Wingman synthetic fixtures: http://127.0.0.1:8810 (loopback only)', flush=True)
    ThreadingHTTPServer(('127.0.0.1', 8810), Handler).serve_forever()
