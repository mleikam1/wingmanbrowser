#!/usr/bin/env python3
"""Loopback-only synthetic acceptance fixtures, never shipped as app runtime.

Android emulator: adb -s DEVICE reverse tcp:8810 tcp:8810
Browse http://127.0.0.1:8810 in the ordinary application. HTTP uses the same
mandatory destination policy; these fixtures never disable HTTPS validation.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from html import escape
from urllib.parse import urlsplit, parse_qs

STYLE = '<meta name="viewport" content="width=device-width,initial-scale=1"><style>body{font:18px system-ui;margin:20px;line-height:1.5}button,a,input{margin:12px 0;padding:10px;display:block}button{font:inherit}nav{display:flex;gap:12px;flex-wrap:wrap}nav a{padding:3px}</style>'
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def page(self, title, body, cookie=None):
        data = f'<!doctype html><html><head><title>{escape(title)}</title>{STYLE}</head><body><nav><a href="/">Home</a><a href="/session">Session</a><a href="/files">Files</a><a href="/security">Security</a><a href="/media">Media</a><a href="/readiness">Readiness</a></nav><h1>{escape(title)}</h1>{body}</body></html>'.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(data)))
        if cookie: self.send_header('Set-Cookie', cookie)
        self.end_headers(); self.wfile.write(data)

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == '/popup':
            self.page('Synthetic popup continuity', '<p id="result">Waiting for child message</p><button onclick="window.open(\'/popup-child\',\'readiness-child\')">Open synthetic child</button><form action="/popup-post" method="post" target="readiness-post"><input name="marker" value="synthetic-popup-post"><button>Open POST child</button></form><script>addEventListener("message",e=>{if(e.origin===location.origin&&e.data===\'synthetic-child-ready\')document.getElementById("result").textContent=\'Child opener message received\'})</script>'); return
        if path == '/popup-child':
            self.page('Synthetic child', '<p id="result"></p><script>const ok=!!window.opener;document.getElementById("result").textContent=ok?\'Opener retained\':\'Opener missing\';if(ok)window.opener.postMessage(\'synthetic-child-ready\',location.origin)</script><button onclick="window.close()">Close this child</button>'); return
        if path == '/popup-post':
            self.page('Popup method changed', '<p>Expected a POST request. A browser integration replaced it with GET.</p>'); return
        if path == '/readiness':
            self.page('Synthetic readiness checks', '<p>Generated test data only. This page is not Wingman news or a substitute application.</p><p id="agent"></p><script>document.getElementById("agent").textContent=navigator.userAgent</script><label>Editable selection<textarea id="selection">Select this synthetic sentence and refine it.</textarea></label><a href="/resource-checks">Resource redirect diagnostic (test-policy setup required)</a><a href="/scroll">Touch and keyboard scrolling</a><a href="/category-checks">Six categories and path spelling checks</a><a href="/session">Controlled normal/private login and storage</a><a href="https://httpbingo.org/basic-auth/wingman/test-only">HTTPS Basic authentication: wingman / test-only</a><a href="/auth-http">HTTP authentication must not offer credentials</a><a href="/download-auth-start">Download with cookies and user agent through redirect</a><a href="/picker-race">File picker followed by page navigation</a><a href="https://webrtc.github.io/samples/src/content/getusermedia/gum/">Origin-named camera permission (deny)</a>'); return
        if path == '/resource-redirect':
            self.send_response(302)
            self.send_header('Location', 'https://httpbingo.org/image/png?readiness=redirect-hop')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', '0')
            self.end_headers(); return
        if path == '/resource-checks':
            self.page('Redirect resource check', '<p>Requires an automated test policy that blocks httpbingo.org. The consumer UI cannot configure this prerequisite; without it, this neutral fixture tests redirect connectivity only.</p><p id="status">Image not requested</p><img id="image" alt="Redirect result" style="max-width:220px"><button onclick="const i=document.getElementById(\'image\');i.onload=()=>document.getElementById(\'status\').textContent=\'Redirected image loaded\';i.onerror=()=>document.getElementById(\'status\').textContent=\'Redirected image unavailable\';i.src=\'/resource-redirect?run=\'+Date.now()">Load redirected image</button><a href="https://httpbingo.org/html">Top-level comparison (blocked only with test policy)</a>'); return
        if path == '/category-checks':
            domains = [('Sexual explicit', 'sexual-explicit'), ('Gambling', 'gambling'), ('Alcohol promotion', 'alcohol'), ('Recreational drugs', 'drugs'), ('Tobacco/nicotine', 'tobacco'), ('Known threat', 'security-threat')]
            links = ''.join(f'<a href="https://{host}.protection.test/">{label} synthetic block</a>' for label,host in domains)
            paths = ['/promotion/alcohol', '/promotion//alcohol', '//promotion/alcohol', '/promotion/%61lcohol', '/promotion/./alcohol']
            links += ''.join(f'<a href="https://mixed.protection.test{path}">Path spelling: {escape(path)}</a>' for path in paths)
            self.page('Synthetic policy checks', '<style>nav{display:none}body{font-size:15px;margin:12px}h1{font-size:22px}a{margin:4px 0;padding:4px}</style><p>Reserved .test destinations. Each must be blocked before network use by the installed baseline, with no live prohibited content.</p>'+links); return
        if path == '/scroll':
            sections = ''.join(f'<section style="height:360px;border-bottom:1px solid #abc"><h2>Scroll marker {i}</h2><p>Generated neutral text for touch, selection and keyboard testing.</p></section>' for i in range(1,7))
            self.page('Synthetic scrolling', '<p id="position">Scroll position: 0</p><script>addEventListener("scroll",()=>document.getElementById("position").textContent="Scroll position: "+Math.round(scrollY))</script>'+sections); return
        if path == '/auth-http':
            self.send_response(401)
            self.send_header('WWW-Authenticate', 'Basic realm="Synthetic HTTP - do not send credentials"')
            self.send_header('Content-Length', '0')
            self.end_headers(); return
        if path in ('/download-auth-start', '/download-auth-final'):
            cookies = self.headers.get('Cookie', '')
            agent = self.headers.get('User-Agent', '')
            signed = 'wingman_readiness=synthetic-user' in cookies
            expected_agent = 'Mozilla/' in agent and 'AppleWebKit/' in agent
            if not signed or not expected_agent:
                self.page('Download precondition failed', f'<p>Synthetic session present: {signed}; browser user agent retained: {expected_agent}</p><a href="/session">Sign in with the synthetic fixture first</a>'); return
            if path == '/download-auth-start':
                self.send_response(302)
                self.send_header('Set-Cookie', 'wingman_download_stage=ready; HttpOnly; SameSite=Lax; Path=/; Max-Age=300')
                self.send_header('Location', '/download-auth-final')
                self.send_header('Content-Length', '0')
                self.end_headers(); return
            if 'wingman_download_stage=ready' not in cookies:
                self.page('Download redirect cookie missing', '<p>The downloader did not retain the same-origin redirect cookie.</p>'); return
            payload = b'Wingman readiness: synthetic authenticated redirect download.\n'
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.send_header('Content-Disposition', 'attachment; filename="wingman-readiness-auth.txt"')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers(); self.wfile.write(payload); return
        if path == '/picker-race':
            self.page('Picker ownership fixture', '<p>Opening this chooser schedules a same-origin navigation after five seconds. A stale selection must not be delivered to the new page.</p><input type="file" onclick="setTimeout(()=>location.href=\'/second\',5000)"><p>No selected file is uploaded by this page.</p>'); return
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
            self.page('Synthetic media fixture', '<style>nav{display:none}body{margin:12px}h1{font-size:22px;margin:0}button{margin:6px 0;padding:8px}</style><p id="status">Playback waiting</p><canvas id="canvas" width="320" height="180" hidden></canvas><video id="video" controls muted playsinline style="width:100%"></video><button id="play">Play generated video</button><button id="full">Fullscreen video</button><script>const c=document.getElementById("canvas"),v=document.getElementById("video"),ctx=c.getContext("2d");let n=0;setInterval(()=>{ctx.fillStyle=n%2?"#1466ac":"#397764";ctx.fillRect(0,0,320,180);ctx.fillStyle="white";ctx.font="24px sans-serif";ctx.fillText("Synthetic frame "+n++,30,90)},250);document.getElementById("play").onclick=async()=>{try{v.srcObject=c.captureStream(4);await v.play();document.getElementById("status").textContent="Playback started"}catch(e){document.getElementById("status").textContent="Playback unavailable"}};document.getElementById("full").onclick=()=>v.requestFullscreen()</script>'); return
        if path == '/session':
            signed = 'wingman_readiness=synthetic-user' in self.headers.get('Cookie', '')
            self.page('Session fixture', f'<p id="session">Server session: {"signed in as synthetic-user" if signed else "signed out"}</p><p id="storage">Storage: checking</p><script>document.getElementById("storage").textContent="Storage: "+(localStorage.getItem("readiness-2026-09-12")||"empty")</script><form action="/login" method="post"><label>Fixture username<input name="username" value="synthetic-user"></label><button>Sign in fixture</button></form><button onclick="localStorage.setItem(\'readiness-2026-09-12\',\'saved\');document.getElementById(\'storage\').textContent=\'Storage: saved\'">Save storage marker</button><a href="/session">Refresh session</a>'); return
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
        if urlsplit(self.path).path == '/popup-post':
            self.page('Popup POST retained', '<p>Synthetic form POST reached the child destination.</p><script>if(window.opener)window.opener.postMessage(\'synthetic-child-ready\',location.origin)</script>'); return
        if urlsplit(self.path).path == '/login':
            self.send_response(303)
            self.send_header('Set-Cookie', 'wingman_readiness=synthetic-user; HttpOnly; SameSite=Lax; Path=/; Max-Age=86400')
            self.send_header('Location', '/session'); self.end_headers(); return
        self.page('Upload received', f'<p>{length} request bytes received and discarded.</p><a href="/files">Return to file fixtures</a>')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8810)
    args = parser.parse_args()
    print(f'Wingman synthetic fixtures: http://127.0.0.1:{args.port} (loopback only)', flush=True)
    ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
