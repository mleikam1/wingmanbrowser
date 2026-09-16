"""One atomic object contains public snapshot and private ingestion state."""
import json
import math
import os
import tempfile
import time
import uuid
from contextlib import contextmanager
from pathlib import Path

MAX_BUNDLE_BYTES = 4 * 1024 * 1024
WRITER_LEASE_SECONDS = 1200


class WriterLeaseError(RuntimeError):
    """Fixed secret-free error; a writer must stop before more provider I/O."""


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

    @contextmanager
    def writer(self):
        import fcntl
        with (self.directory / 'ingest.lock').open('a') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise WriterLeaseError('content-writer-busy') from None
            active = True
            def check():
                if not active:
                    raise WriterLeaseError('content-writer-lost')
            try:
                yield check
            finally:
                active = False
                fcntl.flock(lock, fcntl.LOCK_UN)

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
        self.bucket = storage.Client(project=project).bucket(bucket)
        self.blob = self.bucket.blob(object_name)
        # Independent of disposable content and the Currents daily ledger.
        self.writer_object = 'wingman-operations/content-writer-lease.json'
        self.generation = 0
        self._active_writer = None

    def _lease_read(self):
        from google.api_core.exceptions import NotFound
        blob = self.bucket.blob(self.writer_object)
        try:
            blob.reload(timeout=10, retry=None)
            if blob.size > 4096:
                raise WriterLeaseError('content-writer-corrupt')
            generation = int(blob.generation)
            lease = json.loads(blob.download_as_bytes(if_generation_match=generation, timeout=10, retry=None))
            if (not isinstance(lease, dict) or type(lease.get('fence')) is not int or lease['fence'] < 1
                    or not isinstance(lease.get('token'), str) or len(lease['token']) != 32
                    or type(lease.get('expiresAt')) not in (int, float)
                    or not math.isfinite(lease['expiresAt']) or lease['expiresAt'] < 0):
                raise WriterLeaseError('content-writer-corrupt')
            return blob, generation, lease
        except NotFound:
            return blob, 0, None

    @contextmanager
    def writer(self):
        """Lease the entire read/ingest/publication, then fence older generations.

        The API's shorter per-attempt lease accounts quota. This separate writer
        lease prevents successful category polls from being lost to snapshot CAS
        conflicts. Acquiring it also bumps the content object's generation before
        any upstream I/O, so an expired older writer cannot publish late.
        """
        token = uuid.uuid4().hex
        acquired = False
        try:
            for _ in range(4):
                blob, generation, prior = self._lease_read()
                now = time.time()
                if prior and prior['expiresAt'] > now:
                    raise WriterLeaseError('content-writer-busy')
                lease = {'token': token, 'fence': prior['fence'] + 1 if prior else 1,
                         'expiresAt': now + WRITER_LEASE_SECONDS}
                try:
                    blob.upload_from_string(encode(lease), content_type='application/json',
                                            if_generation_match=generation, timeout=10, retry=None)
                    acquired = True
                    break
                except Exception as exc:
                    if getattr(exc, 'code', None) in (409, 412):
                        continue
                    raise
            if not acquired:
                raise WriterLeaseError('content-writer-contention')
            def check():
                try:
                    current_blob, current_generation, current = self._lease_read()
                    now = time.time()
                    if (not current or current['token'] != token or current['fence'] != lease['fence']
                            or current['expiresAt'] <= now):
                        raise WriterLeaseError('content-writer-lost')
                    if current['expiresAt'] - now < WRITER_LEASE_SECONDS / 2:
                        current['expiresAt'] = now + WRITER_LEASE_SECONDS
                        current_blob.upload_from_string(encode(current), content_type='application/json',
                            if_generation_match=current_generation, timeout=10, retry=None)
                except WriterLeaseError:
                    raise
                except Exception:
                    raise WriterLeaseError('content-writer-unavailable') from None
            self._active_writer = check
            # The content CAS is the publication fence, even if a prior worker
            # was paused between its final lease check and its attempted upload.
            previous = self.read() or {}
            self.write(dict(previous, _writerFence=token))
            yield check
        except WriterLeaseError:
            raise
        except Exception:
            raise WriterLeaseError('content-writer-unavailable') from None
        finally:
            self._active_writer = None
            if acquired:
                try:
                    blob, generation, current = self._lease_read()
                    if current and current['token'] == token:
                        current['expiresAt'] = 0
                        blob.upload_from_string(encode(current), content_type='application/json',
                            if_generation_match=generation, timeout=10, retry=None)
                except Exception:
                    # A release failure keeps the lease until expiry, never
                    # clears another writer or causes an unbudgeted retry.
                    pass

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
        if getattr(self, '_active_writer', None):
            self._active_writer()
        data = encode(bundle)
        if len(data) > MAX_BUNDLE_BYTES:
            raise ValueError("Stored bundle size limit")
        self.blob.upload_from_string(data, content_type="application/json",
                                     if_generation_match=self.generation, timeout=20, retry=None)
        self.generation = int(self.blob.generation)
