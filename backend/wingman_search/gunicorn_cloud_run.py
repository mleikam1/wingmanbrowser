"""Explicit Cloud Run-only TLS boundary; never a general-host default.

Select with --config=python:wingman_search.gunicorn_cloud_run only when the
container port is reachable exclusively through Cloud Run's managed ingress.
The K_* check prevents accidental use elsewhere; it is not host attestation.
"""
import os
import re


def _require_cloud_run():
    for name in ('K_SERVICE', 'K_REVISION', 'K_CONFIGURATION'):
        if not re.fullmatch(r'[a-z][a-z0-9-]{0,62}', os.environ.get(name, '')):
            raise RuntimeError('cloud_run_environment_required')


_require_cloud_run()
_port = os.environ.get('PORT', '8080')
if not _port.isascii() or not _port.isdecimal() or not 1 <= int(_port) <= 65535:
    raise RuntimeError('cloud_run_port_invalid')

bind = ['0.0.0.0:' + str(int(_port))]
workers = 1
worker_class = 'gthread'
threads = 4
timeout = 30
limit_request_line = 1024
limit_request_fields = 30
limit_request_field_size = 2048
accesslog = '/dev/null'
errorlog = '/dev/null'
capture_output = False
disable_redirect_access_to_syslog = True
syslog = False

# Cloud Run terminates TLS and supplies this exact header. No alternate scheme
# headers or WSGI path/user overrides are trusted. Do not use on an exposed port.
forwarded_allow_ips = '*'
secure_scheme_headers = {'X-FORWARDED-PROTO': 'https'}
forwarder_headers = ''
header_map = 'refuse'
proxy_protocol = 'off'
protocol = 'http'

_fixed_settings = {name: value for name, value in list(globals().items())
                   if name in ('bind', 'workers', 'worker_class', 'threads', 'timeout',
                               'limit_request_line', 'limit_request_fields',
                               'limit_request_field_size', 'accesslog', 'errorlog',
                               'capture_output', 'disable_redirect_access_to_syslog',
                               'syslog', 'forwarded_allow_ips', 'secure_scheme_headers',
                               'forwarder_headers', 'header_map', 'proxy_protocol', 'protocol')}
# Gunicorn normalizes comma-separated address strings into lists.
_fixed_settings['forwarded_allow_ips'] = ['*']
_fixed_settings['forwarder_headers'] = []


def on_starting(server):
    """CLI/environment overrides must not silently weaken this deployment."""
    _require_cloud_run()
    if any(server.cfg.settings[name].get() != value
           for name, value in _fixed_settings.items()):
        raise RuntimeError('cloud_run_gunicorn_configuration_changed')
