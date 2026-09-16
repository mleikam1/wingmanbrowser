"""Fixture integration for the real provider/normalizer/public service path."""
import copy
import http.client
import json
import tempfile
import threading
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

from wingman_content.config import load_config
from wingman_content.normalize import (canonical_url, currents_topics, iso,
                                       item_id, parse_currents_news)
from wingman_content.provider import (CompositeNewsProvider, RssAtomProvider,
                                      ingest, public_snapshot)
from wingman_content.server import BoundedServer, handler_for
from wingman_content.store import LocalStore, encode
from test_content import Allow, FakeFetcher, SOURCE, response

ROOT = Path(__file__).resolve().parents[2]
NOW = datetime(2026, 9, 16, 12, tzinfo=timezone.utc)
CURRENTS = next(s for s in load_config(ROOT / 'backend/sources.json')['sources'] if s['id'] == 'currents')


def news(**values):
    row = {'id': 'api-id', 'title': 'New scientific research findings',
           'description': 'Researchers report new evidence.',
           'url': 'https://news.example.com/articles/a?utm_source=api',
           'language': 'en', 'category': ['science_technology'],
           'published': '2026-09-16 06:00:00 -0500', 'author': 'Jane Reporter'}
    return dict(row, **values)


def state(items):
    return {'items': items, 'lastSuccessAt': iso(NOW), 'fetchedAt': iso(NOW),
            'nextRefreshAt': iso(NOW + timedelta(hours=6)), 'status': 'fresh'}


class ApiNormalizationTests(unittest.TestCase):
    def parse(self, rows, category=None, source=None):
        return parse_currents_news(rows, source or CURRENTS, NOW, Allow(), category)

    def test_all_sixteen_canonical_categories_map_without_legacy_query_ids(self):
        from wingman_content.currents import CATEGORIES, CATEGORY_TOPICS
        self.assertEqual(len(CATEGORIES), 16)
        for category in CATEGORIES:
            with self.subTest(category=category):
                items, held = self.parse([news(category=[category], title='Current reporting', description='')], category)
                self.assertEqual(held['count'], 0)
                self.assertEqual(items[0]['providerCategories'], [category])
                expected = CATEGORY_TOPICS[category]
                self.assertTrue(set([expected] if isinstance(expected, str) else expected) <= set(items[0]['topics']))

    def test_parent_topics_do_not_fabricate_derived_membership(self):
        self.assertEqual(currents_topics(['science_technology'], 'Latest developments'), ['science_technology'])
        self.assertEqual(currents_topics(['lifestyle_leisure'], 'A quiet weekend'), ['lifestyle_leisure'])
        self.assertEqual(currents_topics(['lifestyle_leisure'], 'Chef shares a cooking recipe'), ['food', 'lifestyle_leisure'])
        self.assertEqual(currents_topics(['science_technology'], 'New software for computers'), ['science_technology', 'technology'])
        self.assertIn('fashion', currents_topics(['arts_culture_entertainment'], 'Fashion design exhibition'))
        self.assertIn('travel', currents_topics(['general'], 'Tourism destinations to visit'))

    def test_optional_values_do_not_drop_preview_and_dates_remain_original(self):
        for image in (None, '', 'null', 'None', 'https://images.example.com/a.jpg'):
            items, held = self.parse([news(description=None, author=None, image=image)])
            self.assertEqual(held['count'], 0)
            item = items[0]
            self.assertIsNone(item['image'])
            self.assertEqual(item['publishedAt'], '2026-09-16T11:00:00Z')
            self.assertEqual(item['fetchedAt'], iso(NOW))
            self.assertEqual(item['expiresAt'], iso(NOW + timedelta(hours=24)))
            self.assertEqual(item['originalUrl'], news()['url'])
            self.assertEqual(item['canonicalUrl'], 'https://news.example.com/articles/a')
            self.assertNotIn('excerpt', item)

    def test_original_publisher_is_not_author_or_provider(self):
        items, _ = self.parse([news(source={'name': 'Example Daily', 'domain': 'news.example.com'})])
        self.assertEqual(items[0]['publisherName'], 'Example Daily')
        self.assertEqual(items[0]['publisherId'], 'news.example.com')
        self.assertEqual(items[0]['author'], 'Jane Reporter')
        self.assertEqual(items[0]['providerId'], 'currents')
        self.assertEqual(items[0]['providerAttribution']['label'], 'Powered by Currents News API')
        items, _ = self.parse([news(source={'name': 'Wrong publisher', 'domain': 'different.example.com'})])
        self.assertEqual(items[0]['publisherName'], 'news.example.com')

    def test_preview_permission_is_independent_from_disabled_rss_and_image_permission(self):
        item = self.parse([news(image='https://image.example.com/photo.jpg')])[0][0]
        self.assertTrue(item['rights']['title'])
        self.assertTrue(item['rights']['excerpt'])
        self.assertFalse(item['rights']['image'])
        self.assertEqual(item['eligibility']['basis'], 'provider-preview')
        self.assertNotIn('image.example.com', json.dumps(item))

    def test_only_exact_separately_reviewed_api_photo_enters_trusted_media_pipeline(self):
        source = copy.deepcopy(CURRENTS)
        source['rights']['images'] = True
        article = 'https://news.example.com/articles/a'
        image = {'schemaVersion': 1, 'sourceId': 'currents', 'articleId': item_id(article),
                 'articleUrl': article, 'url': 'https://images.example.com/exact.jpg',
                 'basis': 'reviewed-article-image', 'credit': 'Example photographer',
                 'licenseLabel': 'Fixture explicit permission', 'licenseUrl': 'https://news.example.com/permission',
                 'caption': None, 'width': 640, 'height': 480}
        source['imagePolicy'] = {'kind': 'reviewed-article-image', 'maximumWidth': 2048,
                'maximumHeight': 2048, 'allowedHosts': ['images.example.com'], 'pathPrefixes': ['/'],
                'credit': image['credit'], 'licenseLabel': image['licenseLabel'], 'licenseUrl': image['licenseUrl'],
                'reviewedArticles': {article: image}}
        items, _ = self.parse([news(image=image['url'])], source=source)
        self.assertEqual(items[0]['image'], image)
        self.assertTrue(items[0]['rights']['image'])
        items, _ = self.parse([news(image='https://images.example.com/unrelated.jpg')], source=source)
        self.assertIsNone(items[0]['image'])
        self.assertEqual(len(items), 1)

    def test_host_validation_and_baseline_are_not_bypassed_by_api(self):
        for url in ('http://example.com/a', 'https://127.0.0.1/a', 'https://10.0.0.1/a',
                    'https://user@example.com/a', 'https://api.currentsapi.services/v2/latest-news',
                    'https://localhost/a', 'https://app.local/a', 'https://example.com:22/a',
                    'https://example.com/%2e%2e/a'):
            self.assertIsNone(canonical_url(url, CURRENTS), url)
        class Deny:
            def allows(self, _url):
                return False
        items, held = parse_currents_news([news()], CURRENTS, NOW, Deny())
        self.assertFalse(items)
        self.assertEqual(held['reasons'], {'destination-policy': 1})

    def test_oversize_record_is_held_individually_and_copyright_credit_survives(self):
        items, held = self.parse([news(description='x' * 100001), news(copyright='© Example Daily 2026')])
        self.assertEqual(len(items), 1)
        self.assertIn('© Example Daily 2026', items[0]['attribution'])
        self.assertEqual(held['count'], 1)


