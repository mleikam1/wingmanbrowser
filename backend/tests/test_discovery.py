"""Synthetic public-publisher fixtures; no live feed or network requests."""
import copy
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from html import escape

from wingman_content.fetch import FetchResult
from wingman_content.normalize import canonical_url, item_id, parse_feed
from wingman_content.provider import RssAtomProvider, ingest
from wingman_content.store import LocalStore


NOW = datetime(2026, 9, 13, 22, tzinfo=timezone.utc)
ARTICLE = "https://publisher.example/2026/09/04/fixture-story/"
SOURCE = {
    "id": "fixture-fashion", "name": "Fixture publisher · Fashion",
    "homepageUrl": "https://publisher.example/",
    "feedUrl": "https://publisher.example/feed/?s=fashion",
    "feedRedirectHosts": ["publisher.example"],
    "allowedArticleHosts": ["publisher.example"],
    "articlePathPrefixes": ["/"], "articleUrlFormat": "dated-story",
    "language": "en", "topics": ["fashion"],
    "eligibilityScope": "lifestyle-education", "requiresAttribution": True,
    "requiredTopicTerms": ["fashion designer", "garment", "garments"],
    "rights": {"titles": True, "excerpts": True, "images": False,
               "attribution": "Fixture author and publisher credit",
               "licenseUrl": "https://publisher.example/reuse"},
    "enabled": True, "verifiedAt": "2026-09-13T00:00:00Z",
    "minRefreshSeconds": 1800, "retentionSeconds": 604800,
    "revokedItemIds": [], "revokedUrls": [],
}


class AllowDestination:
    def allows(self, _url):
        return True


def feed(title, description="Independent reporting.", author="Fixture Writer",
         url=ARTICLE):
    credit = "<dc:creator>" + escape(author) + "</dc:creator>" if author else ""
    return ("<rss version='2.0' xmlns:dc='http://purl.org/dc/elements/1.1/'>"
            "<channel><item><title>" + escape(title) + "</title><link>" +
            escape(url) + "</link><description>" + escape(description) +
            "</description>" + credit + "<guid>fixture-story-guid</guid>"
            "<pubDate>Fri, 04 Sep 2026 12:00:00 GMT</pubDate>"
            "</item></channel></rss>").encode()


class FixtureFetcher:
    def __init__(self, *bodies):
        self.bodies = list(bodies)
        self.calls = []

    def fetch(self, source, _validators):
        self.calls.append(source["id"])
        return FetchResult(200, {}, self.bodies.pop(0))


class DiscoveryNormalizationTests(unittest.TestCase):
    def parse(self, data):
        return parse_feed(data, SOURCE, NOW, AllowDestination())

    def test_fashion_designer_and_garment_reporting_keep_author_and_date(self):
        for title in ("A fashion designer rebuilds her workshop",
                      "Garment workers secure expanded childcare"):
            with self.subTest(title=title):
                items, held, deleted = self.parse(feed(title, author="A & B"))
                self.assertEqual(len(items), 1)
                self.assertEqual(items[0]["topics"], ["fashion"])
                self.assertEqual(items[0]["attribution"], "A & B")
                self.assertEqual(items[0]["publishedAt"], "2026-09-04T12:00:00Z")
                self.assertIsNone(items[0]["image"])
                self.assertEqual(held["count"], 0)
                self.assertEqual(deleted, [])

    def test_incidental_fashion_phrase_is_local_hold_not_revocation(self):
        items, held, deleted = self.parse(feed(
            "Football team wins regional final", "The team won in dramatic fashion."))
        self.assertEqual(items, [])
        self.assertEqual(held["reasons"], {"outside-topic-scope": 1})
        self.assertEqual(deleted, [])

    def test_required_author_missing_holds_article_and_revokes_cached_identity(self):
        items, held, deleted = self.parse(feed("A fashion designer opens a workshop", author=None))
        self.assertEqual(items, [])
        self.assertEqual(held["reasons"], {"missing-author": 1})
        self.assertIn(ARTICLE, deleted)
        self.assertIn("fixture-story-guid", deleted)

    def test_rights_and_promotion_failure_take_priority_over_topic_mismatch(self):
        for notice in ("Copyright 2026 Other Publisher. All rights reserved.",
                       "Paid partnership. Buy now.", "© 2026 Other Publisher"):
            with self.subTest(notice=notice):
                items, held, deleted = self.parse(feed("Football team wins", notice))
                self.assertEqual(items, [])
                self.assertEqual(held["reasons"], {"promotion-or-rights-ambiguity": 1})
                self.assertIn(ARTICLE, deleted)

    def test_dated_story_scope_accepts_articles_and_rejects_feeds_shops_and_aliases(self):
        for path in ("/2026/09/04/story/", "/2027/01/01/future-year-story"):
            url = "https://publisher.example" + path
            self.assertEqual(canonical_url(url, SOURCE), url)
        for url in ("https://publisher.example/", "https://publisher.example/feed/",
                    "https://publisher.example/-/topics/sport/",
                    "https://publisher.example/shop/2026/09/04/story/",
                    "https://publisher.example/2026/09/04/story/extra/",
                    "https://publisher.example/2026/09/04/%2e%2e/",
                    "https://publisher.example/2026/09/04/../shop/",
                    "https://publisher.example.evil/2026/09/04/story/"):
            with self.subTest(url=url):
                self.assertIsNone(canonical_url(url, SOURCE))
                items, held, _ = self.parse(feed("Fashion designer", url=url))
                self.assertEqual(items, [])
                self.assertEqual(held["reasons"], {"unreviewed-destination": 1})


