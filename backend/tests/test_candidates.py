import copy
import csv
import io
import hashlib
import json
import tempfile
import threading
import time
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from wingman_content.candidates import (BOOLEAN_COLUMNS, EXPECTED_CATEGORIES, REQUIRED_COLUMNS,
    atomic_json, build_report, checked_compatibility, identity, import_csv, promotion_patch, read_json, report_markdown)
from wingman_content.candidate_probe import inspect_feed, probe, run_validation
from wingman_content.fetch import FetchError, FetchResult

ROOT = Path(__file__).resolve().parents[2]
NOW = datetime(2026, 9, 15, 20, tzinfo=timezone.utc)


def fixture_csv(count=3, duplicate=False):
    columns = sorted(REQUIRED_COLUMNS | {"unanticipated_research_field"})
    out = io.StringIO(newline="")
    writer = csv.DictWriter(out, columns)
    writer.writeheader()
    for index in range(count):
        row = {key: "" for key in columns}
        row.update({key: "False" for key in BOOLEAN_COLUMNS})
        row.update(record_id="WM-%04d" % index, publisher="Brand %d" % index,
                   category="Sports" if index % 2 else "Science",
                   feed_url="https://host%d.example/feed" % (0 if duplicate else index),
                   unanticipated_research_field='Quoted, research "value"\ncontinued')
        writer.writerow(row)
    return out.getvalue().encode()


def inventory(count=3, duplicate=False):
    return import_csv(fixture_csv(count, duplicate), expected=False, checked_at="2026-09-15T20:00:00Z")


def rss(items=None):
    return ('<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel>' + (items or
      '<item><title>Original title</title><link>https://publisher.example/story</link>'
      '<description>&lt;p&gt;Publisher summary&lt;img src="https://images.example/a.jpg"/&gt;&lt;/p&gt;</description>'
      '<pubDate>Tue, 15 Sep 2026 10:00:00 GMT</pubDate><media:thumbnail url="https://images.example/a.jpg" width="90" height="90"/></item>') + '</channel></rss>').encode()


def success(source, validators):
    return FetchResult(200, {"etag": '"v1"'}, rss()), [{"url": source["feedUrl"], "status": 200}], None


class ImportTests(unittest.TestCase):
    def test_supplied_inventory_counts_columns_and_false_values(self):
        data = (ROOT / "backend/candidate_data/wingman_feed_candidates.csv").read_bytes()
        imported = import_csv(data)
        self.assertEqual(imported["counts"], {"records": 217, "publishers": 201,
                        "literalFeedUrls": 216, "categories": EXPECTED_CATEGORIES})
        self.assertEqual(len(imported["columns"]), 29)
        for row in imported["records"]:
            for field in ("production_enabled", "image_display_enabled", "all_criteria_verified"):
                self.assertIs(row["parsedBooleans"][field], False)
                self.assertEqual(row["raw"][field], "False")

    def test_raw_metadata_brand_identity_and_duplicate_endpoint_preserved(self):
        result = inventory(3, True)
        self.assertEqual(len(result["publishers"]), 3)
        self.assertEqual(len(result["endpoints"]), 1)
        self.assertEqual(len(result["endpoints"][0]["recordIds"]), 3)
        self.assertEqual(result["records"][0]["raw"]["unanticipated_research_field"],
                         'Quoted, research "value"\ncontinued')

    def test_unknown_boolean_fails_closed_without_changing_raw_research(self):
        data = fixture_csv(1).replace(b"False", b"unsure", 1)
        row = import_csv(data, expected=False)["records"][0]
        self.assertIn(None, row["parsedBooleans"].values())
        self.assertTrue(row["importIssues"])
        self.assertIn("unsure", row["raw"].values())

    def test_malformed_csv_and_changed_expected_counts_rejected(self):
        for data in (b"a,b\n1,2\n", fixture_csv(1).replace(b"WM-0000", b"bad/id"),
                     fixture_csv(1) + b"extra,column\n"):
            with self.assertRaises(ValueError):
                import_csv(data, expected=False)
        with self.assertRaises(ValueError):
            import_csv(fixture_csv(1))

    def test_idempotent_import_and_exact_reconciliation_never_domain_inheritance(self):
        data = fixture_csv(2)
        approved = {"sources": [{"id": "approved", "feedUrl": "https://host0.example/feed"},
                                {"id": "same-host-unrelated", "feedUrl": "https://host1.example/other"}]}
        first = import_csv(data, approved=approved, expected=False)
        second = import_csv(data, prior=first, approved=approved, expected=False)
        self.assertEqual(first, second)
        self.assertEqual(first["endpoints"][0]["existingExactSourceIds"], ["approved"])
        self.assertEqual(first["endpoints"][1]["existingExactSourceIds"], [])
        decisions = {"schemaVersion": 1, "decisions": [{"reviewId": "keep-explicit-denial"}]}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "reviews.json"
            atomic_json(path, decisions)
            atomic_json(Path(directory) / "candidates.json", second)
            self.assertEqual(read_json(path), decisions)


