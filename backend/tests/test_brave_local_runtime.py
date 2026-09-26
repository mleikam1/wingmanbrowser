import contextlib
import http.client
import importlib.util
import io
import json
from pathlib import Path
import threading
import tempfile
import unittest
from unittest.mock import Mock, patch

from wingman_search.budget import BudgetError
from wingman_search.contracts import SearchError
from wingman_search.gateway import SearchApplication, LocalServer, handler_for
from wingman_search.local_runtime import create_local_search_application, local_status, LocalRuntimeError
from wingman_search.provider import FixtureProvider

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('brave_local_launcher', ROOT / 'scripts/run_brave_local.py')
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


class LocalRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.ledger = Mock()
        self.ledger.snapshot.return_value = dict(attempts=3, verified_web=True, verified_news=False,
            remaining_attempts=97, dangerous_extra='must-not-leak', billing_reconciliation_complete=False,
            endpoint_outcomes={'web': {'latest_schema_reserved_at': 2000}, 'news': {'latest_schema_reserved_at': None}})
        stamp = patch('wingman_search.local_runtime.credential_identity', return_value=(1, 2, 1000000, 1000000, 32))
        self.identity = stamp.start()
        self.addCleanup(stamp.stop)

    @patch('wingman_search.local_runtime.secret_status', return_value='configured_unverified')
    def test_factory_uses_fixed_actor_count_and_no_dispatch_or_initialization(self, status):
        factory, loader, provider = Mock(return_value=self.ledger), Mock(return_value='synthetic-key-only'), Mock()
        app = create_local_search_application(ROOT, actor='automated', ledger_factory=factory,
            secret_loader=loader, provider_factory=provider)
        self.assertEqual('automated', factory.call_args.kwargs['actor'])
        provider.assert_called_once_with(self.ledger, 'synthetic-key-only', transport=None, default_count=10)
        self.ledger.reserve.assert_not_called()
        provider.return_value.search.assert_not_called()
        self.assertEqual('local-live', app.mode)
        self.assertTrue(app.local_status()['verifiedWeb'])
        self.assertEqual(1, loader.call_count)

    @patch('wingman_search.local_runtime.secret_status', return_value='unconfigured')
    def test_unconfigured_fails_before_ledger_or_key(self, status):
        factory, loader = Mock(), Mock()
        with self.assertRaises(LocalRuntimeError) as error:
            create_local_search_application(ROOT, ledger_factory=factory, secret_loader=loader)
        self.assertEqual('credential-unconfigured', error.exception.code)
        factory.assert_not_called()
        loader.assert_not_called()

    @patch('wingman_search.local_runtime.secret_status', return_value='configured_unverified')
    def test_unavailable_accounting_fails_before_key(self, status):
        loader = Mock()
        with self.assertRaises(LocalRuntimeError):
            create_local_search_application(ROOT, ledger_factory=Mock(side_effect=BudgetError('unsafe_or_missing_ledger')),
                                            secret_loader=loader)
        loader.assert_not_called()

    @patch('wingman_search.local_runtime.load_secret', side_effect=AssertionError('no key read'))
    @patch('wingman_search.local_runtime.secret_status', return_value='configured_unverified')
    def test_status_metadata_has_verification_and_no_unreviewed_fields(self, status, loader):
        result = local_status(ROOT, ledger=self.ledger)
        self.assertEqual('verified-web', result['credentialStatus'])
        self.assertTrue(result['verifiedWeb'])
        self.assertFalse(result['verifiedNews'])
        self.assertEqual(97, result['accounting']['remaining_attempts'])
        self.assertNotIn('dangerous_extra', json.dumps(result))
        loader.assert_not_called()
        self.ledger.reserve.assert_not_called()

    @patch('wingman_search.local_runtime.secret_status', return_value='configured_unverified')
    def test_status_label_distinguishes_endpoint_verification(self, status):
        for web, news, expected in [(None, None, 'configured-unverified'),
                (2000, None, 'verified-web'), (None, 2000, 'verified-news'),
                (2000, 2000, 'verified-web-and-news')]:
            self.ledger.snapshot.return_value['endpoint_outcomes'] = {
                'web': {'latest_schema_reserved_at': web},
                'news': {'latest_schema_reserved_at': news}}
            self.assertEqual(expected, local_status(ROOT, ledger=self.ledger)['credentialStatus'])

    @patch('wingman_search.local_runtime.secret_status', return_value='configured_unverified')
    def test_rotated_credential_does_not_reuse_previous_verification(self, status):
        self.identity.return_value = (1, 3, 3000000, 3000000, 32)
        self.assertFalse(local_status(ROOT, ledger=self.ledger)['verifiedWeb'])

    @patch('wingman_search.local_runtime.secret_status', return_value='configured_unverified')
    def test_credential_replacement_requires_restart_before_reservation(self, status):
        provider = Mock()
        app = create_local_search_application(ROOT, ledger_factory=Mock(return_value=self.ledger),
            secret_loader=Mock(return_value='synthetic-key-only'), provider_factory=Mock(return_value=provider))
        self.identity.return_value = (1, 3, 1000000, 1000000, 32)
        with self.assertRaises(SearchError) as error:
            provider.before_request()
        self.assertEqual('configuration-required', error.exception.code)
        self.ledger.reserve.assert_not_called()

    @patch('wingman_search.local_runtime.secret_status', return_value='configured_unverified')
    def test_credential_change_during_load_never_creates_provider(self, status):
        provider = Mock()
        self.identity.side_effect = [(1, 2, 1000000, 1000000, 32), (1, 3, 1000000, 1000000, 32)]
        with self.assertRaises(LocalRuntimeError):
            create_local_search_application(ROOT, ledger_factory=Mock(return_value=self.ledger),
                secret_loader=Mock(return_value='synthetic-key-only'), provider_factory=provider)
        provider.assert_not_called()

    @patch('wingman_search.local_runtime.secret_status', return_value='configured_unverified')
    def test_real_provider_factory_uses_ten_for_each_endpoint_without_real_transport(self, status):
        from wingman_content.fetch import FetchResult
        transport = Mock()
        bodies = [dict(query={}, web={'results': []}), dict(query={}, results=[])]
        transport.request.side_effect = [FetchResult(200, {}, json.dumps(body).encode()) for body in bodies]
        app = create_local_search_application(ROOT, ledger_factory=Mock(return_value=self.ledger),
            secret_loader=Mock(return_value='synthetic-key-only'), transport=transport)
        transport.request.assert_not_called()
        app.local_status()
        transport.request.assert_not_called()
        for kind in ('web', 'news'):
            dto = app.search({'query': 'space science', 'kind': kind})
            self.assertFalse(dto['fixture'])
        self.assertEqual(2, self.ledger.reserve.call_count)
        for call in transport.request.call_args_list:
            self.assertEqual(10, call.args[1]['count'])
            self.assertEqual('strict', call.args[1]['safesearch'])
        self.assertNotIn('result_filter', transport.request.call_args_list[1].args[1])

    def test_local_allowance_errors_are_distinct_safe_codes(self):
        cases = {'local_evaluation_expired': 'allowance-expired',
            'automated_attempt_budget_exhausted': 'automated-limit-reached',
            'previous_attempt_unresolved': 'allowance-paused',
            'local_evaluation_paused_authentication': 'allowance-paused',
            'attempt_budget_exhausted': 'budget-exhausted', 'shared_backoff': 'provider-rate-limited'}
        for cause, expected in cases.items():
            app = SearchApplication(Mock(search=Mock(side_effect=BudgetError(cause))))
            with self.assertRaises(SearchError) as error:
                app.search({'query': 'space science'})
            self.assertEqual(expected, error.exception.code)

    def test_cli_modes_cannot_initialize_or_load_live_accidentally(self):
        from wingman_search.__main__ import main
        with patch('wingman_search.__main__.serve') as serve, patch(
                'wingman_search.local_runtime.create_local_search_application') as live, patch(
                'wingman_search.local_budget.LocalEvaluationLedger.initialize') as init, \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(0, main(['serve']))
            self.assertEqual('disabled', serve.call_args.args[0].mode)
            self.assertEqual(0, main(['serve-fixtures']))
            self.assertEqual('fixtures', serve.call_args.args[0].mode)
            live.assert_not_called()
            init.assert_not_called()

    def test_explicit_initialize_and_resume_are_separate_commands(self):
        from wingman_search.__main__ import main
        with patch('wingman_search.local_budget.LocalEvaluationLedger') as cls, patch(
                'wingman_search.local_runtime.local_status', return_value={'mode': 'local-live'}), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(0, main(['initialize-local', '--actor', 'automated']))
            cls.initialize.assert_called_once()
            self.assertEqual('automated', cls.initialize.call_args.kwargs['actor'])
            self.assertEqual(0, main(['resume-local', '--correction', 'request-corrected']))
            cls.return_value.resume.assert_called_once_with(correction='request-corrected')


class LocalBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.provider = Mock(wraps=FixtureProvider())
        self.app = SearchApplication(self.provider, mode='local-live')
        self.app.local_status = Mock(return_value={'mode': 'local-live', 'accounting': {'attempts': 4}})
        self.server = LocalServer(('127.0.0.1', 0), handler_for(self.app, ['http://127.0.0.1:8898']))
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(2)

    def request(self, method='POST', path='/v1/search', headers=(), body=b'{"query":"space science"}'):
        c = http.client.HTTPConnection('127.0.0.1', self.port, timeout=2)
        c.putrequest(method, path, skip_host=True)
        c.putheader('Host', f'127.0.0.1:{self.port}')
        if method == 'POST':
            c.putheader('Content-Type', 'application/json')
            c.putheader('Content-Length', len(body))
        for key, value in headers:
            c.putheader(key, value)
        c.endheaders(body if method == 'POST' else None)
        response = c.getresponse()
        result = response.status, response.read()
        c.close()
        return result

    def test_health_status_and_options_never_dispatch_or_consume_search_burst(self):
        for _ in range(25):
            self.assertEqual(200, self.request('GET', '/healthz')[0])
        self.assertEqual(200, self.request('GET', '/statusz')[0])
        self.assertEqual(200, self.request('HEAD', '/healthz')[0])
        self.assertEqual(200, self.request('OPTIONS', headers=(('Origin', 'http://127.0.0.1:8898'),
            ('Access-Control-Request-Method', 'POST'), ('Access-Control-Request-Headers', 'content-type')))[0])
        self.provider.search.assert_not_called()
        self.assertEqual(200, self.request()[0])
        self.assertEqual(1, self.provider.search.call_count)

    def test_foreign_empty_duplicate_browser_origin_and_credentials_never_dispatch(self):
        cases = [(('Origin', 'https://example.org'),), (('Origin', ''),),
            (('Origin', 'http://127.0.0.1:8898'), ('Origin', 'http://127.0.0.1:8898')),
            (('Sec-Fetch-Site', 'cross-site'),), (('Cookie', 'no-secret-fixture'),),
            (('Authorization', 'fixture'),), (('Host', f'127.0.0.1:{self.port}'),)]
        for headers in cases:
            self.assertEqual(403, self.request(headers=headers)[0])
        self.provider.search.assert_not_called()

    def test_json_duplicate_framing_encoding_and_form_requests_never_dispatch(self):
        for headers in ((('Content-Type', 'text/plain'),), (('Content-Length', '25'),),
                        (('Transfer-Encoding', ''),), (('Content-Encoding', 'gzip'),), (('Expect', '100-continue'),)):
            self.assertIn(self.request(headers=headers)[0], (413, 415))
        self.provider.search.assert_not_called()

    def test_native_absent_origin_and_exact_browser_origin_can_dispatch(self):
        self.assertEqual(200, self.request()[0])
        self.assertEqual(200, self.request(headers=(('Origin', 'http://127.0.0.1:8898'),
                                                  ('Sec-Fetch-Site', 'same-site')))[0])
        self.assertEqual(2, self.provider.search.call_count)

    def test_invalid_preflight_and_non_post_do_not_dispatch(self):
        for method in ('GET', 'HEAD', 'PUT', 'DELETE', 'PATCH', 'TRACE'):
            self.assertGreaterEqual(self.request(method)[0], 400)
        self.assertEqual(403, self.request('OPTIONS', headers=(('Origin', 'http://127.0.0.1:8898'),
            ('Access-Control-Request-Method', 'DELETE')))[0])
        self.provider.search.assert_not_called()

    def test_sanitized_error_exposes_only_known_metadata(self):
        self.provider.search.side_effect = SearchError('provider-request-invalid', 503, 422, provider_code='INTERNAL')
        status, body = self.request()
        self.assertEqual(503, status)
        self.assertEqual({'code': 'provider-request-invalid', 'providerStatus': 422, 'providerCode': 'INTERNAL'},
                         json.loads(body)['error'])
        self.assertNotIn('space science', body.decode())