class DiscoveryCrossFeedTests(unittest.TestCase):
    def test_fashion_mismatch_does_not_remove_same_sports_article_across_refreshes(self):
        sports = copy.deepcopy(SOURCE)
        sports.update(id="fixture-sports", name="Fixture publisher · Sports",
                      topics=["sports"], eligibilityScope="sports-reporting",
                      requiredTopicTerms=[], feedUrl="https://publisher.example/sports/feed/")
        body = feed("Football team reaches final", "The team won in dramatic fashion.")
        fetcher = FixtureFetcher(body, body, body, body)
        provider = RssAtomProvider(AllowDestination(), fetcher)
        config = {"schemaVersion": 1, "sources": [sports, copy.deepcopy(SOURCE)]}
        with tempfile.TemporaryDirectory() as directory:
            store = LocalStore(directory)
            for now in (NOW, NOW + timedelta(seconds=1801)):
                snapshot, report = ingest(config, store, provider, now)
                self.assertEqual(len(snapshot["items"]), 1)
                self.assertEqual(snapshot["items"][0]["sourceId"], "fixture-sports")
                self.assertEqual(snapshot["items"][0]["topics"], ["sports"])
                self.assertEqual(snapshot["revokedItemIds"], [])
                self.assertEqual(report[1]["heldReasons"], {"outside-topic-scope": 1})
                self.assertEqual(store.read()["states"]["fixture-fashion"]["revokedItemIds"], [])
        self.assertEqual(fetcher.calls, ["fixture-sports", "fixture-fashion"] * 2)

    def test_real_rights_withdrawal_still_removes_previously_cached_article(self):
        allowed = feed("Fashion designer opens a workshop")
        withdrawn = feed("Football team wins", "Copyright 2026 Other Publisher.")
        provider = RssAtomProvider(AllowDestination(), FixtureFetcher(allowed, withdrawn))
        config = {"schemaVersion": 1, "sources": [copy.deepcopy(SOURCE)]}
        with tempfile.TemporaryDirectory() as directory:
            store = LocalStore(directory)
            initial, _ = ingest(config, store, provider, NOW)
            self.assertEqual(len(initial["items"]), 1)
            updated, report = ingest(config, store, provider, NOW + timedelta(seconds=1801))
            self.assertEqual(updated["items"], [])
            self.assertEqual(updated["revokedItemIds"], [item_id(ARTICLE)])
            self.assertEqual(report[0]["heldReasons"], {"promotion-or-rights-ambiguity": 1})


if __name__ == "__main__":
    unittest.main()
