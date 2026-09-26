"""Offline Cloud Run configuration and actual Gunicorn HTTP parser regressions."""
import os
from pathlib import Path
import runpy
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

try:
    from gunicorn.config import Config
    from gunicorn.http.message import Request
    from gunicorn.http.unreader import IterUnreader
    from gunicorn.http.wsgi import create
except ImportError:
    Config = None


MODULE = Path(__file__).parents[1] / 'wingman_search' / 'gunicorn_cloud_run.py'
ENV = {'K_SERVICE': 'wingman-fixture', 'K_REVISION': 'wingman-fixture-00001',
       'K_CONFIGURATION': 'wingman-fixture'}


def load(environment=None):
    with patch.dict(os.environ, ENV if environment is None else environment, clear=True):
        return runpy.run_path(str(MODULE))


class CloudRunConfigurationTests(unittest.TestCase):
    def test_every_managed_environment_value_required_and_errors_sanitized(self):
        for missing in ENV:
            environment = dict(ENV)
            del environment[missing]
            with self.subTest(missing=missing), self.assertRaisesRegex(
                    RuntimeError, '^cloud_run_environment_required$'):
                load(environment)
        for value in ('', ' ', 'sensitive-invalid-value\n', 'x' * 64):
            with self.subTest(value=value), self.assertRaisesRegex(
                    RuntimeError, '^cloud_run_environment_required$'):
                load(dict(ENV, K_SERVICE=value))

    def test_port_validation_has_no_host_or_argument_injection(self):
        self.assertEqual(load()['bind'], ['0.0.0.0:8080'])
        self.assertEqual(load(dict(ENV, PORT='9090'))['bind'], ['0.0.0.0:9090'])
        for value in ('', '0', '65536', '-1', ' 8080', '8080\n', '０８０', '127.0.0.1:8080'):
            with self.subTest(value=value), self.assertRaisesRegex(
                    RuntimeError, '^cloud_run_port_invalid$'):
                load(dict(ENV, PORT=value))

    def test_generic_docker_entrypoint_does_not_enable_cloud_trust(self):
        docker = (MODULE.parents[1] / 'Dockerfile.search').read_text()
        entrypoint = next(line for line in docker.splitlines() if line.startswith('ENTRYPOINT'))
        self.assertNotIn('gunicorn_cloud_run', entrypoint)
        self.assertNotIn('forwarded-allow-ips', entrypoint)


@unittest.skipIf(Config is None, 'install backend/requirements-search.txt for Gunicorn parser checks')
class CloudRunParserTests(unittest.TestCase):
    def setUp(self):
        self.module = load()
        self.cfg = Config()
        for name, value in self.module.items():
            if name in self.cfg.settings:
                self.cfg.set(name, value)

    def parse(self, headers=(), path='/v1/search'):
        raw = ('POST ' + path + ' HTTP/1.1\r\nHost: search.example.org\r\n'
               'Content-Type: application/json\r\nContent-Length: 2\r\n' +
               ''.join(header + '\r\n' for header in headers) + '\r\n{}').encode('ascii')
        return Request(self.cfg, IterUnreader([raw]), ('10.1.2.3', 12345))

    def test_cloud_edge_https_preserves_original_path_and_host(self):
        request = self.parse(['X-Forwarded-Proto: https', 'X-Forwarded-Host: attacker.example',
                              'X-Forwarded-Prefix: /admin'])
        with patch.dict(os.environ, ENV, clear=True):
            _, environ = create(request, Mock(), ('10.1.2.3', 12345), ('0.0.0.0', 8080), self.cfg)
        self.assertEqual(environ['wsgi.url_scheme'], 'https')
        self.assertEqual(environ['PATH_INFO'], '/v1/search')
        self.assertEqual(environ['SCRIPT_NAME'], '')
        self.assertEqual(environ['HTTP_HOST'], 'search.example.org')

    def test_only_exact_proto_header_establishes_https(self):
        for headers in ([], ['X-Forwarded-SSL: on'], ['X-Forwarded-Protocol: ssl'],
                        ['Forwarded: proto=https'], ['X-Forwarded-Proto: http'],
                        ['X-Forwarded-Proto: HTTPS'], ['X-Forwarded-Proto: https,http']):
            with self.subTest(headers=headers):
                self.assertEqual(self.parse(headers).scheme, 'http')
        self.assertEqual(self.parse(['X-Forwarded-Proto: https']).scheme, 'https')

    def test_conflicting_scheme_and_forwarder_overrides_are_rejected(self):
        for headers in (['X-Forwarded-Proto: https', 'X-Forwarded-Proto: http'],
                        ['SCRIPT_NAME: /admin'], ['PATH_INFO: /admin'], ['REMOTE_USER: admin'],
                        ['X_Forwarded_Proto: https'], ['Host: attacker.example'],
                        ['Content-Length: 2']):
            with self.subTest(headers=headers), self.assertRaises(Exception):
                self.parse(headers)

    def test_request_limits_apply_before_wsgi(self):
        with self.assertRaises(Exception):
            self.parse(path='/' + 'x' * 1024)
        with self.assertRaises(Exception):
            self.parse(['X-Size: ' + 'x' * 2048])
        with self.assertRaises(Exception):
            self.parse(['X-Field-' + str(index) + ': value' for index in range(30)])

    def test_starting_revalidates_environment_and_effective_safety_settings(self):
        hook = self.module['on_starting']
        with patch.dict(os.environ, ENV, clear=True):
            hook(SimpleNamespace(cfg=self.cfg))
            for setting, changed in (('workers', 2), ('threads', 8), ('accesslog', '-'),
                    ('errorlog', '-'), ('forwarder_headers', 'SCRIPT_NAME'),
                    ('secure_scheme_headers', {'X-FORWARDED-SSL': 'on'}),
                    ('forwarded_allow_ips', '127.0.0.1'), ('header_map', 'dangerous'),
                    ('proxy_protocol', 'auto'), ('limit_request_fields', 100)):
                previous = self.module[setting]
                self.cfg.set(setting, changed)
                with self.subTest(setting=setting), self.assertRaisesRegex(
                        RuntimeError, '^cloud_run_gunicorn_configuration_changed$'):
                    hook(SimpleNamespace(cfg=self.cfg))
                self.cfg.set(setting, previous)
        with patch.dict(os.environ, {}, clear=True), self.assertRaisesRegex(
                RuntimeError, '^cloud_run_environment_required$'):
            hook(SimpleNamespace(cfg=self.cfg))


if __name__ == '__main__':
    unittest.main()
