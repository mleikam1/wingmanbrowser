"""Destination ownership checks must complete before any project files are copied."""
import contextlib
import io
import json
from pathlib import Path
import runpy
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'prepare.py'
APP = 'com.wingmanbrowser.wingman_browser.gecko_prototype'

class CopyReached(Exception):
    pass

class DestinationOwnershipTests(unittest.TestCase):
    def run_prepare(self, destination, accepted):
        with patch('sys.argv', [str(SCRIPT), '--destination', str(destination)]), \
             patch('shutil.copytree', side_effect=CopyReached) as copy, \
             contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(CopyReached if accepted else SystemExit):
                runpy.run_path(str(SCRIPT), run_name='__main__')
            self.assertEqual(copy.call_count, 1 if accepted else 0)

    def test_existing_file_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            dest = Path(directory) / 'project'
            dest.write_text('unrelated')
            self.run_prepare(dest, False)
            self.assertEqual(dest.read_text(), 'unrelated')

    def test_nonempty_unowned_or_invalid_marker_rejected(self):
        for value in [None, 'invalid JSON', '[]', json.dumps({'applicationId': 'unrelated'})]:
            with self.subTest(value=value), tempfile.TemporaryDirectory() as directory:
                dest = Path(directory)
                (dest / 'keep.txt').write_text('unrelated')
                if value is not None:
                    (dest / 'prototype-build.json').write_text(value)
                self.run_prepare(dest, False)
                self.assertEqual((dest / 'keep.txt').read_text(), 'unrelated')

    def test_owned_nonempty_destination_can_refresh(self):
        with tempfile.TemporaryDirectory() as directory:
            dest = Path(directory)
            (dest / 'prototype-build.json').write_text(json.dumps({'applicationId': APP}))
            self.run_prepare(dest, True)

    def test_empty_or_new_destination_allowed(self):
        with tempfile.TemporaryDirectory() as directory:
            self.run_prepare(Path(directory), True)
            self.run_prepare(Path(directory) / 'new', True)

if __name__ == '__main__':
    unittest.main()
