import copy
import gzip
import http.client
import json
import tempfile
import threading
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch
from wingman_content.config import load_config, registry
from wingman_content.fetch import (FetchError, FetchResult, SecureFeedFetcher, configured_url,
                                   inflate_chunks, public_ip, MAX_XML_BYTES, MAX_WIRE_BYTES)
from wingman_content.normalize import (DestinationPolicy, canonical_url, date_value, iso, item_id,
                                       parse_feed, plain, text_eligible, item_topics)
from wingman_content.provider import RssAtomProvider, ingest, public_snapshot, delay_seconds
from wingman_content.server import BoundedServer, handler_for
from wingman_content.store import LocalStore, encode

NOW = datetime(2026, 9, 11, 20, tzinfo=timezone.utc)
ROOT = Path(__file__).resolve().parents[2]
SOURCE = {"id": "test-news", "name": "Test publisher", "homepageUrl": "https://public.example/news/",
          "feedUrl": "https://public.example/feed.xml", "feedRedirectHosts": ["public.example"],
          "allowedArticleHosts": ["public.example"], "articlePathPrefixes": ["/news/"],
          "language": "en", "topics": ["science"], "eligibilityScope": "science-reporting",
          "rights": {"titles": True, "excerpts": True, "images": False, "attribution": "Source: Test",
                     "licenseUrl": "https://public.example/terms"}, "enabled": True,
          "verifiedAt": "2026-09-11T00:00:00Z", "minRefreshSeconds": 1800,
          "retentionSeconds": 604800, "revokedItemIds": [], "revokedUrls": []}


class Allow:
    def allows(self, _url):
        return True


def rss(items=None):
    items = items or '<item><title>Research news</title><link>https://public.example/news/a</link><description>New science research.</description><pubDate>Fri, 11 Sep 2026 14:00:00 EDT</pubDate><guid>a</guid></item>'
    return ('<rss version="2.0"><channel>' + items + '</channel></rss>').encode()


class FakeFetcher:
    def __init__(self, values):
        self.values, self.calls = list(values), []

    def fetch(self, source, validators):
        self.calls.append((source["id"], validators))
        value = self.values.pop(0)
        if isinstance(value, Exception):
            raise value
        return value


def response(body=None, status=200, headers=None):
    return FetchResult(status, headers or {"etag": '"v1"', "last-modified": "Fri, 11 Sep 2026 18:00:00 GMT"},
                       rss() if body is None else body)


