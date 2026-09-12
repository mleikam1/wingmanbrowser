/* Isolated engine-comparison policy. No remote code, page bridge or URL logging. */
(function (root) {
  'use strict';
  const CATEGORIES = ['sexual-explicit', 'gambling', 'alcohol-promotion', 'recreational-drug-promotion', 'tobacco-nicotine', 'security-threat'];
  const DDG = new Set(['duckduckgo.com', 'www.duckduckgo.com', 'safe.duckduckgo.com', 'html.duckduckgo.com', 'lite.duckduckgo.com', 'noai.duckduckgo.com', 'start.duckduckgo.com']);
  const ALIASES = new Set(['duck.com', 'www.duck.com', 'ddg.gg']);
  const ALTERNATIVES = new Set(['google.com', 'www.google.com', 'bing.com', 'www.bing.com', 'search.brave.com', 'safe.search.brave.com']);
  const SEARCH_PATHS = new Set(['', '/', '/html', '/html/', '/lite', '/lite/']);
  const ALT_PATHS = new Set(['', '/', '/search', '/images/search', '/videos/search', '/images', '/videos', '/news', '/ask']);
  const parts = value => /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/([^/?#]*)([^?#]*)(?:\?([^#]*))?(?:#(.*))?$/.exec(value);
  const invalid = () => { throw new Error('invalid-policy-input'); };
  const control = value => [...value].some(c => { const n = c.codePointAt(0); return n <= 31 || (n >= 127 && n <= 159) || n === 0x61c || n === 0x200e || n === 0x200f || (n >= 0x2028 && n <= 0x202e) || (n >= 0x2066 && n <= 0x2069); });
  function unicode(value) {
    if (typeof value !== 'string') invalid();
    for (const c of value) { const n = c.codePointAt(0); if (n >= 0xd800 && n <= 0xdfff) invalid(); }
  }
  function urlText(value) {
    unicode(value);
    if (value.length > 16384 || /[\s\\]/u.test(value) || control(value) || /%(?![0-9a-fA-F]{2})/.test(value)) invalid();
    if (control(decodeURIComponent(value))) invalid();
  }
  function encode(value) { return encodeURIComponent(value).replace(/[!'()*]/g, c => '%' + c.charCodeAt(0).toString(16).toUpperCase()); }
  function queryValue(value) {
    unicode(value);
    if (value.length > 16384 || control(value)) invalid();
    const trim = /^[\u0020\u00a0\u1680\u2000-\u200a\u202f\u205f\u3000\ufeff]+|[\u0020\u00a0\u1680\u2000-\u200a\u202f\u205f\u3000\ufeff]+$/gu;
    value = value.replace(trim, '');
    if (!value || [...value].length > 512 || new TextEncoder().encode(value).length > 1024) invalid();
    let probe = value;
    for (let round = 0; round <= 8; round++) {
      probe = [...probe].map(c => { const n = c.codePointAt(0); return n >= 0xff01 && n <= 0xff5e ? String.fromCodePoint(n - 0xfee0) : n === 0xfe57 ? '!' : n === 0xfe68 ? '\\' : c; }).join('');
      if (control(probe) || /(^|[^a-zA-Z0-9_])![a-zA-Z0-9_]/.test(probe) || probe.trimStart().startsWith('\\')) invalid();
      if (!/(?:%[0-9a-fA-F]{2})+/.test(probe)) return value;
      if (round === 8) invalid();
      probe = probe.replace(/(?:%[0-9a-fA-F]{2})+/g, text => decodeURIComponent(text));
    }
    invalid();
  }
  function parseQuery(value) {
    if (!value || value.length > 16384) invalid();
    const fields = value.split('&'); if (fields.length > 64) invalid();
    const seen = new Set(), result = new Map();
    for (const field of fields) {
      const at = field.indexOf('='); if (at <= 0) invalid();
      const decode = s => { if (/%(?![0-9a-fA-F]{2})/.test(s)) invalid(); const v = decodeURIComponent(s.replace(/\+/g, ' ')); unicode(v); if (control(v)) invalid(); return v; };
      const key = decode(field.slice(0, at)), value = decode(field.slice(at + 1));
      if (!/^[a-zA-Z0-9_.-]{1,64}$/.test(key) || seen.has(key.toLowerCase())) invalid();
      seen.add(key.toLowerCase()); result.set(key, value);
    }
    return result;
  }
  function checkedURL(raw) {
    urlText(raw); const p = parts(raw); if (!p || p[2].includes('%') || p[2].includes('@')) invalid();
    const uri = new URL(raw); if (!['http:', 'https:'].includes(uri.protocol) || !uri.hostname || uri.username || uri.password || uri.port === '0') invalid();
    uri.hostname = uri.hostname.toLowerCase().replace(/\.$/, '');
    return uri;
  }
  function buildQuery(value) { return 'https://safe.duckduckgo.com/?q=' + encode(queryValue(value)) + '&kp=1&kac=-1'; }
  function rewriteProviderInput(raw) {
    unicode(raw); if (raw.length > 16384) invalid();
    const p = parts(raw); if (!p) return null; urlText(raw);
    const uri = new URL(raw), host = uri.hostname.toLowerCase().replace(/\.$/, '');
    const ddg = host === 'duckduckgo.com' || host.endsWith('.duckduckgo.com') || ALIASES.has(host);
    if (!ddg && !ALTERNATIVES.has(host)) return null;
    checkedURL(raw); if (uri.port || p[2].includes('%')) invalid();
    const path = p[3];
    if (!(ddg ? SEARCH_PATHS : ALT_PATHS).has(path)) {
      if (path.includes('%') || path.split('/').some(s => s === '.' || s === '..')) invalid();
      return null;
    }
    if (ddg && !DDG.has(host) && !ALIASES.has(host)) invalid();
    const values = p[4] ? parseQuery(p[4]) : new Map();
    if ([...values.keys()].some(k => k.toLowerCase() === 'q' && k !== 'q')) invalid();
    if (values.has('q')) values.set('q', queryValue(values.get('q')));
    if (!ddg) return values.has('q') ? buildQuery(values.get('q')) : 'https://safe.duckduckgo.com/?kp=1&kac=-1';
    for (const key of values.keys()) if (['kp', 'kac'].includes(key.toLowerCase())) values.delete(key);
    values.set('kp', '1'); values.set('kac', '-1');
    return 'https://safe.duckduckgo.com' + (path || '/') + '?' + [...values].map(([k, v]) => encode(k) + '=' + encode(v)).join('&');
  }
  function acceptsCanonical(raw) {
    try {
      const uri = checkedURL(raw), p = parts(raw);
      if (uri.protocol !== 'https:' || uri.hostname !== 'safe.duckduckgo.com' || uri.port || !SEARCH_PATHS.has(p[3]) || !p[3] || p[5] !== undefined) return false;
      const q = parseQuery(p[4]); if (q.get('kp') !== '1' || q.get('kac') !== '-1') return false;
      if (q.has('q')) queryValue(q.get('q')); return true;
    } catch (_) { return false; }
  }
  function unwrapResultLink(raw) {
    try {
      const uri = checkedURL(raw), p = parts(raw);
      if (!DDG.has(uri.hostname) || uri.protocol !== 'https:' || /:\d+$/.test(p[2]) || p[3] !== '/l/' || p[5] !== undefined) return null;
      const q = parseQuery(p[4]);
      if (!q.has('uddg') || [...q.keys()].some(k => !['uddg', 'rut'].includes(k)) || (q.has('rut') && !/^[A-Za-z0-9_-]{1,128}$/.test(q.get('rut')))) return null;
      const rawTarget = q.get('uddg'); if (!rawTarget || new TextEncoder().encode(rawTarget).length > 4096) return null;
      const target = checkedURL(rawTarget), t = parts(rawTarget);
      if (target.protocol !== 'https:' || /:\d+$/.test(t[2]) || (DDG.has(target.hostname) && target.pathname === '/l/')) return null;
      return target.href;
    } catch (_) { return null; }
  }
  function normalizedPath(uri) {
    const segments = [];
    for (const segment of decodeURIComponent(uri.pathname).toLowerCase().split('/')) {
      if (segment === '..') segments.pop(); else if (segment && segment !== '.') segments.push(segment);
    }
    return '/' + segments.join('/');
  }
  const domain = value => typeof value === 'string' && value.length <= 253 && value.includes('.') && value.split('.').every(p => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(p));
  const matches = (host, value) => host === value || host.endsWith('.' + value);
  const suffixes = host => { const values = []; for (let value = host; value; value = value.includes('.') ? value.slice(value.indexOf('.') + 1) : '') values.push(value); return values; };
  function restrictions(value) {
    if (!value || typeof value !== 'object' || !Array.isArray(value.blockedDomains) || !Array.isArray(value.blockedUrls) || typeof value.searchBlocked !== 'boolean' || value.blockedDomains.length > 5000 || value.blockedUrls.length > 5000) invalid();
    if (!value.blockedDomains.every(domain)) invalid();
    return {domains: new Set(value.blockedDomains), urls: new Set(value.blockedUrls.map(raw => { const uri = checkedURL(raw); uri.hash = ''; return uri.href; })), searchBlocked: value.searchBlocked};
  }
  function createPolicy(data) {
    if (!data || data.schemaVersion !== 1 || data.sequence !== 1 || !data.categories || Object.keys(data.categories).length !== 6 || !Array.isArray(data.pathRules) || !Array.isArray(data.trackers)) invalid();
    const domains = new Map();
    for (const category of CATEGORIES) {
      const values = data.categories[category];
      if (!Array.isArray(values) || !values.length || values.length > 500000 || !values.every(domain)) invalid();
      for (const host of values) domains.set(host, category);
    }
    const paths = data.pathRules.map(r => {
      if (!domain(r.host) || typeof r.pathPrefix !== 'string' || !r.pathPrefix.startsWith('/') || /[%?#]/.test(r.pathPrefix) || !CATEGORIES.includes(r.category)) invalid();
      return {host:r.host, path:r.pathPrefix.toLowerCase().replace(/\/$/, ''), category:r.category};
    });
    if (!data.trackers.every(domain)) invalid(); const trackers = new Set(data.trackers);
    let limits = restrictions({blockedDomains:[], blockedUrls:[], searchBlocked:false});
    return {
      setRestrictions(value) { limits = restrictions(value); },
      decide(raw, {document = true, initiator = null, method = 'GET'} = {}) {
        try {
          const socket = typeof raw === 'string' && /^wss?:\/\//i.test(raw);
          if (socket && document) return {cancel:true, reason:'unsupported-navigation-scheme'};
          // Compare a handshake's host/path with the same HTTP(S) policy. This
          // local comparison never redirects the socket or changes its transport;
          // Gecko still enforces TLS, mixed content, origin and protocol rules.
          const policyURL = socket ? raw.replace(/^ws(s?):/i, (_, secure) => secure ? 'https:' : 'http:') : raw;
          const original = checkedURL(policyURL); let uri = original;
          if (document && (DDG.has(uri.hostname) || ALIASES.has(uri.hostname)) && uri.pathname === '/l/') {
            const target = unwrapResultLink(raw); if (!target) return {cancel:true, reason:'unsupported-wrapper'}; uri = checkedURL(target);
          }
          if (document) { const rewritten = rewriteProviderInput(uri.href); if (rewritten) uri = checkedURL(rewritten); }
          const host = uri.hostname, path = normalizedPath(uri);
          const category = suffixes(host).map(s => domains.get(s)).find(Boolean) || paths.find(r => matches(host, r.host) && (path === r.path || path.startsWith(r.path + '/')))?.category;
          if (category) return {cancel:true, reason:'mandatory-category'};
          if (suffixes(host).some(s => limits.domains.has(s))) return {cancel:true, reason:'additional-domain'};
          const documentUrl = new URL(uri.href); documentUrl.hash = '';
          if (document && limits.urls.has(documentUrl.href)) return {cancel:true, reason:'additional-document'};
          const ddg = host === 'duckduckgo.com' || host.endsWith('.duckduckgo.com');
          if (limits.searchBlocked && (ddg || ALIASES.has(host) || ALTERNATIVES.has(host))) return {cancel:true, reason:'additional-search'};
          if (ddg && (path === '/ac' || path.startsWith('/ac/'))) return {cancel:true, reason:'suggestions-disabled'};
          let initiatorHost = null; try { if (initiator) initiatorHost = checkedURL(initiator).hostname; } catch (_) {}
          if (!document && host !== initiatorHost && suffixes(host).some(s => trackers.has(s))) return {cancel:true, reason:'tracker'};
          if (document && uri.href !== original.href) {
            if (method === 'GET') return {redirectUrl:uri.href, reason:'normalized-navigation'};
            if (!(original.protocol === 'https:' && original.hostname === 'safe.duckduckgo.com' && SEARCH_PATHS.has(original.pathname))) return {cancel:true, reason:'unsupported-search-method'};
          }
          return {reason:'permitted'};
        } catch (_) { return {cancel:true, reason:'invalid-address'}; }
      }
    };
  }
  const api = {CATEGORIES, createPolicy, restrictions, checkedURL, buildQuery, rewriteProviderInput, acceptsCanonical, unwrapResultLink};
  root.WingmanPolicy = Object.freeze(api);
  if (typeof module !== 'undefined') module.exports = api;
})(globalThis);
