"""Editorial delivery regressions. Fixtures do not assert real publisher supply."""
import copy
import json
import tempfile
import unittest
from datetime import timedelta
from unittest.mock import patch

from wingman_content.diagnostics import export_diagnostics
from wingman_content.fetch import FetchError
from wingman_content.normalize import parse_feed
from wingman_content.provider import RssAtomProvider, ingest
from wingman_content.store import LocalStore
from test_content import Allow, FakeFetcher, NOW, SOURCE, response, rss


class EditorialNormalizationTests(unittest.TestCase):
    def test_sports_and_film_with_no_image_are_text_eligible(self):
        for topic, title in [('sports', 'New York wins the final match'),
                             ('entertainment', 'A film review of the new drama')]:
            source = dict(SOURCE, topics=[topic])
            body = rss('<item><title>' + title + '</title><link>https://public.example/news/a</link></item>')
            items, held, deleted = parse_feed(body, source, NOW, Allow())
            self.assertEqual(held['textEligible'], 1)
            self.assertEqual(held['topicMatched'], 1)
            self.assertEqual(held['imagePermitted'], 0)
            self.assertEqual(items[0]['title'], title)
            self.assertIsNone(items[0]['image'])
            self.assertEqual(deleted, [])

    def test_malformed_individual_metadata_does_not_revoke_or_break_siblings(self):
        body = rss('<item><link>https://public.example/news/a</link></item>'
                   '<item><title>Missing link</title></item>'
                   '<item><title>A film review</title><link>https://public.example/news/good</link></item>')
        items, held, deleted = parse_feed(body, SOURCE, NOW, Allow())
        self.assertEqual([i['title'] for i in items], ['A film review'])
        self.assertEqual(held['parsedEntries'], 3)
        self.assertEqual(held['reasons'], {'missing-title': 1, 'missing-link': 1})
        self.assertEqual(deleted, [])
        with self.assertRaises(Exception):
            parse_feed(body[:-5], SOURCE, NOW, Allow())

    def test_optional_credit_absent_allowed_but_required_credit_still_held(self):
        items, _, _ = parse_feed(rss(), SOURCE, NOW, Allow())
        self.assertEqual(len(items), 1)
        items, held, _ = parse_feed(rss(), dict(SOURCE, requiresAttribution=True), NOW, Allow())
        self.assertEqual(items, [])
        self.assertEqual(held['reasons'], {'missing-author': 1})

    def test_overlong_rejected_headline_cannot_expand_diagnostics_without_bound(self):
        body = rss('<item><title>' + 'Huge headline ' * 6000 + '</title>'
                   '<link>https://public.example/news/a</link></item>')
        items, held, _ = parse_feed(body, SOURCE, NOW, Allow())
        self.assertFalse(items)
        self.assertEqual(held['reasons'], {'headline-size-limit': 1})
        self.assertEqual(len(held['examples'][0]['title']), 500)
        self.assertTrue(held['examples'][0]['titleTruncated'])

    def test_title_denial_cannot_be_repaired_by_photo_or_summary(self):
        source = copy.deepcopy(SOURCE)
        source['rights']['titles'] = False
        items, held, _ = parse_feed(rss(), source, NOW, Allow())
        self.assertFalse(items)
        self.assertEqual(held['reasons'], {'source-text-not-permitted': 1})

    def test_story_chrome_is_not_story_content_but_actual_promotion_stays_held(self):
        body = rss('<item><title>New York wins the final match</title>'
                   '<link>https://public.example/news/a</link>'
                   '<description><![CDATA[<p>The team won the match.</p>'
                   '<nav><a href="/sportsbook">Sportsbook</a></nav>'
                   '<footer>Casino bonus and vape sale</footer>]]></description></item>')
        items, held, _ = parse_feed(body, SOURCE, NOW, Allow())
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]['excerpt'], 'The team won the match.')
        self.assertEqual(held['count'], 0)
        items, held, _ = parse_feed(body.replace(b'The team won the match.', b'Get a casino bonus.'), SOURCE, NOW, Allow())
        self.assertFalse(items)
        self.assertEqual(held['reasons'], {'promotion-or-rights-ambiguity': 1})


class EditorialDeliveryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.store = LocalStore(self.directory.name)
        self.config = {'schemaVersion': 1, 'sources': [copy.deepcopy(SOURCE)]}

    def ingest(self, values, now=NOW):
        fetcher = FakeFetcher(values)
        result = ingest(self.config, self.store, RssAtomProvider(Allow(), fetcher), now)
        return result, fetcher

    def test_no_store_then_cacheable_response_recovers_same_article_identity(self):
        (original, _), _ = self.ingest([response()])
        (held, _), _ = self.ingest([response(headers={'cache-control': 'no-store'})], NOW + timedelta(minutes=30))
        self.assertFalse(held['items'])
        self.assertFalse(held['revokedItemIds'])
        # Source backoff remains in force; repairing storage must not hurry fetches.
        (_, _), early = self.ingest([], NOW + timedelta(minutes=31))
        self.assertFalse(early.calls)
        (recovered, _), fetched = self.ingest([response()], NOW + timedelta(hours=1))
        self.assertEqual(recovered['items'][0]['id'], original['items'][0]['id'])
        self.assertEqual(fetched.calls[0][1], {})

    def test_real_revocation_is_not_reversed_after_cache_hold(self):
        (one, _), _ = self.ingest([response()])
        self.config['sources'][0]['revokedUrls'] = [one['items'][0]['canonicalUrl']]
        self.ingest([response(headers={'cache-control': 'private'})], NOW + timedelta(minutes=30))
        self.config['sources'][0]['revokedUrls'] = []
        (two, _), _ = self.ingest([response()], NOW + timedelta(hours=1))
        self.assertFalse(two['items'])
        self.assertEqual(two['revokedItemIds'], [one['items'][0]['id']])

    def test_empty_not_due_and_parser_failure_have_distinct_observed_diagnostics(self):
        (_, report), _ = self.ingest([response(b'<rss><channel/></rss>')])
        diag = report[0]['diagnostics']
        self.assertEqual((diag['outcome'], diag['httpStatus'], diag['parsedEntries']), ('empty', 200, 0))
        self.assertTrue(diag['requested'])
        (_, report), fetcher = self.ingest([], NOW + timedelta(minutes=1))
        diag = report[0]['diagnostics']
        self.assertEqual(diag['outcome'], 'not-due')
        self.assertFalse(diag['requested'])
        self.assertFalse(diag['transportError'])
        self.assertFalse(fetcher.calls)
        last_success = diag['lastSuccessAt']
        (_, report), _ = self.ingest([response(b'<rss><broken>')], NOW + timedelta(minutes=30))
        diag = report[0]['diagnostics']
        self.assertEqual(diag['parserError'], 'invalid-feed')
        self.assertEqual(diag['httpStatus'], 200)
        self.assertTrue(diag['fetched'])
        self.assertEqual(diag['lastSuccessAt'], last_success)
        self.assertNotEqual(diag['attemptedAt'], diag['lastSuccessAt'])

    def test_http_429_preserves_status_retry_pacing_and_last_success(self):
        self.ingest([response()])
        (_, report), _ = self.ingest([FetchError('http-429', '7200')], NOW + timedelta(minutes=30))
        diag = report[0]['diagnostics']
        self.assertEqual(diag['httpStatus'], 429)
        self.assertEqual(diag['transportError'], 'http-429')
        self.assertFalse(diag['fetched'])
        self.assertEqual(diag['textEligible'], 1)  # Last good parse, not fabricated fresh content.
        self.assertEqual(diag['countedAt'], diag['lastSuccessAt'])

    def test_304_revalidation_does_not_claim_a_new_parse(self):
        (_, before), _ = self.ingest([response()])
        (_, after), _ = self.ingest([response(status=304)], NOW + timedelta(minutes=30))
        self.assertEqual(after[0]['diagnostics']['countedAt'], before[0]['diagnostics']['countedAt'])
        self.assertNotEqual(after[0]['diagnostics']['lastSuccessAt'], before[0]['diagnostics']['lastSuccessAt'])
        self.assertEqual(after[0]['diagnostics']['outcome'], 'not-modified')

    def test_cached_items_recheck_title_and_changed_category_contract_without_request(self):
        self.ingest([response()])
        self.config['sources'][0]['requiredTopicTerms'] = ['film']
        (snapshot, _), fetcher = self.ingest([], NOW + timedelta(minutes=1))
        self.assertFalse(snapshot['items'])
        self.assertFalse(snapshot['revokedItemIds'])
        self.assertFalse(fetcher.calls)
        self.config['sources'][0]['requiredTopicTerms'] = []
        self.config['sources'][0]['rights']['titles'] = False
        (snapshot, _), _ = self.ingest([], NOW + timedelta(minutes=2))
        self.assertFalse(snapshot['items'])
        self.assertEqual(snapshot['sources'][0]['status'], 'revoked')

    def test_diagnostics_export_reads_existing_generation_without_network_or_reader_data(self):
        self.ingest([response()])
        before = self.store.path.read_bytes()
        bundle = self.store.read()
        bundle['states'][SOURCE['id']]['history'] = ['https://secret.invalid/']
        bundle['states'][SOURCE['id']]['interests'] = ['private preference']
        with patch('wingman_content.fetch.SecureFeedFetcher.fetch', side_effect=AssertionError('unexpected network')):
            report = export_diagnostics(self.config, bundle, NOW)
        self.assertEqual(report['networkRequests'], 0)
        self.assertEqual(report['readerData'], 'none')
        self.assertNotIn('secret.invalid', json.dumps(report))
        self.assertNotIn('private preference', json.dumps(report))
        science = next(r for r in report['categories'] if r['category'] == 'science')
        self.assertEqual((science['serverEligible'], science['imageCards'], science['textFallbacks']), (1, 0, 1))
        self.assertEqual(science['visibility'], 'not-measured-on-server')
        self.assertEqual(self.store.path.read_bytes(), before)

    def test_duplicate_keeps_one_source_contract_without_combining_rights_or_topics(self):
        first = self.config['sources'][0]
        first.update(topics=['sports'], publisherId='reviewed-publisher')
        first['rights']['excerpts'] = False
        second = copy.deepcopy(first)
        second.update(id='second-section', topics=['business'])
        second['rights']['excerpts'] = True
        self.config['sources'].append(second)
        (snapshot, _), _ = self.ingest([response(), response()])
        self.assertEqual(len(snapshot['items']), 1)
        item = snapshot['items'][0]
        self.assertEqual(item['topics'], ['sports'])
        self.assertEqual(item['sourceId'], first['id'])
        self.assertFalse(item['rights']['excerpt'])
        self.assertNotIn('excerpt', item)
        second['publisherId'] = 'different-publisher'
        (snapshot, _), _ = self.ingest([], NOW + timedelta(minutes=1))
        self.assertEqual(snapshot['items'][0]['topics'], ['sports'])
        second['publisherId'] = 'reviewed-publisher'
        second['requiredTopicTerms'] = ['film']
        (snapshot, _), _ = self.ingest([], NOW + timedelta(minutes=2))
        self.assertEqual(snapshot['items'][0]['topics'], ['sports'])


if __name__ == '__main__':
    unittest.main()
