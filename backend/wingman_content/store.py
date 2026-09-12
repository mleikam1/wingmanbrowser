"""One atomic object contains public snapshot and private ingestion state."""
import json
import os
import tempfile
from pathlib import Path

MAX_BUNDLE_BYTES = 4 * 1024 * 1024


def encode(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


class LocalStore:
    def __init__(self, directory):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.path = self.directory / "current.json"

    def read(self):
        if not self.path.exists():
            return None
        if self.path.stat().st_size > MAX_BUNDLE_BYTES:
            raise ValueError("Stored bundle size limit")
        return json.loads(self.path.read_bytes())

    def write(self, bundle):
        data = encode(bundle)
        if len(data) > MAX_BUNDLE_BYTES:
            raise ValueError("Stored bundle size limit")
        fd, path = tempfile.mkstemp(prefix=".pending-", dir=self.directory)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(path, self.path)
            directory_fd = os.open(self.directory, os.O_RDONLY)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        finally:
            if os.path.exists(path):
                os.unlink(path)


class GCSStore:
    """Private bucket object; readers see only completely uploaded generations.

    The service emits only bundle.snapshot. Conditional generation writes prevent
    overlapping scheduled jobs from overwriting newer state. No bucket is created.
    """
    def __init__(self, bucket, object_name="wingman-content/current.json", project=None):
        if not project:
            raise ValueError("Explicit dedicated CONTENT_PROJECT is required; no CLI default project")
        from google.cloud import storage
        self.blob = storage.Client(project=project).bucket(bucket).blob(object_name)
        self.generation = 0

    def read(self):
        from google.api_core.exceptions import NotFound
        try:
            self.blob.reload(timeout=10, retry=None)
            if self.blob.size > MAX_BUNDLE_BYTES:
                raise ValueError("Stored bundle size limit")
            self.generation = int(self.blob.generation)
            data = self.blob.download_as_bytes(if_generation_match=self.generation, timeout=10, retry=None)
            return json.loads(data)
        except NotFound:
            self.generation = 0
            return None

    def write(self, bundle):
        data = encode(bundle)
        if len(data) > MAX_BUNDLE_BYTES:
            raise ValueError("Stored bundle size limit")
        self.blob.upload_from_string(data, content_type="application/json",
                                     if_generation_match=self.generation, timeout=20, retry=None)
        self.generation = int(self.blob.generation)
