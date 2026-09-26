#!/usr/bin/env python3
"""Start the actual development app and explicit local-live search gateway.

This helper never initializes/resumes the allowance, submits a search, retries a
request, uninstalls an app, or stops an unrelated process. Ctrl-C stops only its
own children and removes only its own Android reverse mapping. The selected
app's ordinary user searches spend the existing allowance.
"""
import argparse
import contextlib
import functools
import http.client
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import threading
import time
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
ANDROID_COMPONENT = 'com.wingmanbrowser.wingman_browser/.MainActivity'
ANDROID_ABIS = {'android-arm': 'armeabi-v7a', 'android-arm64': 'arm64-v8a', 'android-x64': 'x86_64'}


class LaunchError(RuntimeError):
    pass


def port_available(port):
    try:
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', port))
    except OSError:
        raise LaunchError('Requested port is already used; choose another port. No process was stopped.') from None


def parse_args(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--platform', choices=('web', 'android', 'ios', 'macos'), default='web')
    p.add_argument('--device', help='Exact already-running Flutter device ID; required for native platforms.')
    p.add_argument('--gateway-port', type=int, default=8897)
    p.add_argument('--web-port', type=int, default=8898)
    p.add_argument('--origin', help='Exact web origin; defaults to http://127.0.0.1:<web-port>.')
    p.add_argument('--actor', choices=('manual', 'automated'), default='manual')
    p.add_argument('--flutter', default='flutter')
    p.add_argument('--adb', default='adb')
    p.add_argument('--android-target-platform', choices=tuple(ANDROID_ABIS),
                   help='Build and install only this Android ABI; omitted means the universal APK.')
    p.add_argument('--dry-run', action='store_true', help='Print commands only; no build, processes, credential read, or live calls.')
    args = p.parse_args(argv)
    if any(not 1024 <= n <= 65535 for n in (args.gateway_port, args.web_port)):
        p.error('Ports must be unprivileged, from 1024 through 65535.')
    if args.gateway_port == args.web_port:
        p.error('Gateway and app ports must differ.')
    args.origin = args.origin or f'http://127.0.0.1:{args.web_port}'
    try:
        u = urlsplit(args.origin)
        valid = (u.scheme == 'http' and u.hostname in ('127.0.0.1', 'localhost')
                 and u.port == args.web_port and not u.username and not u.path and not u.query and not u.fragment)
    except ValueError:
        valid = False
    if not valid:
        p.error('--origin must match the selected loopback web port, with no path.')
    if args.platform != 'web' and (not args.device or not re.fullmatch(r'[A-Za-z0-9_.:-]{1,160}', args.device)):
        p.error('Native platforms require an explicit already-running --device ID.')
    if args.platform == 'android' and args.device == 'macos':
        p.error('Select an Android device explicitly.')
    if args.android_target_platform and args.platform != 'android':
        p.error('--android-target-platform requires --platform android.')
    return args


def web_output_directory(args, root=ROOT):
    # Keep the verified default artifact stable. Alternate port pairs must not
    # replace assets being served by another active helper's Flutter app.
    leaf = ('current' if (args.gateway_port, args.web_port) == (8897, 8898)
            else f'gateway-{args.gateway_port}-web-{args.web_port}')
    return root / 'work' / 'brave-live-web' / leaf


def android_apk_path(args, root=ROOT):
    abi = ANDROID_ABIS.get(args.android_target_platform)
    filename = f'app-{abi}-debug.apk' if abi else 'app-debug.apk'
    return root / 'build' / 'app' / 'outputs' / 'flutter-apk' / filename


def commands(args, root=ROOT):
    defines = [f'--dart-define=WINGMAN_SEARCH_URL=http://127.0.0.1:{args.gateway_port}/v1/search',
               '--dart-define=WINGMAN_SEARCH_DEVELOPMENT=true']
    gateway = [sys.executable, '-m', 'wingman_search', 'serve-live-local',
               '--port', str(args.gateway_port), '--actor', args.actor]
    if args.platform == 'web':
        gateway += ['--origin', args.origin]
        app = [args.flutter, 'build', 'web', '--debug', '--no-pub',
               '--no-web-resources-cdn', '--no-wasm-dry-run', '--output',
               str(web_output_directory(args, root)), *defines]
    elif args.platform == 'android':
        # flutter run may uninstall after a failed replacement install. Build
        # separately and use adb install -r exactly once instead.
        app = [args.flutter, 'build', 'apk', '--debug', '--no-pub', *defines]
        if args.android_target_platform:
            app += ['--target-platform', args.android_target_platform, '--split-per-abi']
    else:
        app = [args.flutter, 'run', '--debug', '-d', args.device, '--no-pub', *defines]
    return gateway, app


def verify_web_output(output, root=ROOT):
    """Fail closed on Flutter's successful-but-incomplete copied output.

    Flutter compares previous/current output *strings* during cleanup. Changing
    relative to absolute --output for the same directory can remove freshly
    copied files. Keep the helper's absolute path stable and verify the complete
    declared bundle before starting either server. Never borrow another build's
    assets or compiled application as a fallback.
    """
    root, output = Path(root).resolve(), Path(output).resolve()
    required = {'index.html', 'main.dart.js', 'flutter_bootstrap.js', 'flutter.js',
                'assets/AssetManifest.bin', 'assets/AssetManifest.bin.json',
                'assets/FontManifest.json', 'assets/assets/policy/manifest.json',
                'assets/assets/policy/catalog.json', 'assets/assets/policy/consumer_protection.json',
                'assets/assets/policy/live_sites.json', 'assets/assets/live_content/sources.json',
                'sqlite3.wasm', 'sqflite_sw.js', 'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm'}
    try:
        build_id = (output / '.last_build_id').read_text(encoding='ascii').strip()
        if not re.fullmatch(r'[a-f0-9]{32}', build_id):
            raise ValueError()
        metadata = root / '.dart_tool' / 'flutter_build' / build_id / 'outputs.json'
        if metadata.stat().st_size > 2 * 1024 * 1024:
            raise ValueError()
        outputs = json.loads(metadata.read_text(encoding='utf-8'))
        if not isinstance(outputs, list) or not outputs or len(outputs) > 10000:
            raise ValueError()
        for value in outputs:
            if not isinstance(value, str):
                raise ValueError()
            if '*' in value:
                continue  # Flutter includes templated index.html patterns.
            path = Path(value)
            if not path.is_absolute():
                path = root / path
            required.add(str(path.resolve().relative_to(output)))
        for source in (root / 'web').rglob('*'):
            if source.is_file() and source.name not in ('index.html', 'flutter_bootstrap.js'):
                required.add(str(source.relative_to(root / 'web')))
        missing = [name for name in sorted(required)
                   if not (output / name).is_file() or (output / name).stat().st_size == 0]
        if missing:
            raise LaunchError('Flutter reported success but the web bundle is incomplete (' + missing[0] +
                '). Rebuild using this helper with its unchanged absolute output path; no gateway was started.')
    except (OSError, UnicodeError, ValueError, TypeError):
        raise LaunchError('The Flutter web output manifest is missing or invalid. No gateway was started; '
                          'rebuild using this helper without changing its output path.') from None


class AppHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Paths can contain user-entered text: never log them.
    def list_directory(self, path):
        self.send_error(404)
        return None
    def end_headers(self):
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()


def wait_ready(process, port, *, connection=http.client.HTTPConnection, sleep=time.sleep, attempts=40):
    for _ in range(attempts):
        if process.poll() is not None:
            raise LaunchError('The local gateway exited. Inspect its sanitized startup diagnostic.')
        try:
            c = connection('127.0.0.1', port, timeout=.5)
            try:
                c.request('GET', '/healthz')
                r = c.getresponse()
                body = r.read(4096)
                if r.status == 200 and json.loads(body).get('mode') == 'local-live':
                    return
            finally:
                c.close()
        except (OSError, http.client.HTTPException, ValueError):
            pass
        sleep(.1)
    raise LaunchError('The local gateway did not become ready. No search was submitted.')


def stop_child(process):
    if process is not None and process.poll() is None:
        # Every child starts a new session. Never signal a port owner or a
        # caller-supplied PID; this group belongs solely to this invocation.
        with contextlib.suppress(ProcessLookupError):
            os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)


