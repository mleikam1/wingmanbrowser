"""Operator surfaces must not leak secrets or select unapproved infrastructure."""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from wingman_content.secret import load_currents_secret

ROOT = Path(__file__).resolve().parents[2]


class OperatorCommandTests(unittest.TestCase):
    def test_secret_environment_precedence_and_restrictive_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / '.env.currents'
            with patch.dict(os.environ, {}, clear=True):
                self.assertIsNone(load_currents_secret(path))
                path.write_text('CURRENTS_API_KEY=' + json.dumps('test-only-token') + '\n')
                path.chmod(0o600)
                self.assertEqual(load_currents_secret(path), 'test-only-token')
                path.chmod(0o644)
                with self.assertRaisesRegex(ValueError, '0600'):
                    load_currents_secret(path)
                path.chmod(0o600)
                path.write_text('CURRENTS_API_KEY=accidental-secret-without-quotes')
                with self.assertRaises(ValueError) as raised:
                    load_currents_secret(path)
                self.assertNotIn('accidental-secret', str(raised.exception))
            with patch.dict(os.environ, {'CURRENTS_API_KEY': 'environment-test-token'}):
                self.assertEqual(load_currents_secret(path), 'environment-test-token')

    def test_secret_symlink_rejected_and_noninteractive_prompt_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'real'
            source.write_text('CURRENTS_API_KEY="fixture"')
            source.chmod(0o600)
            link = Path(directory) / 'link'
            link.symlink_to(source)
            with patch.dict(os.environ, {}, clear=True):
                with self.assertRaises(ValueError):
                    load_currents_secret(link)
        result = subprocess.run([sys.executable, 'backend/setup_currents_secret.py'],
                                input='do-not-echo-me', text=True, capture_output=True, cwd=ROOT)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('do-not-echo-me', result.stdout + result.stderr)

    def test_render_requires_explicit_project_and_secret_name_only_on_writer(self):
        with tempfile.TemporaryDirectory() as directory:
            args = [sys.executable, 'backend/deploy/render.py', '--project', 'wingman-fixture',
                    '--project-number', '123456789', '--region', 'us-central1',
                    '--bucket', 'wingman-fixture-private', '--image',
                    'us-central1-docker.pkg.dev/wingman-fixture/content/service@sha256:' + 'a' * 64,
                    '--currents-secret', 'existing-secret-name', '--output', directory]
            result = subprocess.run(args, text=True, capture_output=True, cwd=ROOT)
            self.assertEqual(result.returncode, 0, result.stderr)
            writer = (Path(directory) / 'cloud-run-job.yaml').read_text()
            reader = (Path(directory) / 'cloud-run-service.yaml').read_text()
            self.assertIn('secretKeyRef:', writer)
            self.assertIn('wingman-operations/currents-ledger.json', writer)
            self.assertNotIn('CURRENTS_API_KEY', reader)
            self.assertNotRegex(writer + reader, r'REPLACE_[A-Z][A-Z_]+')
            scheduler = json.loads((Path(directory) / 'scheduler.json').read_text())
            self.assertEqual(scheduler['retryConfig']['retryCount'], 0)
            self.assertEqual(scheduler['schedule'], '*/30 * * * *')
            args[args.index('wingman-fixture')] = 'wingman-interactive-live'
            result = subprocess.run(args, text=True, capture_output=True, cwd=ROOT)
            self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