class LauncherTests(unittest.TestCase):
    def test_dry_run_no_key_process_network_or_build(self):
        run, popen, check = Mock(), Mock(), Mock()
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(0, launcher.launch(launcher.parse_args(['--dry-run']), run=run, popen=popen, check_port=check))
        for mock in (run, popen, check):
            mock.assert_not_called()
        result = json.loads(output.getvalue())
        self.assertEqual(0, result['automaticSearches'])
        self.assertIn('serve-live-local', result['gatewayCommand'])
        self.assertIn('--debug', result['appCommand'])
        for flag in ('--no-pub', '--no-web-resources-cdn', '--no-wasm-dry-run'):
            self.assertIn(flag, result['appCommand'])
        self.assertIn('--dart-define=WINGMAN_SEARCH_URL=http://127.0.0.1:8897/v1/search', result['appCommand'])

    def test_actual_web_build_precedes_process_readiness_and_static_serving(self):
        events = []
        gateway = Mock(poll=Mock(return_value=None))
        server = Mock(serve_forever=Mock(side_effect=lambda: events.append('static')))
        def run(*args, **kwargs):
            events.append('build')
            return Mock(returncode=0)
        def popen(*args, **kwargs):
            events.append('gateway')
            return gateway
        def ready(*args): events.append('health-only')
        def stop(*args): events.append('stop-owned')
        def sleep(_): raise KeyboardInterrupt()
        with self.assertRaises(KeyboardInterrupt), contextlib.redirect_stdout(io.StringIO()):
            launcher.launch(launcher.parse_args(['--actor', 'automated']), run=run, popen=popen,
                check_port=Mock(), readiness=ready, server_factory=Mock(return_value=server), stop=stop, sleep=sleep,
                verify_web=Mock())
        self.assertEqual(['build', 'gateway', 'health-only'], events[:3])
        server.server_close.assert_called_once()
        self.assertIn('stop-owned', events)

    def test_web_port_pairs_build_and_serve_distinct_matching_directories(self):
        outputs = []
        for gateway_port, web_port in ((8897, 8898), (8907, 8908), (8909, 8910)):
            args = launcher.parse_args(['--gateway-port', str(gateway_port), '--web-port', str(web_port)])
            run = Mock(return_value=Mock(returncode=0))
            server = Mock()
            factory = Mock(return_value=server)
            with self.assertRaises(KeyboardInterrupt), contextlib.redirect_stdout(io.StringIO()):
                launcher.launch(args, run=run,
                    popen=Mock(return_value=Mock(poll=Mock(return_value=None))), check_port=Mock(),
                    readiness=Mock(), server_factory=factory, stop=Mock(), sleep=Mock(side_effect=KeyboardInterrupt),
                    verify_web=Mock())
            command = run.call_args.args[0]
            output = command[command.index('--output') + 1]
            self.assertEqual(output, factory.call_args.args[1].keywords['directory'])
            self.assertEqual(('127.0.0.1', web_port), factory.call_args.args[0])
            self.assertIn(f'--dart-define=WINGMAN_SEARCH_URL=http://127.0.0.1:{gateway_port}/v1/search', command)
            outputs.append(output)
        self.assertEqual(3, len(set(outputs)))
        self.assertEqual(str(ROOT / 'work' / 'brave-live-web' / 'current'), outputs[0])

    def test_incomplete_successful_web_build_stops_before_gateway_or_serving(self):
        popen, server = Mock(), Mock()
        with self.assertRaises(launcher.LaunchError):
            launcher.launch(launcher.parse_args([]), run=Mock(return_value=Mock(returncode=0)),
                popen=popen, server_factory=server, check_port=Mock(), stop=Mock(),
                verify_web=Mock(side_effect=launcher.LaunchError('incomplete bundle')))
        popen.assert_not_called()
        server.assert_not_called()

    def test_web_completeness_checks_declared_assets_and_static_resources(self):
        with tempfile.TemporaryDirectory(prefix='web-bundle-', dir=ROOT / 'work') as temp:
            root = Path(temp)
            output = root / 'work' / 'brave-live-web' / 'current'
            output.mkdir(parents=True)
            build_id = 'a' * 32
            (output / '.last_build_id').write_text(build_id)
            metadata = root / '.dart_tool' / 'flutter_build' / build_id / 'outputs.json'
            metadata.parent.mkdir(parents=True)
            required = ['index.html', 'main.dart.js', 'flutter_bootstrap.js', 'flutter.js',
                'assets/AssetManifest.bin', 'assets/AssetManifest.bin.json', 'assets/FontManifest.json',
                'assets/assets/policy/manifest.json', 'assets/assets/policy/catalog.json',
                'assets/assets/policy/consumer_protection.json', 'assets/assets/policy/live_sites.json',
                'assets/assets/live_content/sources.json', 'sqlite3.wasm', 'sqflite_sw.js',
                'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm', 'assets/assets/discovery/extra.png',
                'icons/extra.png']
            for name in required:
                path = output / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'synthetic')
            static = root / 'web' / 'icons' / 'extra.png'
            static.parent.mkdir(parents=True)
            static.write_bytes(b'synthetic')
            declared = output / 'assets/assets/discovery/extra.png'
            metadata.write_text(json.dumps([str(declared), str(output / '*' / 'index.html')]))
            launcher.verify_web_output(output, root)
            declared.unlink()
            with self.assertRaisesRegex(launcher.LaunchError, 'incomplete'):
                launcher.verify_web_output(output, root)
            declared.write_bytes(b'synthetic')
            (output / 'icons/extra.png').unlink()
            with self.assertRaisesRegex(launcher.LaunchError, 'incomplete'):
                launcher.verify_web_output(output, root)

    def test_web_missing_or_escaping_output_manifest_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix='web-manifest-', dir=ROOT / 'work') as temp:
            root = Path(temp)
            output = root / 'out'
            output.mkdir()
            with self.assertRaises(launcher.LaunchError):
                launcher.verify_web_output(output, root)
            (output / '.last_build_id').write_text('../outside')
            with self.assertRaises(launcher.LaunchError):
                launcher.verify_web_output(output, root)

    def test_busy_port_refuses_without_stopping_anything(self):
        run, popen, stop = Mock(), Mock(), Mock()
        with self.assertRaises(launcher.LaunchError):
            launcher.launch(launcher.parse_args([]), run=run, popen=popen, stop=stop,
                check_port=Mock(side_effect=launcher.LaunchError('busy')))
        for mock in (run, popen, stop): mock.assert_not_called()

    def test_android_preserves_data_and_cleans_only_owned_reverse(self):
        run = Mock(return_value=Mock(stdout='', returncode=0))
        gateway = Mock(poll=Mock(return_value=None))
        popen, stop = Mock(return_value=gateway), Mock()
        args = launcher.parse_args(['--platform', 'android', '--device', 'emulator-5998'])
        with self.assertRaises(KeyboardInterrupt), contextlib.redirect_stdout(io.StringIO()):
            launcher.launch(args, run=run, popen=popen, stop=stop, check_port=Mock(),
                            readiness=Mock(), sleep=Mock(side_effect=KeyboardInterrupt))
        calls = [call.args[0] for call in run.call_args_list]
        self.assertEqual(['flutter', 'build', 'apk', '--debug', '--no-pub'], calls[0][:5])
        self.assertTrue(all(cmd[:3] == ['adb', '-s', 'emulator-5998'] for cmd in calls[1:]))
        self.assertIn('--no-rebind', calls[2])
        self.assertEqual(['install', '-r'], calls[3][3:5])
        self.assertEqual(['shell', 'am', 'start', '-W', '-n', launcher.ANDROID_COMPONENT], calls[4][3:])
        self.assertEqual(['reverse', '--remove', 'tcp:8897'], calls[5][3:])
        self.assertFalse(any(word in ('uninstall', 'clear', 'run') for cmd in calls for word in cmd))
        self.assertEqual(1, popen.call_count)

    def test_android_replacement_failure_never_uninstalls_retries_or_launches(self):
        calls = []
        def run(cmd, **kwargs):
            calls.append(cmd)
            if 'install' in cmd:
                raise launcher.subprocess.CalledProcessError(1, cmd)
            return Mock(stdout='', returncode=0)
        with self.assertRaises(launcher.subprocess.CalledProcessError), contextlib.redirect_stdout(io.StringIO()):
            launcher.launch(launcher.parse_args(['--platform', 'android', '--device', 'emulator-5998']),
                run=run, popen=Mock(return_value=Mock(poll=Mock(return_value=None))), stop=Mock(),
                check_port=Mock(), readiness=Mock())
        self.assertEqual(1, sum('install' in cmd for cmd in calls))
        self.assertFalse(any('uninstall' in cmd or 'start' in cmd or 'clear' in cmd for cmd in calls))

    def test_android_selected_abi_build_and_install_match_actual_and_dry_run(self):
        for target, abi in (('android-arm', 'armeabi-v7a'), ('android-arm64', 'arm64-v8a'),
                            ('android-x64', 'x86_64')):
            with self.subTest(target=target):
                arguments = ['--platform', 'android', '--device', 'emulator-5998',
                             '--android-target-platform', target]
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    launcher.launch(launcher.parse_args(arguments + ['--dry-run']))
                planned = json.loads(output.getvalue())
                app = planned['appCommand']
                self.assertEqual(target, app[app.index('--target-platform') + 1])
                self.assertIn('--split-per-abi', app)
                expected = str(ROOT / 'build/app/outputs/flutter-apk' / f'app-{abi}-debug.apk')
                self.assertEqual(expected, planned['androidInstallCommand'][-1])
                run = Mock(return_value=Mock(stdout='', returncode=0))
                with self.assertRaises(KeyboardInterrupt), contextlib.redirect_stdout(io.StringIO()):
                    launcher.launch(launcher.parse_args(arguments), run=run,
                        popen=Mock(return_value=Mock(poll=Mock(return_value=None))), stop=Mock(),
                        check_port=Mock(), readiness=Mock(), sleep=Mock(side_effect=KeyboardInterrupt))
                calls = [call.args[0] for call in run.call_args_list]
                self.assertEqual(app, calls[0])
                installs = [cmd for cmd in calls if 'install' in cmd]
                self.assertEqual([planned['androidInstallCommand']], installs)

    def test_android_universal_default_unchanged_and_abi_rejected_for_web(self):
        args = launcher.parse_args(['--platform', 'android', '--device', 'emulator-5998'])
        _, command = launcher.commands(args)
        self.assertNotIn('--split-per-abi', command)
        self.assertNotIn('--target-platform', command)
        self.assertEqual('app-debug.apk', launcher.android_apk_path(args).name)
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            launcher.parse_args(['--android-target-platform', 'android-arm64'])

    def test_existing_reverse_is_never_removed(self):
        run = Mock(return_value=Mock(stdout='UsbFfs tcp:8897 tcp:8897\n', returncode=0))
        gateway = Mock(poll=Mock(return_value=None))
        with self.assertRaises(KeyboardInterrupt), contextlib.redirect_stdout(io.StringIO()):
            launcher.launch(launcher.parse_args(['--platform', 'android', '--device', 'emulator-5998']),
                run=run, popen=Mock(return_value=gateway), stop=Mock(), check_port=Mock(), readiness=Mock(),
                sleep=Mock(side_effect=KeyboardInterrupt))
        self.assertEqual(4, run.call_count)
        self.assertFalse(any('--remove' in call.args[0] for call in run.call_args_list))

    def test_sigterm_uses_normal_owned_process_cleanup_path(self):
        handlers = []
        def register(_kind, handler):
            handlers.append(handler)
            return 'previous-fixture-handler'
        def launched(_args):
            handlers[0](15, None)
        with patch.object(launcher.signal, 'signal', side_effect=register), patch.object(
                launcher, 'launch', side_effect=launched):
            self.assertEqual(0, launcher.main(['--dry-run']))
        self.assertEqual('previous-fixture-handler', handlers[-1])

    def test_readiness_uses_health_get_only(self):
        connection = Mock()
        connection.return_value.getresponse.return_value = Mock(status=200,
            read=Mock(return_value=b'{"status":"ok","mode":"local-live"}'))
        launcher.wait_ready(Mock(poll=Mock(return_value=None)), 8897, connection=connection)
        connection.return_value.request.assert_called_once_with('GET', '/healthz')


if __name__ == '__main__':
    unittest.main()