class NormalizationTests(unittest.TestCase):
    def parse(self, data):
        return parse_feed(data, SOURCE, NOW, Allow())

    def test_rss_dates_are_publisher_dates(self):
        items, held, _ = self.parse(rss())
        self.assertEqual(items[0]["publishedAt"], "2026-09-11T18:00:00Z")
        self.assertNotEqual(items[0]["publishedAt"], items[0]["fetchedAt"])
        self.assertEqual(held["count"], 0)

    def test_missing_bad_and_naive_dates_stay_null(self):
        for value in ("", "not a date", "2026-09-11T12:00:00"):
            items, _, _ = self.parse(rss('<item><title>Science</title><link>https://public.example/news/a</link><pubDate>' + value + '</pubDate></item>'))
            self.assertIsNone(items[0]["publishedAt"])

    def test_future_date_is_not_asserted_as_publication(self):
        self.assertIsNone(date_value("2035-01-01T00:00:00Z", NOW))

    def test_atom_uses_published_not_updated_and_valid_alternate(self):
        atom = b'<feed xmlns="http://www.w3.org/2005/Atom"><entry><id>x</id><title>Science</title><link href="https://evil.example/a"/><link href="https://public.example/news/a"/><updated>2026-09-11T00:00:00Z</updated><author><name>Jane Scientist</name></author></entry></feed>'
        items, _, _ = self.parse(atom)
        self.assertIsNone(items[0]["publishedAt"])
        self.assertEqual(items[0]["attribution"], "Jane Scientist")

    def test_rss_author_credit_preserved(self):
        items, _, _ = self.parse(rss('<item xmlns:dc="http://purl.org/dc/elements/1.1/"><title>Science</title><link>https://public.example/news/a</link><dc:creator>Jane Scientist</dc:creator></item>'))
        self.assertEqual(items[0]["attribution"], "Jane Scientist")

    def test_no_xml_entities_or_dtd(self):
        for bad in (b'<!DOCTYPE rss [<!ENTITY ext SYSTEM "file:///etc/passwd">]><rss><channel>&ext;</channel></rss>',
                    b'<!DOCTYPE rss SYSTEM "https://public.example/evil"><rss/>',
                    b'<!DOCTYPE rss [<!ENTITY a "123"><!ENTITY b "&a;&a;">]><rss>&b;</rss>'):
            with self.assertRaises(Exception):
                self.parse(bad)

    def test_malformed_non_feed_and_oversize(self):
        for bad in (b'<rss><', b'<html>not feed</html>', b'x' * (MAX_XML_BYTES + 1)):
            with self.assertRaises(Exception):
                self.parse(bad)

    def test_entry_limit(self):
        with self.assertRaises(ValueError):
            self.parse(rss('<item/>' * 501))

    def test_html_plaintext_has_no_remote_media_or_script(self):
        self.assertEqual(plain('<p>Science<img src="https://tracker.example/pixel"><script>evil()</script></p>', 400), 'Science')
        items, _, _ = self.parse(rss())
        self.assertIsNone(items[0]["image"])

    def test_full_title_and_description_review_before_truncation(self):
        items, held, _ = self.parse(rss('<item><title>' + 'science ' * 100 + 'Buy now</title><link>https://public.example/news/a</link></item>'))
        self.assertFalse(items)
        self.assertEqual(held["reasons"], {"promotion-or-rights-ambiguity": 1})
        items, _, _ = self.parse(rss('<item><title>Science</title><link>https://public.example/news/a</link><description>' + 'science ' * 100 + 'Sponsored content</description></item>'))
        self.assertFalse(items)

    def test_oversized_field_is_held_not_truncated_into_eligibility(self):
        items, held, _ = self.parse(rss('<item><title>Science</title><link>https://public.example/news/a</link><description>' + 'x' * 100001 + ' buy now</description></item>'))
        self.assertFalse(items)
        self.assertEqual(held['reasons'], {'metadata-size-limit': 1})

    def test_reporting_distinction_and_ambiguous_promotion(self):
        self.assertTrue(text_eligible("Study of tobacco pollution in water", "Research evidence", []))
        self.assertFalse(text_eligible("Wine celebration", "New bottles", []))
        self.assertFalse(text_eligible("Science", "Research sponsored content", []))
        self.assertFalse(text_eligible("Science", "Description © 2026 Third Party", []))
        self.assertFalse(text_eligible("Science", "Copyright 2026 Third Party", []))

    def test_nasa_topics_come_from_publisher_section_not_feed_label(self):
        source = dict(SOURCE, id='nasa-technology')
        self.assertEqual(item_topics('https://science.nasa.gov/earth/earth-observatory/volcano/', source), ['science'])
        self.assertEqual(item_topics('https://www.nasa.gov/technology/tech-transfer-spinoffs/example/', source), ['science', 'technology'])

    def test_exact_article_hosts_and_scoped_paths(self):
        for url in ("http://public.example/news/a", "https://public.example.evil/news/a",
                    "https://sub.public.example/news/a", "https://public.example/shop/a",
                    "https://a@public.example/news/a", "https://public.example/news/../shop/a",
                    "https://public.example:444/news/a", "https://public.example/news/%00a"):
            self.assertIsNone(canonical_url(url, SOURCE), url)

    def test_tracking_canonicalization_and_stable_ids(self):
        clean = canonical_url("https://public.example/news/a?utm_source=rss&amp;utm_medium=feed#part", SOURCE)
        self.assertEqual(clean, "https://public.example/news/a")
        self.assertEqual(item_id(clean), item_id("https://public.example/news/a"))

    def test_destination_policy_runs_before_eligibility(self):
        class Deny:
            def allows(self, _url):
                return False
        items, held, _ = parse_feed(rss(), SOURCE, NOW, Deny())
        self.assertFalse(items)
        self.assertEqual(held["reasons"], {"destination-policy": 1})

    def test_revocation_tombstone_parsed_without_fetch(self):
        _, _, deleted = self.parse(b'<feed xmlns="http://www.w3.org/2005/Atom" xmlns:at="http://purl.org/atompub/tombstones/1.0"><at:deleted-entry ref="urn:article:a" when="2026-09-11T00:00:00Z"/></feed>')
        self.assertEqual(deleted, ["urn:article:a"])


