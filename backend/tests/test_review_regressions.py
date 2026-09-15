"""Regression cases from independent review; synthetic data, no publisher fetches."""
import copy
import http.client
import json
import tempfile
import threading
import unittest
from datetime import datetime, timedelta, timezone
from wingman_content.fetch import FetchError, SecureFeedFetcher
from wingman_content.media import cache_ttl
from wingman_content.normalize import iso, parse_feed
from wingman_content.provider import RssAtomProvider
from wingman_content.server import BoundedServer, handler_for
from wingman_content.store import LocalStore
from test_content import Allow, SOURCE, rss

NOW = datetime(2026, 9, 15, tzinfo=timezone.utc)


def transport(headers, body=None):
    """Exercise the actual HTTP-header normalization without a network socket."""
    class Response:
        status = 200
        def __init__(self):
            self.data = rss() if body is None else body
        def getheaders(self):
            return headers
        def read(self, _size):
            result, self.data = self.data, b''
            return result
    class Connection:
        sock = None
        def __init__(self, *_args):
            self.response = Response()
        def request(self, *_args, **_kwargs):
            pass
        def getresponse(self):
            return self.response
        def close(self):
            pass
    return SecureFeedFetcher(lambda *_args: ['8.8.8.8'], Connection)


def story(description, date='', author='Fixture Author'):
    return rss('<item><title>Science and family routines</title>'
               '<link>https://public.example/news/a</link>'
               '<author>' + author + '</author><pubDate>' + date + '</pubDate>'
               '<description><![CDATA[' + description + ']]></description></item>')


class ReviewRegressions(unittest.TestCase):
    def test_repeated_no_store_survives_and_prevents_shared_text_storage(self):
        for directives in [('no-store', 'max-age=1800'), ('max-age=1800', 'no-store')]:
            headers = [('Content-Type', 'application/rss+xml')]
            headers += [('Cache-Control', value) for value in directives]
            fetched = transport(headers).fetch(SOURCE)
            self.assertEqual(cache_ttl(fetched.headers), 0)
            provider = RssAtomProvider(Allow(), transport(headers))
            with self.assertRaises(FetchError) as failed:
                provider.refresh(SOURCE, {}, NOW)
            self.assertEqual(failed.exception.reason, 'source-cache-prohibited')

    def test_repeated_pragma_no_cache_cannot_be_overwritten(self):
        headers = [('Content-Type', 'application/rss+xml'),
                   ('Cache-Control', 'max-age=1800'),
                   ('Pragma', 'no-cache'), ('Pragma', 'extension-value')]
        self.assertEqual(cache_ttl(transport(headers).fetch(SOURCE).headers), 0)

    def test_duplicate_singleton_response_metadata_fails_closed(self):
        values = {'content-type': 'application/rss+xml', 'content-length': '0',
                  'content-encoding': 'identity', 'location': '/feed',
                  'retry-after': '1800', 'age': '1'}
        for name, value in values.items():
            with self.subTest(header=name):
                headers = [] if name == 'content-type' else [('content-type', 'application/rss+xml')]
                headers += [(name, value), (name.upper(), value)]
                with self.assertRaises(FetchError) as failed:
                    transport(headers).fetch(SOURCE)
                self.assertEqual(failed.exception.reason, 'duplicate-response-metadata')

    def test_normal_cacheable_response_still_has_its_remaining_lifetime(self):
        response = transport([('Content-Type', 'application/rss+xml'),
                              ('Cache-Control', 'public'),
                              ('Cache-Control', 'max-age=600'), ('Age', '200')]).fetch(SOURCE)
        self.assertEqual(cache_ttl(response.headers), 400)
        self.assertTrue(response.body)

    def test_preserved_summary_is_held_instead_of_edited_to_fit(self):
        source = dict(SOURCE, preserveFeedText=True)
        complete = 'Research results and explanations. ' * 70
        items, held, _ = parse_feed(story(complete), source, NOW, Allow())
        self.assertEqual(items, [])
        self.assertEqual(held['reasons'], {'excerpt-size-limit': 1})
        short = 'Publisher summary with its original words.'
        items, held, _ = parse_feed(story(short), source, NOW, Allow())
        self.assertEqual(held['count'], 0)
        self.assertEqual(items[0]['excerpt'], short)
        self.assertFalse(items[0]['excerptProvenance']['shortened'])

    def test_sponsored_future_date_is_withheld_not_relabelled_unknown(self):
        source = copy.deepcopy(SOURCE)
        source.update(displayMode='sponsored-syndication', preserveFeedText=True,
                      eligibilityScope='sponsored-features', requiresAttribution=True)
        source['rights']['excerpts'] = False
        for date in ['2026-09-15T00:00:01Z', '2026-10-15T00:00:00Z', '2035-01-01T00:00:00Z']:
            with self.subTest(date=date):
                items, held, _ = parse_feed(story('<p>Families enjoy walking together.</p>', date), source, NOW, Allow())
                self.assertFalse(items)
                self.assertEqual(held['reasons'], {'outside-publication-window': 1})
        items, held, _ = parse_feed(story('<p>Families enjoy walking together.</p>', '2026-09-14T12:00:00Z'), source, NOW, Allow())
        self.assertEqual(held['count'], 0)
        self.assertEqual(items[0]['publishedAt'], '2026-09-14T12:00:00Z')
        self.assertEqual(items[0]['syndicatedArticle']['html'], '<p>Families enjoy walking together.</p>')

    def test_missing_date_remains_unknown_without_being_fabricated(self):
        items, held, _ = parse_feed(story('A publisher summary.'), SOURCE, NOW, Allow())
        self.assertEqual(held['count'], 0)
        self.assertIsNone(items[0]['publishedAt'])

    def test_server_rechecks_publication_age_without_reingestion(self):
        now = datetime.now(timezone.utc)
        base = {'sourceId': SOURCE['id'], 'fetchedAt': iso(now - timedelta(days=1)),
                'expiresAt': iso(now + timedelta(days=6))}
        old = dict(base, id='old', publishedAt=iso(now - timedelta(days=31)))
        recent = dict(base, id='recent', publishedAt=iso(now - timedelta(days=29)))
        snapshot = {'generatedAt': iso(now - timedelta(days=1)),
                    'expiresAt': iso(now + timedelta(minutes=30)), 'items': [old, recent]}
        with tempfile.TemporaryDirectory() as directory:
            store = LocalStore(directory)
            store.write({'snapshot': snapshot})
            server = BoundedServer(('127.0.0.1', 0), handler_for(store))
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            connection = http.client.HTTPConnection('127.0.0.1', server.server_port)
            try:
                connection.request('GET', '/v1/snapshot.json')
                response = connection.getresponse()
                self.assertEqual(response.status, 200)
                result = json.loads(response.read())
                self.assertEqual([i['id'] for i in result['items']], ['recent'])
            finally:
                connection.close()
                server.shutdown()
                server.server_close()
                worker.join()
