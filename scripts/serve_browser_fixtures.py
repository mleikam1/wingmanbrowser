#!/usr/bin/env python3
"""Local-only manual browser fixtures. Never part of Wingman's runtime.

Run: python3 scripts/serve_browser_fixtures.py
For Android: adb -s DEVICE reverse tcp:8810 tcp:8810
Then browse http://127.0.0.1:8810 in Wingman. Upload only generated test data.
"""
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass  # Do not log URLs, uploads or request headers.

    def do_GET(self):
        if self.path == '/download':
            payload = b'Wingman local download fixture. This file contains no private data.\n'
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', 'attachment; filename="wingman-test.txt"')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        self.send_response(503 if self.path == '/failure' else 200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(b'''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Wingman local test</title><style>body{font:18px system-ui;margin:24px;line-height:1.6}button,a,input{margin:12px 0;padding:12px;display:block}button{font:inherit}</style></head><body>
<h1>Wingman browser fixture</h1>
<p>Local development only. Use generated test files.</p>
<a href="/second">Navigate to another page</a>
<a href="/popup" target="_blank">Open a new window</a>
<a href="/download">Download a harmless text file</a>
<form action="/upload" method="post" enctype="multipart/form-data"><label>Choose a generated image<input name="fixture" type="file" accept="image/*"></label><button>Upload to this local test server</button></form>
<button onclick="alert('The browser shows this website message with its origin.')">Show JavaScript dialog</button>
<button onclick="confirm('Confirm this harmless test?')">Show confirm dialog</button>
<a href="/failure">Show HTTP 503 error</a>
<a href="https://expired.badssl.com/">Test invalid TLS certificate (must block)</a>
</body></html>''')

    def do_POST(self):
        try:
            length = int(self.headers.get('Content-Length', '0'))
        except ValueError:
            self.send_error(400)
            return
        if length < 0 or length > 1048576:
            self.send_error(413)
            return
        self.rfile.read(length)  # Consume then discard; never save upload content.
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(f'<title>Wingman upload received</title><h1>Upload received</h1><p>{length} request bytes received and discarded.</p><a href="/">Return to fixtures</a>'.encode())

if __name__ == '__main__':
    print('Wingman fixtures: http://127.0.0.1:8810 (loopback only)')
    HTTPServer(('127.0.0.1', 8810), Handler).serve_forever()