class FetchSecurityTests(unittest.TestCase):
    def test_private_reserved_and_mapped_ips_rejected(self):
        for address in ("127.0.0.1", "0.0.0.0", "10.2.3.4", "172.16.0.1", "192.168.1.1",
                        "169.254.169.254", "100.64.1.1", "192.0.2.4", "198.18.0.1", "224.0.0.1",
                        "::1", "::", "fc00::1", "fe80::1", "::ffff:127.0.0.1", "2002:7f00:1::", "2001:db8::1"):
            self.assertFalse(public_ip(address), address)
        self.assertTrue(public_ip("8.8.8.8"))
        self.assertTrue(public_ip("2606:4700:4700::1111"))

    def test_configured_feed_urls_only(self):
        for url in ("http://public.example/feed", "https://evil.example/feed", "https://public.example:22/feed",
                    "https://user@public.example/feed", "https://public.example/feed#x", "https://public.example/\r\nX:a"):
            with self.assertRaises(FetchError):
                configured_url(url, SOURCE)

    def test_gzip_normal_and_bomb_limits(self):
        data = rss()
        self.assertEqual(inflate_chunks([gzip.compress(data)], "gzip"), data)
        with self.assertRaises(FetchError):
            inflate_chunks([gzip.compress(b'x' * (MAX_XML_BYTES + 1))], "gzip")

    def test_wire_encoding_truncation_and_deadline_limits(self):
        cases = [([b'x' * (MAX_WIRE_BYTES + 1)], "identity"), ([b'a'], "br"),
                 ([gzip.compress(b'test')[:-4]], "gzip")]
        for chunks, encoding in cases:
            with self.assertRaises(FetchError):
                inflate_chunks(chunks, encoding)
        with self.assertRaises(FetchError):
            inflate_chunks([b'a'], deadline=0)

    def make_fetcher(self, responses, addresses=None):
        calls, dns = [], []
        class Connection:
            sock = None
            def __init__(self, host, address, timeout):
                calls.append((host, address, timeout))
                self.response = responses.pop(0)
            def request(self, method, path, headers):
                calls.append((method, path, dict(headers)))
            def getresponse(self):
                if isinstance(self.response, Exception):
                    raise self.response
                return self.response
            def close(self):
                pass
        def resolver(host, timeout):
            dns.append(host)
            return (addresses.pop(0) if addresses is not None else ["8.8.8.8"])
        return SecureFeedFetcher(resolver, Connection), calls, dns

    def test_pinned_public_ip_host_and_conditional_headers(self):
        fetcher, calls, dns = self.make_fetcher([WireResponse(200)])
        fetcher.fetch(SOURCE, {"If-None-Match": '"v1"', "Authorization": "secret"})
        self.assertEqual(calls[0][:2], ("public.example", "8.8.8.8"))
        self.assertEqual(calls[1][2]["If-None-Match"], '"v1"')
        self.assertNotIn("Authorization", calls[1][2])

    def test_redirect_revalidates_dns_and_blocks_rebinding(self):
        fetcher, calls, dns = self.make_fetcher([WireResponse(302, {"location": "/next"})],
                                               [["8.8.8.8"], ["127.0.0.1"]])
        with self.assertRaises(FetchError):
            fetcher.fetch(SOURCE)
        self.assertEqual(len(dns), 2)
        self.assertEqual(len(calls), 2)

    def test_redirect_to_unapproved_host_or_downgrade_rejected(self):
        for target in ("https://169.254.169.254/", "https://evil.example/", "http://public.example/"):
            fetcher, calls, _ = self.make_fetcher([WireResponse(302, {"location": target})])
            with self.assertRaises(FetchError):
                fetcher.fetch(SOURCE)
            self.assertEqual(len(calls), 2)

    def test_redirect_loop_bounded(self):
        fetcher, calls, _ = self.make_fetcher([WireResponse(302, {"location": "/next"})] * 4)
        with self.assertRaises(FetchError):
            fetcher.fetch(SOURCE)
        self.assertEqual(len(calls), 8)

    def test_mixed_public_private_dns_rejected_before_connection(self):
        fetcher, calls, _ = self.make_fetcher([], [["8.8.8.8", "10.0.0.1"]])
        with self.assertRaises(FetchError):
            fetcher.fetch(SOURCE)
        self.assertFalse(calls)

    def test_quota_timeout_content_type_header_limits(self):
        for value in (WireResponse(429, {"retry-after": "3600"}), TimeoutError(),
                      WireResponse(200, {"content-type": "text/html"}),
                      WireResponse(200, {"x-large": "x" * 40000}),
                      WireResponse(200, {"content-length": str(MAX_WIRE_BYTES + 1)})):
            fetcher, _, _ = self.make_fetcher([value])
            with self.assertRaises(FetchError):
                fetcher.fetch(SOURCE)