class ProbeTests(unittest.TestCase):
    def check(self, fetch=success, prior=None):
        data = inventory(1)
        return probe(data["endpoints"][0], data, {}, prior or {}, fetch=fetch, clock=lambda: NOW)

    def test_actual_format_and_coverage_not_http_status_alone(self):
        result = self.check()
        self.assertEqual(result["status"], "working")
        self.assertEqual(result["format"], "rss-2")
        self.assertEqual(result["checkedAt"], "2026-09-15T20:00:00Z")
        self.assertEqual(result["coverage"]["itemsWithImageCandidates"], 1)
        self.assertEqual(result["coverage"]["itemsWithExcerpts"], 1)
        self.assertNotIn("Original title", json.dumps(result))
        self.assertNotIn("Publisher summary", json.dumps(result))

    def test_atom_published_not_updated_branding_not_article_and_alternate_link(self):
        body = b'<feed xmlns="http://www.w3.org/2005/Atom"><logo>https://publisher.example/logo.png</logo><entry><title>Title</title><link href="javascript:bad"/><link href="https://publisher.example/a"/><summary>Summary</summary><updated>2026-09-15T20:00:00Z</updated></entry></feed>'
        kind, coverage = inspect_feed(body, NOW)
        self.assertEqual(kind, "atom-1")
        self.assertEqual(coverage["itemsWithLinks"], 1)
        self.assertEqual(coverage["itemsWithUpdatedDates"], 1)
        self.assertEqual(coverage["missingPublishedDates"], 1)
        self.assertIsNone(coverage["newestPublishedAt"])
        self.assertEqual(coverage["brandingCandidates"], 1)
        self.assertEqual(coverage["itemsWithImageCandidates"], 0)

    def test_entities_excess_depth_entries_and_bad_xml_fail(self):
        for body in (b'<!DOCTYPE rss [<!ENTITY x SYSTEM "file:///tmp/private">]><rss>&x;</rss>',
                     rss('<item/>' * 501), b'<rss><', b'<rss>' + b'<x>' * 34 + b'</x>' * 34 + b'</rss>'):
            with self.assertRaises(Exception):
                inspect_feed(body, NOW)

    def test_stale_missing_invalid_future_dates_are_distinct(self):
        _, counts = inspect_feed(rss('<item><title>A</title><link>https://example.org/a</link><pubDate>2026-02-31T00:00:00Z</pubDate></item><item><title>B</title><pubDate>2030-01-01T00:00:00Z</pubDate></item>'), NOW)
        self.assertEqual(counts["invalidPublishedDates"], 1)
        self.assertEqual(counts["futurePublishedDates"], 1)
        self.assertIsNone(counts["newestPublishedAt"])
        result = self.check(lambda s, v: (FetchResult(200, {}, rss().replace(b"15 Sep 2026", b"15 Sep 2020")), [], None))
        self.assertEqual(result["status"], "stale")

    def test_http_access_html_timeout_and_retry_after_are_precise(self):
        cases = [("http-403", "access-restricted"), ("http-401", "access-restricted"),
                 ("http-429", "rate-limited"), ("dns-timeout", "unreachable"),
                 ("unconfigured-feed-destination", "review-needed")]
        for reason, status in cases:
            result = self.check(lambda s, v: (None, [], FetchError(reason, "172800")))
            self.assertEqual(result["status"], status)
            self.assertEqual(result["nextCheckAt"], "2026-09-17T20:00:00Z")
        result = self.check(lambda s, v: (None, [{"url": s['feedUrl'], "status": 200, "contentType": "text/html"}], FetchError("unexpected-content-type")))
        self.assertEqual(result["status"], "html-login-challenge-response")

    def test_conditional_revalidation_keeps_publisher_dates(self):
        prior = self.check()
        def not_modified(source, validators):
            self.assertEqual(validators, {"If-None-Match": '"v1"'})
            return FetchResult(304, {"cache-control": "max-age=3600"}, b""), [], None
        current = self.check(not_modified, prior)
        self.assertEqual(current["coverage"], prior["coverage"])
        self.assertEqual(current["nextCheckAt"], "2026-09-15T21:00:00Z")
        self.assertEqual(self.check(lambda s, v: (FetchResult(304, {}, b""), [], None))["status"], "malformed")

    def test_http_is_held_without_network_and_correction_needs_evidence(self):
        data = import_csv(fixture_csv(1).replace(b"https://host0", b"http://host0"), expected=False)
        def never(*args):
            self.fail("Insecure candidate must not reach network")
        result = probe(data["endpoints"][0], data, {}, {}, fetch=never, clock=lambda: NOW)
        self.assertEqual(result["reason"], "https-endpoint-evidence-required")