class CompositionAndInventoryTests(unittest.TestCase):
    def test_legacy_adapter_cannot_bypass_api_budget_gateway(self):
        fetcher = FakeFetcher([])
        with self.assertRaisesRegex(ValueError, 'rss-provider-mismatch'):
            RssAtomProvider(Allow(), fetcher).refresh(CURRENTS, {}, NOW)
        self.assertEqual(fetcher.calls, [])

    def test_unconfigured_currents_preserves_existing_rss_without_duplicate_fetch(self):
        rss_source = copy.deepcopy(SOURCE)
        rss_fetcher = FakeFetcher([response()])
        with tempfile.TemporaryDirectory() as directory:
            snapshot, report = ingest({'sources': [rss_source, CURRENTS]}, LocalStore(directory),
                    CompositeNewsProvider(RssAtomProvider(Allow(), rss_fetcher)), NOW)
        self.assertEqual(len(rss_fetcher.calls), 1)
        self.assertEqual(len(snapshot['items']), 1)
        self.assertEqual(report[1]['action'], 'provider-not-configured')
        self.assertNotIn('diagnostics', snapshot['sources'][0])

    def test_currents_same_article_merges_category_membership_only(self):
        first = parse_currents_news([news(category=['sport'])], CURRENTS, NOW, Allow())[0][0]
        second = parse_currents_news([news(category=['society'])], CURRENTS, NOW, Allow())[0][0]
        snapshot = public_snapshot({'sources': [CURRENTS]}, {'currents': state([first, second])}, NOW)
        self.assertEqual(len(snapshot['items']), 1)
        self.assertEqual(snapshot['items'][0]['providerCategories'], ['society', 'sport'])
        self.assertEqual(snapshot['items'][0]['topics'], ['society', 'sports'])

    def test_balancing_precedes_global_limits_and_large_optional_fields_do_not_drop_snapshot(self):
        from wingman_content.currents import CATEGORIES
        items = []
        for category in CATEGORIES:
            for n in range(28):
                rows, _ = parse_currents_news([news(title='Current reporting', description='x' * 800,
                    url='https://publisher%d.example.com/%s/%d' % (n % 3, category, n),
                    category=[category])], CURRENTS, NOW, Allow(), category)
                items.extend(rows)
        items[0]['excerpt'] = 'x' * 1000000
        snapshot = public_snapshot({'sources': [CURRENTS]}, {'currents': state(items)}, NOW)
        self.assertLessEqual(len(snapshot['items']), 300)
        self.assertLessEqual(len(encode(snapshot)), 512 * 1024)
        self.assertEqual({category for item in snapshot['items'] for category in item['providerCategories']}, set(CATEGORIES))
        self.assertEqual(len({item['publisherId'] for item in snapshot['items'][:16]}), 3)

    def test_failed_poll_and_republication_do_not_extend_retention(self):
        item = parse_currents_news([news()], CURRENTS, NOW, Allow())[0][0]
        previous = state([item])
        previous['error'] = 'quota-paused'
        for offset, count in ((6, 1), (23, 1), (24, 0)):
            snapshot = public_snapshot({'sources': [CURRENTS]}, {'currents': previous}, NOW + timedelta(hours=offset))
            self.assertEqual(len(snapshot['items']), count)
            if count:
                self.assertEqual(snapshot['items'][0]['expiresAt'], item['expiresAt'])

    def test_hundreds_of_conditional_client_reads_never_dispatch_providers(self):
        class ApiFixture:
            calls = 0
            def refresh(self, source, prior, now):
                self.calls += 1
                value = state(parse_currents_news([news()], source, now, Allow())[0])
                value['lastHttpStatus'] = 200
                value['diagnostics'] = {'privateQuota': 'must-not-leak'}
                return value
        api = ApiFixture()
        with tempfile.TemporaryDirectory() as directory:
            store = LocalStore(directory)
            ingest({'sources': [CURRENTS]}, store, CompositeNewsProvider(None, api), NOW)
            server = BoundedServer(('127.0.0.1', 0), handler_for(store))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                etag = None
                for index in range(220):
                    connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=2)
                    connection.request('GET', '/v1/snapshot.json', headers={'If-None-Match': etag} if etag else {})
                    response = connection.getresponse()
                    body = response.read()
                    self.assertEqual(response.status, 304 if etag else 200)
                    self.assertNotIn(b'privateQuota', body)
                    etag = response.getheader('ETag')
                    connection.close()
                self.assertEqual(api.calls, 1)
            finally:
                server.shutdown()
                server.server_close()
                thread.join()

    def test_expiry_changes_etag_and_cannot_return_304_for_old_modified_date(self):
        item = parse_currents_news([news()], CURRENTS, NOW, Allow())[0][0]
        item['expiresAt'] = iso(NOW + timedelta(seconds=30))
        snapshot = public_snapshot({'sources': [CURRENTS]}, {'currents': state([item])}, NOW)
        class Clock:
            current = NOW
            @classmethod
            def now(cls, _timezone=None):
                return cls.current
        with tempfile.TemporaryDirectory() as directory:
            store = LocalStore(directory)
            store.write({'snapshot': snapshot})
            server = BoundedServer(('127.0.0.1', 0), handler_for(store))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            def request(headers):
                connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=2)
                connection.request('GET', '/v1/snapshot.json', headers=headers)
                reply = connection.getresponse()
                result = reply.status, dict(reply.getheaders()), json.loads(reply.read())
                connection.close()
                return result
            try:
                with patch('wingman_content.server.datetime', Clock):
                    status, headers, data = request({})
                    self.assertEqual(status, 200)
                    self.assertIn('max-age=30', headers['Cache-Control'])
                    self.assertEqual(len(data['items']), 1)
                    Clock.current += timedelta(seconds=31)
                    status, after, data = request({'If-Modified-Since': headers['Last-Modified']})
                    self.assertEqual(status, 200)
                    self.assertNotEqual(after['ETag'], headers['ETag'])
                    self.assertEqual(data['items'], [])
            finally:
                server.shutdown()
                server.server_close()
                thread.join()


if __name__ == '__main__':
    unittest.main()
