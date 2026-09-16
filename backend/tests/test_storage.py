"""Cloud adapter contract exercised without credentials or live cloud resources."""
import json
import sys
import types
import tempfile
import unittest
from unittest.mock import patch
from wingman_content.store import (GCSStore, LocalStore, MAX_BUNDLE_BYTES,
                                   WRITER_LEASE_SECONDS, WriterLeaseError)


class NotFound(Exception):
    pass


class PreconditionFailed(Exception):
    code = 412


class Blob:
    def __init__(self):
        self.generation, self.size = 7, 2
        self.data = b'{}'
        self.calls = []
        self.exists = True

    def reload(self, **kwargs):
        self.calls.append(('reload', kwargs))
        if not self.exists:
            raise NotFound()

    def download_as_bytes(self, **kwargs):
        self.calls.append(('download', kwargs))
        if kwargs['if_generation_match'] != self.generation:
            raise PreconditionFailed()
        return self.data

    def upload_from_string(self, data, **kwargs):
        self.calls.append(('upload', kwargs))
        actual = self.generation if self.exists else 0
        if kwargs['if_generation_match'] != actual:
            raise PreconditionFailed()
        self.data, self.size = data, len(data)
        self.exists = True
        self.generation = actual + 1


class CloudStoreTests(unittest.TestCase):
    def setUp(self):
        self.blob = Blob()
        self.store = GCSStore.__new__(GCSStore)
        self.store.blob, self.store.generation = self.blob, 0
        self.exceptions = types.ModuleType('google.api_core.exceptions')
        self.exceptions.NotFound = NotFound
        self.modules = patch.dict(sys.modules, {'google.api_core.exceptions': self.exceptions})
        self.modules.start()
        self.addCleanup(self.modules.stop)

    def test_requires_explicit_project_before_loading_cloud_sdk(self):
        with self.assertRaises(ValueError):
            GCSStore('some-bucket')

    def test_reads_pinned_generation_and_bounded_calls(self):
        self.assertEqual(self.store.read(), {})
        self.assertEqual(self.store.generation, 7)
        self.assertEqual(self.blob.calls[1][1]['if_generation_match'], 7)
        for _, kwargs in self.blob.calls:
            self.assertIsNone(kwargs['retry'])
            self.assertEqual(kwargs['timeout'], 10)

    def test_concurrent_job_cannot_overwrite_newer_generation(self):
        self.store.read()
        self.blob.generation = 8
        self.blob.data = b'{"newer":true}'
        with self.assertRaises(PreconditionFailed):
            self.store.write({'old': True})
        self.assertEqual(json.loads(self.blob.data), {'newer': True})

    def test_initial_create_uses_zero_precondition(self):
        self.blob.exists = False
        self.assertIsNone(self.store.read())
        self.store.write({'snapshot': {'schemaVersion': 1}})
        self.assertEqual(self.blob.calls[-1][1]['if_generation_match'], 0)
        self.assertEqual(self.blob.calls[-1][1]['timeout'], 20)
        self.assertIsNone(self.blob.calls[-1][1]['retry'])

    def test_oversize_remote_object_is_not_downloaded(self):
        self.blob.size = MAX_BUNDLE_BYTES + 1
        with self.assertRaises(ValueError):
            self.store.read()
        self.assertEqual(len(self.blob.calls), 1)