class SchedulerTests(unittest.TestCase):
    def test_duplicate_endpoints_once_and_due_resume_no_refresh_storm(self):
        data = inventory(3, True)
        calls = []
        def fake(endpoint, inventory, reviews, prior, clock):
            calls.append(endpoint['id'])
            return probe(endpoint, inventory, reviews, prior, fetch=success, clock=clock)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            state, first = run_validation(data, None, path, probe_function=fake, clock=lambda: NOW)
            _, second = run_validation(data, state, path, probe_function=fake, clock=lambda: NOW)
            self.assertEqual(len(calls), 1)
            self.assertEqual(first['attemptedEndpoints'], 1)
            self.assertEqual(second['attemptedEndpoints'], 0)
            self.assertEqual(build_report(data, state)['totals']['checkedRows'], 3)

    def test_cursor_fairness_bounded_parallelism_and_preflight_durable_hold(self):
        data = inventory(7)
        active = 0
        maximum = 0
        mutex = threading.Lock()
        calls = []
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            def fake(endpoint, inventory, reviews, prior, clock):
                nonlocal active, maximum
                with mutex:
                    active += 1
                    maximum = max(maximum, active)
                    calls.append(endpoint['id'])
                pending = read_json(path)['endpoints'][endpoint['id']]
                self.assertTrue(pending['inFlight'])
                self.assertEqual(pending['nextCheckAt'], '2026-09-15T20:30:00Z')
                time.sleep(.01)
                with mutex:
                    active -= 1
                return probe(endpoint, inventory, reviews, prior, fetch=success, clock=clock)
            state = None
            for _ in range(3):
                state, _ = run_validation(data, state, path, batch_size=3, concurrency=2,
                                          probe_function=fake, clock=lambda: NOW)
            self.assertEqual(len(calls), 7)
            self.assertEqual(len(set(calls)), 7)
            self.assertLessEqual(maximum, 2)
            self.assertEqual(build_report(data, state)['uniqueEndpointChecks']['checked'], 7)

    def test_malformed_pacing_does_not_reset(self):
        data = inventory(1)
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                run_validation(data, {'schemaVersion': 1, 'cursor': 0, 'endpoints': {
                    data['endpoints'][0]['id']: {'nextCheckAt': 'bad'}}}, Path(directory)/'s.json')


