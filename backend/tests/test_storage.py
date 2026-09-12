"""Cloud adapter contract exercised without credentials or live cloud resources."""
import json
import sys
import types
import unittest
from unittest.mock import patch
from wingman_content.store import GCSStore, MAX_BUNDLE_BYTES


class NotFound(Exception):
    pass


class PreconditionFailed(Exception):
    pass


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