class WireResponse:
    def __init__(self, status, headers=None):
        self.status = status
        self.headers = {"content-type": "application/rss+xml"}
        self.headers.update(headers or {})
        self.data = rss()
    def getheaders(self):
        return list(self.headers.items())
    def read(self, _size):
        value, self.data = self.data, b""
        return value


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.store = LocalStore(self.directory.name)
        self.config = {"schemaVersion": 1, "sources": [copy.deepcopy(SOURCE)]}

    def run_ingest(self, values, now=NOW):
        fetcher = FakeFetcher(values)
        result = ingest(self.config, self.store, RssAtomProvider(Allow(), fetcher), now)
        return result, fetcher

    def test_min_refresh_shared_snapshot_not_per_client(self):
        (one, _), fetcher = self.run_ingest([response()])
        (two, report), fetcher = self.run_ingest([], NOW + timedelta(minutes=1))
        self.assertFalse(fetcher.calls)
        self.assertEqual(report[0]["action"], "not-due")
        self.assertEqual(one["items"][0]["fetchedAt"], two["items"][0]["fetchedAt"])

    def test_conditional_304_reuses_content_not_publication_time(self):
        (one, _), _ = self.run_ingest([response()])
        (two, _), fetcher = self.run_ingest([response(status=304)], NOW + timedelta(minutes=30))
        self.assertEqual(fetcher.calls[0][1]["If-None-Match"], '"v1"')
        self.assertEqual(one["items"][0]["publishedAt"], two["items"][0]["publishedAt"])
        self.assertNotEqual(one["items"][0]["fetchedAt"], two["items"][0]["fetchedAt"])

    def test_unconditional_304_does_not_invent_content(self):
        (snapshot, report), _ = self.run_ingest([response(status=304)])
        self.assertFalse(snapshot["items"])
        self.assertEqual(report[0]["action"], "unconditional-304")

    def test_parser_upgrade_waits_until_due_then_reparses_without_validators(self):
        self.run_ingest([response()])
        with patch('wingman_content.provider.NORMALIZATION_VERSION', 999):
            (_, _), fetcher = self.run_ingest([], NOW + timedelta(minutes=1))
            self.assertFalse(fetcher.calls)
            (_, _), fetcher = self.run_ingest([response()], NOW + timedelta(minutes=30))
            self.assertEqual(fetcher.calls[0][1], {})

    def test_offline_keeps_original_dates_then_expires(self):
        (one, _), _ = self.run_ingest([response()])
        (two, _), _ = self.run_ingest([FetchError("transport-error")], NOW + timedelta(minutes=30))
        self.assertEqual(one["items"], two["items"])
        self.assertEqual(two["staleSourceIds"], [SOURCE["id"]])
        (three, _), _ = self.run_ingest([FetchError("transport-error")], NOW + timedelta(days=8))
        self.assertFalse(three["items"])

    def test_invalid_xml_preserves_last_good_source(self):
        (one, _), _ = self.run_ingest([response()])
        (two, report), _ = self.run_ingest([response(b'<rss><broken>')], NOW + timedelta(minutes=30))
        self.assertEqual(one["items"], two["items"])
        self.assertEqual(report[0]["action"], "invalid-feed")

    def test_quota_retry_after_backoff_prevents_retry_storm(self):
        (_, report), fetcher = self.run_ingest([FetchError("http-429", "7200")])
        self.assertEqual(len(fetcher.calls), 1)
        self.assertEqual(report[0]["nextRefreshAt"], iso(NOW + timedelta(hours=2)))
        (_, report), fetcher = self.run_ingest([], NOW + timedelta(minutes=30))
        self.assertFalse(fetcher.calls)

    def test_failed_attempts_have_bounded_exponential_backoff(self):
        now = NOW
        for attempt in range(15):
            (_, report), fetcher = self.run_ingest([FetchError("transport-error")], now)
            self.assertEqual(len(fetcher.calls), 1)
            next_time = date_value(report[0]["nextRefreshAt"])
            self.assertLessEqual((next_time - now).total_seconds(), 21600)
            now = next_time
        self.assertEqual(self.store.read()["states"][SOURCE["id"]]["failures"], 12)

    def test_cache_control_and_http_date_retry_after(self):
        self.assertEqual(delay_seconds({"cache-control": "public, max-age=3600"}, NOW, 1800), 3600)
        self.assertEqual(delay_seconds({"retry-after": "Fri, 11 Sep 2026 23:00:00 GMT"}, NOW, 1800), 10800)
        self.assertEqual(delay_seconds({'retry-after': '172800'}, NOW, 1800), 172800)

    def test_extreme_publisher_hold_suspends_without_early_retry(self):
        self.run_ingest([FetchError('http-429', '9999999999')])
        state = self.store.read()['states'][SOURCE['id']]
        self.assertTrue(state['refreshSuspended'])
        (_, _), fetcher = self.run_ingest([], NOW + timedelta(days=400))
        self.assertFalse(fetcher.calls)

    def test_revocation_limit_halts_sources_with_client_compatible_envelope(self):
        self.run_ingest([response()])
        self.config['sources'][0]['revokedItemIds'] = ['%032x' % number for number in range(5001)]
        (snapshot, _), _ = self.run_ingest([], NOW + timedelta(minutes=1))
        self.assertFalse(snapshot['items'])
        self.assertLessEqual(len(snapshot['revokedItemIds']), 5000)
        self.assertEqual(snapshot['revokedSourceIds'], [SOURCE['id']])
        self.assertTrue(snapshot['recoveryRequired'])

    def test_304_retains_prior_publisher_cache_interval(self):
        self.run_ingest([response(headers={'etag': '"v1"', 'cache-control': 'public, max-age=3600'})])
        (_, report), _ = self.run_ingest([response(status=304, headers={'etag': '"v1"'})], NOW + timedelta(hours=1))
        self.assertEqual(report[0]['nextRefreshAt'], iso(NOW + timedelta(hours=2)))

    def test_no_store_revokes_prior_shared_cached_text(self):
        self.run_ingest([response()])
        (snapshot, report), _ = self.run_ingest([response(headers={'cache-control': 'no-store'})], NOW + timedelta(minutes=30))
        self.assertFalse(snapshot['items'])
        self.assertEqual(report[0]['action'], 'source-cache-prohibited')
        self.assertEqual(snapshot['revokedItemIds'], [item_id('https://public.example/news/a')])

    def test_dedup_url_and_keep_distinct_same_title(self):
        body = rss('<item><title>Same</title><link>https://public.example/news/a?utm_source=x</link></item><item><title>Same</title><link>https://public.example/news/a</link></item><item><title>Same</title><link>https://public.example/news/b</link></item>')
        (snapshot, _), _ = self.run_ingest([response(body)])
        self.assertEqual(len(snapshot["items"]), 2)

    def test_finite_snapshot_at_most_300_items(self):
        body = rss(''.join('<item><title>Science</title><link>https://public.example/news/%d</link></item>' % i for i in range(400)))
        (snapshot, _), _ = self.run_ingest([response(body)])
        self.assertEqual(len(snapshot["items"]), 300)
        self.assertLessEqual(len(encode(snapshot)), 512 * 1024)

    def test_source_disable_revokes_without_network(self):
        self.run_ingest([response()])
        self.config["sources"][0]["enabled"] = False
        (snapshot, _), fetcher = self.run_ingest([], NOW + timedelta(minutes=1))
        self.assertFalse(snapshot["items"])
        self.assertFalse(fetcher.calls)
        self.assertEqual(snapshot["revokedSourceIds"], [SOURCE["id"]])

    def test_removed_source_revoked_and_not_resurrected(self):
        self.run_ingest([response()])
        self.config["sources"] = []
        (snapshot, _), _ = self.run_ingest([], NOW + timedelta(minutes=1))
        self.assertEqual(snapshot["revokedSourceIds"], [SOURCE["id"]])
        self.assertFalse(snapshot["items"])

    def test_item_revocation_applies_offline_and_persists(self):
        (one, _), _ = self.run_ingest([response()])
        self.config["sources"][0]["revokedUrls"] = [one["items"][0]["canonicalUrl"]]
        (two, _), _ = self.run_ingest([], NOW + timedelta(minutes=1))
        self.assertFalse(two["items"])
        self.assertEqual(two["revokedItemIds"], [one["items"][0]["id"]])
        self.config["sources"][0]["revokedUrls"] = []
        (three, _), _ = self.run_ingest([response()], NOW + timedelta(minutes=30))
        self.assertFalse(three["items"])

    def test_updated_promotion_revokes_previously_eligible_item(self):
        self.run_ingest([response()])
        body = rss('<item><title>Sponsored content</title><link>https://public.example/news/a</link><guid>a</guid></item>')
        (snapshot, _), _ = self.run_ingest([response(body)], NOW + timedelta(minutes=30))
        self.assertFalse(snapshot["items"])
        self.assertEqual(snapshot["revokedItemIds"], [item_id('https://public.example/news/a')])

    def test_ordinary_rolling_feed_omission_is_not_a_revocation(self):
        self.run_ingest([response()])
        (snapshot, _), _ = self.run_ingest([response(b'<rss><channel/></rss>')], NOW + timedelta(minutes=30))
        self.assertFalse(snapshot["items"])
        self.assertFalse(snapshot["revokedItemIds"])

    def test_atom_guid_tombstone_revokes_prior_article(self):
        self.run_ingest([response()])
        body = b'<feed xmlns="http://www.w3.org/2005/Atom" xmlns:at="http://purl.org/atompub/tombstones/1.0"><at:deleted-entry ref="a" when="2026-09-11T20:00:00Z"/></feed>'
        (snapshot, _), _ = self.run_ingest([response(body)], NOW + timedelta(minutes=30))
        self.assertEqual(snapshot["revokedItemIds"], [item_id("https://public.example/news/a")])

    def test_changed_rights_reduce_cached_payload(self):
        self.run_ingest([response()])
        self.config["sources"][0]["rights"]["excerpts"] = False
        (snapshot, _), _ = self.run_ingest([], NOW + timedelta(minutes=1))
        self.assertNotIn("excerpt", snapshot["items"][0])
        self.assertFalse(snapshot["items"][0]["rights"]["excerpt"])

    def test_atomic_write_failure_preserves_generation(self):
        self.run_ingest([response()])
        original = self.store.path.read_bytes()
        with patch('wingman_content.store.os.replace', side_effect=OSError("disk failure")):
            with self.assertRaises(OSError):
                self.store.write({"snapshot": "incomplete"})
        self.assertEqual(self.store.path.read_bytes(), original)
        self.assertEqual(list(Path(self.directory.name).glob('.pending-*')), [])

    def test_old_publication_excluded_without_rewriting_date(self):
        body = rss('<item><title>Old science</title><link>https://public.example/news/old</link><pubDate>Fri, 11 Sep 2020 18:00:00 GMT</pubDate></item>')
        (snapshot, _), _ = self.run_ingest([response(body)])
        self.assertFalse(snapshot["items"])


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.store = LocalStore(self.directory.name)
        ingest({"schemaVersion": 1, "sources": [SOURCE]}, self.store,
               RssAtomProvider(Allow(), FakeFetcher([response()])), NOW)
        self.server = BoundedServer(('127.0.0.1', 0), handler_for(self.store))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.directory.cleanup()

    def request(self, path, method="GET", headers=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=2)
        connection.request(method, path, headers=headers or {})
        result = connection.getresponse()
        status, headers, body = result.status, dict(result.getheaders()), result.read()
        connection.close()
        return status, headers, body

    def test_common_get_and_etag_304_never_ingest(self):
        before = self.store.path.read_bytes()
        status, headers, body = self.request('/v1/snapshot.json')
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["items"][0]["sourceId"], SOURCE["id"])
        status, _, body = self.request('/v1/snapshot.json', headers={"If-None-Match": headers["ETag"]})
        self.assertEqual((status, body), (304, b''))
        self.assertEqual(self.store.path.read_bytes(), before)

    def test_no_proxy_refresh_or_profile_endpoints(self):
        for path in ('/v1/snapshot.json?url=https://private.example', '/refresh', '/v1/snapshot.json?topics=science', '/current.json'):
            self.assertEqual(self.request(path)[0], 404)
        self.assertEqual(self.request('/v1/snapshot.json', method='POST')[0], 405)

    def test_conditional_get_browser_cors_preflight(self):
        status, headers, _ = self.request('/v1/snapshot.json', method='OPTIONS', headers={
            'Origin': 'https://wingman.example', 'Access-Control-Request-Method': 'GET',
            'Access-Control-Request-Headers': 'if-none-match,if-modified-since'})
        self.assertEqual(status, 204)
        self.assertEqual(headers['Access-Control-Allow-Origin'], '*')
        self.assertEqual(headers['Access-Control-Allow-Methods'], 'GET, OPTIONS')
        self.assertIn('If-None-Match', headers['Access-Control-Allow-Headers'])
        self.assertNotIn('Access-Control-Allow-Credentials', headers)
        self.assertNotIn('Authorization', headers['Access-Control-Allow-Headers'])
        self.assertEqual(self.request('/refresh', method='OPTIONS')[0], 404)

    def test_request_headers_bounded_before_full_parse(self):
        status, _, _ = self.request('/v1/snapshot.json', headers={'X-Large': 'x' * 33000})
        self.assertEqual(status, 431)