class PromotionTests(unittest.TestCase):
    def test_exact_review_and_separate_rights_required_never_mutates_config(self):
        data = inventory(1)
        record = data['records'][0]
        checked = probe(data['endpoints'][0], data, {}, {}, fetch=success, clock=lambda: NOW)
        state = {'endpoints': {record['endpointId']: checked}}
        grant = {'status': 'approved', 'scope': 'exact RSS app cards', 'evidenceUrls': ['https://host0.example/terms']}
        decision = {'reviewId': 'review-1', 'recordIds': [record['recordId']], 'feedUrl': record['raw']['feed_url'],
                    'reviewedAt': '2026-09-15T19:00:00Z', 'productionEnabled': True,
                    'contentPolicy': {'status': 'approved'}, 'permissions': {name: grant for name in (
                        'headlineLink', 'excerpt', 'articleImages', 'storageRedistribution')},
                    'sourceConfig': {'id': 'new-reviewed', 'feedUrl': record['raw']['feed_url'], 'enabled': True,
                                     'rights': {'images': True, 'excerpts': True}}}
        approved = {'sources': []}
        reviews = {'decisions': [decision]}
        patch = promotion_patch(data, state, reviews, record['recordId'], 'review-1', approved, NOW)
        self.assertEqual(patch['action'], 'add-reviewed-source')
        self.assertEqual(approved, {'sources': []})
        for change in ({'feedUrl': 'https://host0.example/other'}, {'productionEnabled': 'True'},
                       {'expiresAt': '2026-09-14T00:00:00Z'}, {'permissions': {'headlineLink': grant}}):
            altered = {'decisions': [dict(decision, **change)]}
            with self.assertRaises(ValueError):
                promotion_patch(data, state, altered, record['recordId'], 'review-1', approved, NOW)
        unchanged = promotion_patch(data, state, reviews, record['recordId'], 'review-1', {'sources': [decision['sourceConfig']]}, NOW)
        self.assertEqual(unchanged['action'], 'already-reviewed-source')
        with self.assertRaises(ValueError):
            promotion_patch(data, state, reviews, record['recordId'], 'review-1',
                            {'sources': [dict(decision['sourceConfig'], id='other-brand')]}, NOW)

    def test_compatibility_receipt_requires_exact_pinned_feed_bytes_and_image_association(self):
        url = 'https://science.nasa.gov/feed/photojournal/latest-content/'
        image = {'url': 'https://images.example/reviewed.jpg', 'credit': 'NASA/JPL'}
        source = {'id': 'nasa-photojournal', 'feedUrl': url,
                  'feedCompatibility': 'nasa-photojournal-self-link-v1',
                  'imagePolicy': {'reviewedArticles': {'https://science.nasa.gov/photojournal/a/': image}}}
        original_link = b'<atom:link href="https://science.nasa.gov/feed/?post_type=post&cat=19797&science_org=19791" rel="self" type="application/rss+xml"/>'
        raw = b'<rss xmlns:atom="http://www.w3.org/2005/Atom"><channel>' + original_link + b'<item><title>A</title><link>https://science.nasa.gov/photojournal/a/</link></item></channel></rss>'
        original_hash = hashlib.sha256(raw).hexdigest()
        normalized_hash = hashlib.sha256(raw.replace(original_link, original_link.replace(b'&', b'&amp;'))).hexdigest()
        check = {'status': 'malformed', 'requestUrl': url, 'rawSha256': original_hash,
                 'checkedAt': '2026-09-15T19:00:00Z'}
        receipt = {'sourceId': 'nasa-photojournal', 'feedUrl': url,
                   'compatibilityVersion': 'nasa-photojournal-self-link-v1',
                   'checkedAt': '2026-09-15T19:10:00Z', 'strictNormalizedParse': True,
                   'originalSha256': original_hash, 'normalizedSha256': normalized_hash,
                   'normalizedItems': 1, 'imageEligible': [
                       {'canonicalUrl': 'https://science.nasa.gov/photojournal/a/', 'image': image}]}
        self.assertEqual(checked_compatibility({'compatibilityValidation': receipt}, source, check, NOW, raw), receipt)
        with self.assertRaises(ValueError):
            checked_compatibility({'compatibilityValidation': receipt}, source, check, NOW)
        for change in ({'originalSha256': 'c' * 64}, {'sourceId': 'nasa-other'},
                       {'feedUrl': 'https://science.nasa.gov/other/'}, {'strictNormalizedParse': 'true'},
                       {'compatibilityVersion': 'generic-xml-fix'}, {'normalizedItems': True},
                       {'checkedAt': '2030-01-01T00:00:00Z'}, {'imageEligible': []},
                       {'imageEligible': [{'canonicalUrl': 'https://science.nasa.gov/photojournal/b/', 'image': image}]}):
            with self.assertRaises(ValueError):
                checked_compatibility({'compatibilityValidation': dict(receipt, **change)}, source, check, NOW, raw)

    def test_report_escapes_candidate_markdown_instead_of_loading_remote_images(self):
        data = inventory(1)
        data['records'][0]['raw']['publisher'] = '![untrusted](https://tracker.example/pixel)'
        rendered = report_markdown(build_report(data))
        self.assertNotIn('![untrusted](', rendered)
        self.assertIn(r'\!\[untrusted\]\(', rendered)

    def test_report_accounts_for_every_row_without_claiming_visible_cards(self):
        data = inventory(4, True)
        report = build_report(data)
        self.assertEqual(len(report['records']), 4)
        self.assertEqual(report['uniqueEndpointChecks']['statuses'], {'not-yet-checked': 1})
        self.assertEqual(report['totals']['heldRows'], 4)
        self.assertTrue(all(row['visibleStoryCount'] is None for row in report['records']))
        self.assertIn('WM-0003', report_markdown(report))


if __name__ == '__main__':
    unittest.main()
