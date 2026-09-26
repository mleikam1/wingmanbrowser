"""Approved production adapter; never imported/started by the fixture runner.

The hosting boundary must reject duplicate framing headers, limit connections
and disable request/body/header logging. This module does not provision it.
"""
import json
from urllib.parse import urlsplit
from .contracts import SearchError, decode_json
from .config import load_rights
from .runtime import read_config, create_search_application
from .gateway import BurstGuard


class SearchWSGI:
    def __init__(self, app, config):
        config.validate()
        if config.environment != 'production':
            raise ValueError('production_configuration_required')
        self.app, self.config = app, config
        self.host = urlsplit(config.production_gateway_url).hostname
        self.guard = BurstGuard(limit=60)

    def __call__(self, environ, start_response):
        headers = [('Content-Type', 'application/json; charset=utf-8'),
                   ('Cache-Control', 'no-store, private'), ('Referrer-Policy', 'no-referrer'),
                   ('X-Content-Type-Options', 'nosniff'),
                   ('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none'")]
        status, value = 503, {'status': 'error', 'error': {'code': 'service-unavailable'}}
        try:
            self.config.validate()
            if (environ.get('HTTP_HOST') not in (self.host, self.host + ':443')
                    or environ.get('wsgi.url_scheme') != 'https'):
                raise SearchError('invalid-host', 403)
            if not self.guard.allow(None):
                raise SearchError('service-busy', 429)
            origin = environ.get('HTTP_ORIGIN')
            rights = load_rights(__import__('pathlib').Path(self.config.rights_register_path))
            if origin:
                if origin not in {'https://' + host for host in rights.get('approved_domains', [])}:
                    raise SearchError('origin-not-allowed', 403)
                headers.extend([('Access-Control-Allow-Origin', origin), ('Vary', 'Origin'),
                    ('Access-Control-Allow-Methods', 'POST, OPTIONS'),
                    ('Access-Control-Allow-Headers', 'Content-Type')])
            method = environ.get('REQUEST_METHOD')
            path = environ.get('PATH_INFO')
            if environ.get('QUERY_STRING'):
                raise SearchError('not-found', 404)
            if method == 'GET' and path == '/healthz':
                status, value = 200, {'status': 'ok', 'service': 'Wingman Search'}
            elif method == 'OPTIONS' and path in ('/v1/search', '/v1/ads/decision', '/v1/ads/event'):
                status, value = 200, {'status': 'ok'}
            elif method == 'POST' and path in ('/v1/search', '/v1/ads/decision', '/v1/ads/event'):
                length = environ.get('CONTENT_LENGTH', '')
                if (not length.isascii() or not length.isdecimal() or len(length) > 5
                        or not 2 <= int(length) <= 8192 or environ.get('HTTP_TRANSFER_ENCODING')):
                    raise SearchError('request-size', 413)
                if environ.get('CONTENT_TYPE', '').split(';')[0].strip() != 'application/json':
                    raise SearchError('json-required', 415)
                body = environ['wsgi.input'].read(int(length))
                if len(body) != int(length):
                    raise SearchError('invalid-request')
                try:
                    raw = decode_json(body, 8192)
                except SearchError:
                    raise SearchError('invalid-request') from None
                value = self.app.search(raw) if path == '/v1/search' else self.app.ad_request(path, raw)
                status = 200
            else:
                raise SearchError('not-found', 404)
        except SearchError as exc:
            status, value = exc.http_status, {'status': 'error', 'error': {'code': exc.code}}
        except Exception:
            pass  # No request-derived exception details reach response or logs.
        body = json.dumps(value, separators=(',', ':'), ensure_ascii=True).encode()
        headers.append(('Content-Length', str(len(body))))
        from http import HTTPStatus
        start_response(f'{status} {HTTPStatus(status).phrase}', headers)
        return [] if environ.get('REQUEST_METHOD') == 'HEAD' else [body]


def create_application(config_path):
    """Explicit path only; no gcloud/environment target inference or auto-init."""
    config = read_config(config_path)
    return SearchWSGI(create_search_application(config), config)