def launch(args, *, root=ROOT, run=subprocess.run, popen=subprocess.Popen,
           check_port=port_available, readiness=wait_ready, server_factory=ThreadingHTTPServer,
           stop=stop_child, sleep=time.sleep, verify_web=verify_web_output):
    gateway_cmd, app_cmd = commands(args, root)
    if args.dry_run:
        print(json.dumps({'gatewayCommand': gateway_cmd, 'appCommand': app_cmd,
            'appUrl': args.origin if args.platform == 'web' else None,
            'actor': args.actor, 'initializesAllowance': False, 'automaticSearches': 0,
            'androidInstallCommand': ([args.adb, '-s', args.device, 'install', '-r',
                str(android_apk_path(args, root))]
                if args.platform == 'android' else None),
            'androidLaunchCommand': ([args.adb, '-s', args.device, 'shell', 'am', 'start', '-W', '-n', ANDROID_COMPONENT]
                if args.platform == 'android' else None)}, indent=2))
        return 0
    check_port(args.gateway_port)
    if args.platform == 'web':
        check_port(args.web_port)
    env = dict(os.environ, PYTHONPATH=str(root / 'backend'))
    gateway = native = server = thread = None
    owns_reverse = False
    try:
        # Compile endpoint configuration before exposing this build at its exact
        # origin. Release mode intentionally does not allow loopback HTTP.
        if args.platform in ('web', 'android'):
            result = run(app_cmd, cwd=root, check=False)
            if result.returncode:
                raise LaunchError('Flutter development build failed. The gateway was not started.')
        if args.platform == 'web':
            verify_web(web_output_directory(args, root), root)
            server = server_factory(('127.0.0.1', args.web_port),
                functools.partial(AppHandler, directory=str(web_output_directory(args, root))))
        elif args.platform == 'android':
            listing = run([args.adb, '-s', args.device, 'reverse', '--list'],
                          capture_output=True, text=True, check=True, timeout=10)
            local = f'tcp:{args.gateway_port}'
            mappings = [line.split()[-2:] for line in listing.stdout.splitlines() if line.strip()]
            existing = [row for row in mappings if len(row) == 2 and row[0] == local]
            if any(row[1] != local for row in existing):
                raise LaunchError('The selected Android reverse port already maps elsewhere; choose another port.')
            if not existing:
                run([args.adb, '-s', args.device, 'reverse', '--no-rebind', local, local], check=True, timeout=10)
                owns_reverse = True
        gateway = popen(gateway_cmd, cwd=root, env=env, start_new_session=True)
        readiness(gateway, args.gateway_port)
        print(json.dumps({'mode': 'local-live', 'actor': args.actor,
            'gateway': f'http://127.0.0.1:{args.gateway_port}',
            'app': args.origin if args.platform == 'web' else args.device,
            'status': f'http://127.0.0.1:{args.gateway_port}/statusz',
            'stop': 'Ctrl-C stops only this helper\'s children; app data and allowance remain.'}), flush=True)
        if server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            print(f'Open {args.origin} in your browser. No search is sent by startup.', flush=True)
            while gateway.poll() is None:
                sleep(.25)
            raise LaunchError('Gateway stopped; the app server is closing without restarting it.')
        if args.platform == 'android':
            run([args.adb, '-s', args.device, 'install', '-r',
                 str(android_apk_path(args, root))],
                check=True, timeout=180)
            run([args.adb, '-s', args.device, 'shell', 'am', 'start', '-W', '-n', ANDROID_COMPONENT],
                check=True, timeout=30)
            while gateway.poll() is None:
                sleep(.25)
            raise LaunchError('Gateway stopped; no replacement process or search was started.')
        native = popen(app_cmd, cwd=root, start_new_session=True)
        while native.poll() is None:
            if gateway.poll() is not None:
                raise LaunchError('Gateway stopped; the development app process is closing without retry.')
            sleep(.25)
        return native.returncode
    finally:
        if server:
            if thread:
                server.shutdown()
                thread.join(2)
            server.server_close()
        stop(native)
        stop(gateway)
        if owns_reverse:
            # Remove only the exact mapping created above on the explicit target.
            with contextlib.suppress(OSError, subprocess.SubprocessError):
                run([args.adb, '-s', args.device, 'reverse', '--remove', f'tcp:{args.gateway_port}'],
                    check=False, timeout=10)


def main(argv=None):
    def terminate_owned(_signum, _frame):
        raise KeyboardInterrupt()
    previous_term = signal.signal(signal.SIGTERM, terminate_owned)
    try:
        return launch(parse_args(argv))
    except KeyboardInterrupt:
        return 0
    except LaunchError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except (OSError, subprocess.SubprocessError):
        print('A local development command failed. Check the selected tool/device and sanitized output.', file=sys.stderr)
        return 2
    finally:
        signal.signal(signal.SIGTERM, previous_term)


if __name__ == '__main__':
    raise SystemExit(main())