class SharedWriterTests(unittest.TestCase):
    def setUp(self):
        self.objects = {}
        objects = self.objects
        class Bucket:
            def blob(self, name):
                if name not in objects:
                    objects[name] = Blob()
                    if name == 'lease':
                        objects[name].exists = False
                return objects[name]
        self.bucket = Bucket()
        self.exceptions = types.ModuleType('google.api_core.exceptions')
        self.exceptions.NotFound = NotFound
        self.modules = patch.dict(sys.modules, {'google.api_core.exceptions': self.exceptions})
        self.modules.start()
        self.addCleanup(self.modules.stop)

    def store(self):
        store = GCSStore.__new__(GCSStore)
        store.bucket, store.blob = self.bucket, self.bucket.blob('content')
        store.writer_object, store.generation, store._active_writer = 'lease', 0, None
        return store

    def test_writer_serializes_read_through_publication_before_any_provider_request(self):
        first, second = self.store(), self.store()
        with first.writer():
            self.assertEqual(first.generation, 8)  # Content generation was fenced.
            with self.assertRaisesRegex(WriterLeaseError, 'content-writer-busy'):
                with second.writer():
                    self.fail('Overlapping ingestion must not start')
            first.write({'states': {'completed': True}, 'snapshot': {'items': []}})
        with second.writer():
            self.assertEqual(second.read()['states'], {'completed': True})

    def test_expired_writer_cannot_publish_even_before_successor_finishes(self):
        first, second = self.store(), self.store()
        with patch('wingman_content.store.time.time', return_value=1000):
            initial = first.writer()
            check_first = initial.__enter__()
        try:
            with patch('wingman_content.store.time.time', return_value=1001 + WRITER_LEASE_SECONDS):
                with second.writer():
                    with self.assertRaisesRegex(WriterLeaseError, 'content-writer-lost'):
                        check_first()
                    # Simulate an old process paused after its final lease check.
                    # The new writer's content-generation bump still fences it.
                    first._active_writer = None
                    with self.assertRaises(PreconditionFailed):
                        first.write({'stale': True})
                    second.write({'snapshot': {'items': []}, 'fresh': True})
        finally:
            initial.__exit__(None, None, None)
        self.assertTrue(second.read()['fresh'])

    def test_lease_renews_only_while_owned_and_release_preserves_successor(self):
        first = self.store()
        with patch('wingman_content.store.time.time', return_value=1000):
            context = first.writer()
            guard = context.__enter__()
        try:
            with patch('wingman_content.store.time.time', return_value=1700):
                guard()
                lease = json.loads(self.objects['lease'].data)
                self.assertEqual(lease['expiresAt'], 1700 + WRITER_LEASE_SECONDS)
            lease['token'] = 'f' * 32
            self.objects['lease'].data = json.dumps(lease).encode()
            with self.assertRaisesRegex(WriterLeaseError, 'content-writer-lost'):
                guard()
        finally:
            context.__exit__(None, None, None)
        self.assertEqual(json.loads(self.objects['lease'].data)['expiresAt'], 2900)

    def test_corrupt_or_unavailable_lease_stops_before_provider_work(self):
        store = self.store()
        blob = self.bucket.blob('lease')
        blob.exists, blob.data = True, b'not-json'
        with self.assertRaises(WriterLeaseError):
            with store.writer():
                self.fail('Corrupt lease must prevent ingestion')
        self.assertEqual(self.objects['content'].generation, 7)

    def test_lost_lease_during_provider_refresh_stops_before_next_provider(self):
        from wingman_content.provider import ingest
        from test_content import SOURCE, NOW
        store = self.store()
        calls = []
        class Provider:
            def refresh(self, source, previous, now):
                calls.append(source['id'])
                lease = json.loads(self_outer.objects['lease'].data)
                lease['token'] = 'e' * 32
                self_outer.objects['lease'].data = json.dumps(lease).encode()
                return {'items': [], 'lastSuccessAt': now.isoformat(), 'lastHttpStatus': 200}
        self_outer = self
        with self.assertRaises(WriterLeaseError):
            ingest({'sources': [SOURCE, dict(SOURCE, id='second')]}, store, Provider(), NOW)
        self.assertEqual(calls, [SOURCE['id']])
        self.assertNotIn('states', store.read())

    def test_local_writer_lock_is_shared_by_independent_store_instances(self):
        with tempfile.TemporaryDirectory() as directory:
            first, second = LocalStore(directory), LocalStore(directory)
            with first.writer():
                with self.assertRaisesRegex(WriterLeaseError, 'content-writer-busy'):
                    with second.writer():
                        self.fail('Local writers must serialize')
            with second.writer() as guard:
                guard()