class ConfigurationTests(unittest.TestCase):
    def test_reviewed_registry_matches_generated_app_asset(self):
        config = load_config(ROOT / 'backend/sources.json')
        self.assertEqual(registry(config), json.loads((ROOT / 'assets/live_content/sources.json').read_text()))
        self.assertEqual({source["id"] for source in config["sources"]}, {
            "nasa-technology", "noaa-news", "usgs-news", "globalvoices-sports",
            "globalvoices-fashion", "globalvoices-food", "globalvoices-health",
            "globalvoices-science", "globalvoices-technology", "globalvoices-business",
            "globalvoices-entertainment", "globalvoices-headlines",
        })
        self.assertEqual({topic for source in config["sources"] for topic in source["topics"]}, {
            "sports", "fashion", "food", "health", "science", "technology",
            "business", "entertainment", "headlines", "environment",
        })

    def test_real_pinned_baseline_loaded_and_mandatory_fixture_denied(self):
        policy = DestinationPolicy(ROOT / 'assets/policy/consumer_protection.json')
        self.assertTrue(policy.allows('https://www.nasa.gov/technology/'))
        data = json.loads((ROOT / 'assets/policy/consumer_protection.json').read_text())
        for category, domains in data['categories'].items():
            self.assertFalse(policy.allows('https://' + domains[0] + '/'), category)

    def test_baseline_integrity_fail_closed(self):
        with tempfile.NamedTemporaryFile() as stream:
            stream.write(b'{"categories":{}}')
            stream.flush()
            with self.assertRaises(ValueError):
                DestinationPolicy(stream.name)


if __name__ == '__main__':
    unittest.main()
