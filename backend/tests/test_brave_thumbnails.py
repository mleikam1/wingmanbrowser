"""Synthetic thumbnail fixtures only: no Brave/media/merchant network requests."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import http.client
import io
import json
import threading
import unittest
from unittest.mock import Mock

from PIL import Image, PngImagePlugin
from wingman_content.fetch import FetchResult
from wingman_search.contracts import SearchError, SearchRequest, parse_results
from wingman_search.gateway import LocalServer, SearchApplication, handler_for
from wingman_search.policy import SearchPolicy
from wingman_search.provider import BraveProvider, FixtureProvider
from wingman_search.thumbnails import (CDN_HOST, FIXTURE_SOURCE, MAX_PNG_BYTES, MAX_TOKENS,
    MAX_WIRE_BYTES, RELEASE_PATH, THUMBNAIL_PATH, ThumbnailService, ThumbnailTransport,
    checked_thumbnail_url, sanitize_png)


def png(size=(96, 64), *, metadata=False):
    output = io.BytesIO()
    text = PngImagePlugin.PngInfo()
    text.add_text('comment', 'synthetic metadata must disappear')
    Image.new('RGB', size, '#345678').save(output, 'PNG', pnginfo=text if metadata else None)
    return output.getvalue()


def news(src=FIXTURE_SOURCE, **changes):
    row = dict(title='Space science', url='https://www.nasa.gov/news/', description='Science research update',
               thumbnail={'src': src})
    row.update(changes)
    return row


class Timer:
    def __init__(self, seconds, callback):
        self.seconds, self.callback = seconds, callback
        self.started, self.cancelled = False, False
    def start(self): self.started = True
    def cancel(self): self.cancelled = True


class ThumbnailTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 9, 26, tzinfo=timezone.utc).timestamp()
        self.services = []
        self.timers = []

    def tearDown(self):
        for service in self.services:
            service.close()

    def service(self, **kwargs):
        def timer(seconds, callback):
            value = Timer(seconds, callback)
            self.timers.append(value)
            return value
        kwargs.setdefault('clock', lambda: self.now)
        kwargs.setdefault('monotonic', lambda: self.now)
        service = ThumbnailService(timer_factory=timer, **kwargs)
        self.services.append(service)
        return service

    def test_only_exact_https_brave_thumbnail_host_is_accepted(self):
        self.assertEqual(FIXTURE_SOURCE, checked_thumbnail_url(FIXTURE_SOURCE))
        for value in (None, {}, 1, 'http://' + CDN_HOST + '/a', 'https://images.search.brave.com/a',
                      'https://' + CDN_HOST + '.evil.example/a', 'https://127.0.0.1/a',
                      'https://publisher.example/a', 'https://x@' + CDN_HOST + '/a',
                      'https://' + CDN_HOST + ':444/a', 'https://' + CDN_HOST + '/a#fragment',
                      'https://' + CDN_HOST + '/%252e%252e/a', 'https://' + CDN_HOST + '/%0d%0a',
                      'https://' + CDN_HOST + '/a?x=%0d%0a', 'https://' + CDN_HOST + '//a'):
            with self.subTest(value=value):
                self.assertIsNone(checked_thumbnail_url(value))

    def test_static_raster_is_reencoded_bounded_and_metadata_stripped(self):
        result = sanitize_png(png((1024, 768), metadata=True), 'image/png')
        self.assertLessEqual(len(result), MAX_PNG_BYTES)
        self.assertNotIn(b'synthetic metadata', result)
        with Image.open(io.BytesIO(result)) as image:
            self.assertEqual(image.format, 'PNG')
            self.assertEqual(image.mode, 'RGB')
            self.assertLessEqual(image.width, 256)
            self.assertLessEqual(image.height, 144)
            self.assertFalse(image.info)
        for format_, mime in (('JPEG', 'image/jpeg'), ('WEBP', 'image/webp')):
            out = io.BytesIO()
            Image.new('RGB', (80, 80)).save(out, format_)
            self.assertTrue(sanitize_png(out.getvalue(), mime).startswith(b'\x89PNG'))

    def test_rejects_svg_malformed_animated_large_dimensions_and_wire(self):
        animated = io.BytesIO()
        Image.new('RGB', (32, 32), 'red').save(animated, 'PNG', save_all=True,
            append_images=[Image.new('RGB', (32, 32), 'blue')])
        for data, mime in ((b'<svg/>', 'image/svg+xml'), (b'not raster', 'image/png'),
                (png(), 'image/jpeg'), (png((4096, 16)), 'image/png'),
                (png((1, 1)), 'image/png'), (animated.getvalue(), 'image/png'),
                (b'x' * (MAX_WIRE_BYTES + 1), 'image/png')):
            with self.subTest(mime=mime, size=len(data)), self.assertRaises(Exception):
                sanitize_png(data, mime)

    def test_extreme_aspect_ratios_preserve_client_minimum_dimensions(self):
        for size in ((2048, 16), (16, 2048)):
            with self.subTest(size=size):
                result = sanitize_png(png(size), 'image/png')
                with Image.open(io.BytesIO(result)) as image:
                    self.assertGreaterEqual(min(image.size), 16)
                    self.assertLessEqual(image.width, 256)
                    self.assertLessEqual(image.height, 144)
                    self.assertFalse(image.info)

    def test_one_fetch_consumes_url_and_keeps_no_server_bytes(self):
        transport = Mock(fetch=Mock(return_value=(png(), 'image/png')))
        service = self.service(transport=transport)
        grant = service.register(FIXTURE_SOURCE)
        self.assertEqual(set(grant), {'token', 'expiresAt'})
        self.assertRegex(grant['token'], r'^[a-f0-9]{64}$')
        self.assertNotIn(CDN_HOST, json.dumps(grant))
        body, mime = service.fetch({'token': grant['token']})
        self.assertEqual(mime, 'image/png')
        self.assertLessEqual(len(body), MAX_PNG_BYTES)
        self.assertIsNone(service._entries[grant['token']].source)
        self.assertFalse(any(isinstance(value, bytes) for value in vars(service._entries[grant['token']]).values()))
        with self.assertRaises(SearchError):
            service.fetch({'token': grant['token']})
        self.assertEqual(transport.fetch.call_count, 1)
        self.assertEqual(service.snapshot()['upstream_attempts'], 1)

    def test_failure_cannot_retry_and_forged_token_never_fetches(self):
        transport = Mock(fetch=Mock(side_effect=ValueError('URL query secret must not escape')))
        service = self.service(transport=transport)
        token = service.register(FIXTURE_SOURCE)['token']
        for raw in ({'token': '0' * 64}, {'token': token, 'url': FIXTURE_SOURCE}, {'token': token}, {'token': token}):
            with self.assertRaises(SearchError) as exc:
                service.fetch(raw)
            self.assertEqual(exc.exception.code, 'thumbnail-unavailable')
            self.assertNotIn('secret', str(exc.exception))
        self.assertEqual(transport.fetch.call_count, 1)
        self.assertIsNone(service._entries[token].source)

    def test_cap_absolute_expiry_physical_timer_release_and_close(self):
        service = self.service(fixture=True)
        tokens = [service.register(FIXTURE_SOURCE)['token'] for _ in range(MAX_TOKENS)]
        self.assertIsNone(service.register(FIXTURE_SOURCE))
        self.assertEqual(self.timers[0].seconds, 300)
        self.assertTrue(self.timers[0].started)
        service.release({'tokens': tokens[:50]})
        self.assertEqual(service.snapshot()['active_tokens'], MAX_TOKENS - 50)
        with self.assertRaises(SearchError):
            service.fetch({'token': tokens[0]})
        with self.assertRaises(SearchError):
            service.release({'tokens': tokens[:51]})
        with self.assertRaises(SearchError):
            service.release({'tokens': ['bad'], 'url': FIXTURE_SOURCE})
        self.now += 300
        self.timers[0].callback()  # Physical deletion without another request.
        self.assertFalse(service._entries)
        self.assertEqual(service.snapshot()['expired'], MAX_TOKENS - 50)
        service.close()
        self.assertIsNone(service.register(FIXTURE_SOURCE))

    def test_wall_clock_rollback_cannot_extend_monotonic_expiry(self):
        elapsed = [10.0]
        service = self.service(fixture=True, monotonic=lambda: elapsed[0])
        token = service.register(FIXTURE_SOURCE)['token']
        self.now -= 24 * 60 * 60
        elapsed[0] += 300
        self.timers[0].callback()
        self.assertFalse(service._entries)
        self.assertEqual(service.snapshot()['expired'], 1)
        with self.assertRaises(SearchError):
            service.fetch({'token': token})
        self.assertEqual(service.snapshot()['upstream_attempts'], 0)

    def test_concurrent_requests_fetch_same_token_only_once_and_release_drops_late_image(self):
        started, finish = threading.Event(), threading.Event()
        def fetch(_):
            started.set()
            self.assertTrue(finish.wait(3))
            return png(), 'image/png'
        service = self.service(transport=Mock(fetch=Mock(side_effect=fetch)))
        token = service.register(FIXTURE_SOURCE)['token']
        with ThreadPoolExecutor(max_workers=2) as pool:
            future = pool.submit(service.fetch, {'token': token})
            self.assertTrue(started.wait(3))
            with self.assertRaises(SearchError):
                service.fetch({'token': token})
            service.release({'tokens': [token]})
            finish.set()
            with self.assertRaises(SearchError):
                future.result(timeout=3)
        self.assertEqual(service.transport.fetch.call_count, 1)
        self.assertFalse(service._entries)

    def test_two_fetch_concurrency_ceiling_consumes_excess_token_without_network(self):
        release = threading.Event()
        entered = 0
        lock = threading.Lock()
        ready = threading.Event()
        def fetch(_):
            nonlocal entered
            with lock:
                entered += 1
                if entered == 2: ready.set()
            self.assertTrue(release.wait(3))
            return png(), 'image/png'
        service = self.service(transport=Mock(fetch=Mock(side_effect=fetch)))
        tokens = [service.register(FIXTURE_SOURCE)['token'] for _ in range(3)]
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(service.fetch, {'token': token}) for token in tokens[:2]]
            self.assertTrue(ready.wait(3))
            with self.assertRaises(SearchError):
                service.fetch({'token': tokens[2]})
            release.set()
            for future in futures: future.result(timeout=3)
        self.assertEqual(service.transport.fetch.call_count, 2)
        with self.assertRaises(SearchError): service.fetch({'token': tokens[2]})

    def test_fixture_service_never_invokes_external_fetch(self):
        transport = Mock(fetch=Mock(side_effect=AssertionError('network must not run')))
        service = self.service(fixture=True, transport=transport)
        body, mime = service.fetch({'token': service.register(FIXTURE_SOURCE)['token']})
        self.assertTrue(body.startswith(b'\x89PNG'))
        self.assertEqual(mime, 'image/png')
        transport.fetch.assert_not_called()
        self.assertEqual(service.snapshot()['upstream_attempts'], 0)

    def test_only_normal_news_permitted_rows_register_after_complete_schema_validation(self):
        service = self.service(fixture=True)
        for kind, context in (('web', 'normal'), ('news', 'private')):
            raw = {'query': {}, **({'web': {'results': [news()]}} if kind == 'web' else {'results': [news()]})}
            dto, _ = parse_results(json.dumps(raw).encode(), SearchRequest('space', kind, context=context),
                                   SearchPolicy(), thumbnail_register=service.register)
            self.assertNotIn('thumbnail', dto['results'][0])
        dto, _ = parse_results(json.dumps({'results': [news(family_friendly=False), news(url='https://localhost/'),
            news()]}).encode(), SearchRequest('space', 'news'), SearchPolicy(), thumbnail_register=service.register)
        self.assertEqual(len(dto['results']), 1)
        self.assertIn('thumbnail', dto['results'][0])
        self.assertEqual(service.snapshot()['registered'], 1)
        with self.assertRaises(SearchError):
            parse_results(json.dumps({'results': [news(), {'invalid': True}]}).encode(), SearchRequest('space', 'news'),
                          SearchPolicy(), thumbnail_register=service.register)
        self.assertEqual(service.snapshot()['registered'], 1)

    def test_optional_metadata_failure_never_fails_organic_or_uses_original(self):
        service = self.service(fixture=True)
        for thumbnail in (None, 'bad', {'src': 'https://publisher.example/a', 'original': FIXTURE_SOURCE},
                          {'original': FIXTURE_SOURCE}, {'src': {}}):
            dto, _ = parse_results(json.dumps({'results': [news(thumbnail=thumbnail)]}).encode(),
                SearchRequest('space', 'news'), SearchPolicy(), thumbnail_register=service.register)
            self.assertEqual(dto['status'], 'ok')
            self.assertNotIn('thumbnail', dto['results'][0])
        dto, _ = parse_results(json.dumps({'results': [news()]}).encode(), SearchRequest('space', 'news'),
            SearchPolicy(), thumbnail_register=Mock(side_effect=ValueError('optional failure')))
        self.assertEqual(dto['status'], 'ok')
        self.assertNotIn('thumbnail', dto['results'][0])


class TransportTests(unittest.TestCase):
    def fake(self, *, status=200, headers=None, body=None, addresses=None):
        events = []
        data = png() if body is None else body
        class Response:
            def __init__(self): self.status, self.reader = status, io.BytesIO(data)
            def getheaders(self): return headers or [('Content-Type', 'image/png')]
            def read(self, maximum):
                events.append(('read', maximum))
                return self.reader.read(maximum)
        class Connection:
            sock = None
            def __init__(self, *args): events.append(('connect', args))
            def request(self, method, path, headers): events.append(('request', method, path, headers))
            def getresponse(self): return Response()
            def close(self): events.append(('close',))
        return ThumbnailTransport(resolver=lambda *_: addresses or ['8.8.8.8'], connector=Connection), events

    def test_fixed_host_get_and_allowlisted_headers_only(self):
        transport, events = self.fake()
        body, mime = transport.fetch(FIXTURE_SOURCE)
        self.assertEqual(body, png())
        self.assertEqual(mime, 'image/png')
        connect = next(row for row in events if row[0] == 'connect')
        self.assertEqual(connect[1][0:2], (CDN_HOST, '8.8.8.8'))
        request = next(row for row in events if row[0] == 'request')
        self.assertEqual(request[1], 'GET')
        self.assertEqual(set(request[3]), {'Accept', 'Accept-Encoding', 'User-Agent', 'Connection'})
        self.assertEqual(sum(row[0] == 'request' for row in events), 1)
        self.assertEqual(events[-1], ('close',))

    def test_private_dns_redirect_bad_type_oversize_and_ambiguous_headers_refused(self):
        cases = [dict(addresses=['127.0.0.1']), dict(status=302, headers=[('Location', 'https://publisher.example/a')]),
            dict(headers=[('Content-Type', 'image/svg+xml')]),
            dict(headers=[('Content-Type', 'image/png'), ('Content-Encoding', 'gzip')]),
            dict(headers=[('Content-Type', 'image/png'), ('Content-Length', str(MAX_WIRE_BYTES + 1))]),
            dict(headers=[('Content-Type', 'image/png'), ('Content-Type', 'image/jpeg')]),
            dict(body=b'x' * (MAX_WIRE_BYTES + 1)),
            dict(headers=[('Content-Type', 'image/png'), ('Content-Length', '999')])]
        for kwargs in cases:
            transport, events = self.fake(**kwargs)
            with self.subTest(kwargs=kwargs.keys()), self.assertRaises(ValueError):
                transport.fetch(FIXTURE_SOURCE)
            self.assertLessEqual(sum(row[0] == 'request' for row in events), 1)
            if 'addresses' in kwargs:
                self.assertFalse(events)


class GatewayThumbnailTests(unittest.TestCase):
    def setUp(self):
        self.ledger = Mock(reserve=Mock(return_value=1))
        self.provider_transport = Mock(request=Mock(return_value=FetchResult(200, {},
            json.dumps({'results': [news()]}).encode())))
        self.images = ThumbnailService(fixture=True)
        self.provider = BraveProvider(self.ledger, 'synthetic-not-a-provider-key', transport=self.provider_transport,
                                      thumbnails=self.images, default_count=10)
        self.app = SearchApplication(self.provider)
        self.server = LocalServer(('127.0.0.1', 0), handler_for(self.app, ['http://127.0.0.1:8898']))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(2)
        self.app.close()

    def request(self, path, raw=None, *, method='POST', origin=None, mime='application/json'):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_address[1], timeout=2)
        headers = {'Content-Type': mime}
        if origin is not None: headers['Origin'] = origin
        connection.request(method, path, json.dumps(raw).encode() if raw is not None else None, headers)
        response = connection.getresponse()
        result = response.status, dict(response.getheaders()), response.read()
        connection.close()
        return result

    def token(self):
        status, _, body = self.request('/v1/search', {'query': 'space', 'kind': 'news'})
        self.assertEqual(status, 200)
        return json.loads(body)['results'][0]['thumbnail']['token']

    def test_news_fetch_release_do_not_increase_provider_attempts_or_search_metrics(self):
        token = self.token()
        counts = self.app.metrics.snapshot()
        status, headers, body = self.request(THUMBNAIL_PATH, {'token': token}, origin='http://127.0.0.1:8898')
        self.assertEqual(status, 200)
        self.assertEqual(headers['Content-Type'], 'image/png')
        self.assertIn('no-store', headers['Cache-Control'])
        self.assertEqual(headers['Referrer-Policy'], 'no-referrer')
        self.assertTrue(body.startswith(b'\x89PNG'))
        self.assertEqual(self.request(THUMBNAIL_PATH, {'token': token})[0], 404)
        self.assertEqual(self.request(RELEASE_PATH, {'tokens': [token]})[0], 200)
        self.assertEqual(self.ledger.reserve.call_count, 1)
        self.assertEqual(self.provider_transport.request.call_count, 1)
        self.assertEqual(self.app.metrics.snapshot(), counts)
        self.assertNotIn(CDN_HOST, json.dumps(counts))

    def test_get_head_foreign_origin_forms_and_arbitrary_urls_do_not_consume(self):
        token = self.token()
        for method in ('GET', 'HEAD'):
            self.assertEqual(self.request(THUMBNAIL_PATH, method=method)[0], 404)
        self.assertEqual(self.request(THUMBNAIL_PATH, {'token': token}, origin='https://evil.example')[0], 403)
        self.assertEqual(self.request(THUMBNAIL_PATH, {'token': token}, mime='text/plain')[0], 415)
        self.assertEqual(self.request(THUMBNAIL_PATH, {'token': token, 'url': FIXTURE_SOURCE})[0], 404)
        self.assertEqual(self.images.snapshot()['consumed'], 0)
        self.assertEqual(self.request(THUMBNAIL_PATH, {'token': token})[0], 200)
        self.assertEqual(self.provider_transport.request.call_count, 1)

    def test_fixture_application_registers_offline_thumbnail(self):
        app = SearchApplication(FixtureProvider())
        try:
            result = app.search({'query': 'space', 'kind': 'news'})
            self.assertTrue(result['fixture'])
            token = result['results'][0]['thumbnail']['token']
            self.assertTrue(app.thumbnail_request(THUMBNAIL_PATH, {'token': token})[0].startswith(b'\x89PNG'))
            self.assertEqual(app.thumbnails.snapshot()['upstream_attempts'], 0)
        finally:
            app.close()

    def test_local_status_exposes_only_aggregate_thumbnail_counts(self):
        token = self.token()
        self.assertEqual(self.request(THUMBNAIL_PATH, {'token': token})[0], 200)
        status, _, body = self.request('/statusz', method='GET')
        self.assertEqual(status, 200)
        counts = json.loads(body)['thumbnailMetrics']
        self.assertEqual(counts['registered'], 1)
        self.assertEqual(counts['delivered'], 1)
        self.assertEqual(counts['upstream_attempts'], 0)
        self.assertNotIn(token, body.decode())
        self.assertNotIn(CDN_HOST, body.decode())
        self.assertNotIn('thumbnailMetrics', json.loads(self.request('/healthz', method='GET')[2]))


if __name__ == '__main__':
    unittest.main()
