"""Finite public request/response contracts. No provider metadata passthrough."""
import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from urllib.parse import urlsplit
from wingman_content.normalize import plain, date_value, iso
from .policy import query_allowed, ad_context

class SearchError(Exception):
    def __init__(self, code, http_status=400, provider_status=None, *, provider_code=None):
        super().__init__(code)
        self.code, self.http_status = code, http_status
        self.provider_status = provider_status
        self.provider_code = provider_code if isinstance(provider_code, str) and provider_code in {'INTERNAL', 'QUOTA_LIMITED', 'RATE_LIMITED'} else None

# An intentionally bounded initial supported-locale subset, not arbitrary input.
LOCALES = {'US': ('en', 'en-US'), 'GB': ('en', 'en-GB'), 'CA': ('en', 'en-CA'),
           'AU': ('en', 'en-AU'), 'DE': ('de', 'de-DE'), 'FR': ('fr', 'fr-FR'),
           'ES': ('es', 'es-ES')}

@dataclass(frozen=True, repr=False)
class SearchRequest:
    query: str
    kind: str = 'web'
    country: str = 'US'
    search_lang: str = 'en'
    ui_lang: str = 'en-US'
    offset: int = 0
    context: str = 'normal'

    @classmethod
    def parse(cls, raw):
        allowed = {'query', 'kind', 'country', 'searchLang', 'uiLang', 'offset', 'context'}
        if not isinstance(raw, dict) or set(raw) - allowed:
            raise SearchError('unsupported-parameters')
        q = raw.get('query')
        try:
            query_bytes = len(q.encode('utf-8')) if isinstance(q, str) else 0
        except UnicodeError:
            raise SearchError('invalid-query') from None
        if (not isinstance(q, str) or not q.strip() or len(q) > 400 or len(q.split()) > 50
                or query_bytes > 1600 or re.search(r'[\x00-\x1f\x7f]', q)):
            raise SearchError('invalid-query')
        kind, country = raw.get('kind', 'web'), raw.get('country', 'US')
        language, ui = raw.get('searchLang', 'en'), raw.get('uiLang', 'en-US')
        offset, context = raw.get('offset', 0), raw.get('context', 'normal')
        if kind not in ('web', 'news') or type(offset) is not int or not 0 <= offset <= 9:
            raise SearchError('invalid-page')
        if not isinstance(country, str) or LOCALES.get(country) != (language, ui):
            raise SearchError('unsupported-locale')
        if context not in ('normal', 'private', 'managed'):
            raise SearchError('invalid-context')
        if context == 'managed':
            raise SearchError('managed-search-unavailable', 403)
        if not query_allowed(q):
            raise SearchError('policy-blocked', 403)
        return cls(q, kind, country, language, ui, offset, context)

    def provider_params(self, count=20):
        if type(count) is not int or not 1 <= count <= (20 if self.kind == 'web' else 50):
            raise SearchError('invalid-count')
        result = dict(q=self.query, country=self.country, search_lang=self.search_lang,
                      ui_lang=self.ui_lang, safesearch='strict', count=count, offset=self.offset)
        if self.kind == 'web':
            result.update(result_filter='web', text_decorations='false')
        return result

def _pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate-json-key')
        result[key] = value
    return result

def decode_json(body, limit=1024 * 1024):
    if not isinstance(body, bytes) or len(body) > limit:
        raise SearchError('malformed-response', 502)
    try:
        return json.loads(body.decode('utf-8'), object_pairs_hook=_pairs,
                          parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
    except (ValueError, UnicodeError, RecursionError):
        raise SearchError('malformed-response', 502) from None

def parse_results(body, request, policy, *, count=20, fixture=False, now=None):
    raw = decode_json(body)
    if not isinstance(raw, dict):
        raise SearchError('malformed-response', 502)
    container = raw.get('web') if request.kind == 'web' else raw
    # The official Web schema declares web nullable. An empty/null block needs
    # valid query metadata; a differently typed block is a schema failure.
    if container is None and request.kind == 'web' and isinstance(raw.get('query'), dict):
        rows = []
    elif isinstance(container, dict) and isinstance(container.get('results'), list):
        rows = container['results']
    else:
        raise SearchError('malformed-response', 502)
    if len(rows) > (20 if request.kind == 'web' else 50):
        raise SearchError('malformed-response', 502)
    query = raw.get('query')
    query = {} if query is None else query
    if not isinstance(query, dict):
        raise SearchError('malformed-response', 502)
    results, seen, filtered = [], set(), 0
    for row in rows:
        if (not isinstance(row, dict) or not isinstance(row.get('title'), str)
                or not isinstance(row.get('url'), str)
                or row.get('description') is not None and not isinstance(row.get('description'), str)):
            raise SearchError('malformed-response', 502)
        raw_description = row.get('description') or ''
        if len(row['title']) > 10000 or len(raw_description) > 20000:
            raise SearchError('malformed-response', 502)
        title = plain(row['title'], 500)
        description = plain(raw_description, 1600)
        url = row['url']
        if row.get('family_friendly') is False or not policy.allows_result(plain(row['title'], 10000), plain(raw_description, 20000), url):
            filtered += 1
            continue
        if url in seen:
            continue
        seen.add(url)
        item = dict(title=title, url=url, description=description, source=urlsplit(url).hostname)
        if request.kind == 'news':
            # age/page_age are not reliable publication timestamps.
            try:
                page_date = date_value(row.get('page_age'))
                fetched = date_value(row.get('page_fetched'))
            except (ValueError, OverflowError, TypeError):
                raise SearchError('malformed-response', 502) from None
            current = now or datetime.now(timezone.utc)
            item.update(publishedAt=None, discoveredAt=None,
                        pageDate=iso(page_date) if page_date and page_date <= current else None,
                        providerFetchedAt=iso(fetched) if fetched and fetched <= current else None)
        results.append(item)
    more = (query.get('more_results_available') is True if request.kind == 'web' else len(rows) == count)
    # A supplied alteration is reevaluated only in memory and never returned.
    altered = query.get('altered')
    intent = (ad_context(request.query, altered=altered)
              if results and request.context == 'normal'
              and (altered is None or isinstance(altered, str)) else None)
    return dict(schemaVersion=1, kind=request.kind, status='ok' if results else 'filtered' if filtered else 'empty',
                results=results, moreAvailable=bool(more and request.offset < 9),
                provider='Brave Search', fixture=fixture), intent
