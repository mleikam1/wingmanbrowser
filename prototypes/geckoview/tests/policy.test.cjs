const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {webcrypto} = require('node:crypto');
const root = path.resolve(__dirname, '../../..');
const extension = path.join(root, 'prototypes/geckoview/overlay/android/app/src/main/assets/wingman-policy');
const api = require(path.join(extension, 'policy.js'));
const baselineBytes = fs.readFileSync(path.join(root, 'assets/policy/consumer_protection.json'));
const baseline = JSON.parse(baselineBytes);
const fixture = JSON.parse(fs.readFileSync(path.join(root, 'test/fixtures/strict_search_cases.json')));

for (const c of fixture.cases) test('shared strict search: ' + c.operation + ': ' + c.name, () => {
  if (c.throwsFormatException) assert.throws(() => api[c.operation](c.input));
  else assert.equal(api[c.operation](c.input), c.expected);
});

test('actual pinned baseline: every mandatory synthetic category and neutral controls', () => {
  const policy = api.createPolicy(baseline);
  for (const category of api.CATEGORIES) {
    const host = baseline.categories[category].find(h => h.endsWith('.protection.test'));
    assert.ok(host, category);
    assert.equal(policy.decide('https://' + host + '/').cancel, true, category);
    assert.equal(policy.decide('https://sub.' + host + './').cancel, true, category);
  }
  for (const raw of ['https://www.espn.com/nfl/', 'https://www.walmart.com/', 'https://www.cancer.gov/', 'https://www.samhsa.gov/', 'https://unclassified-neutral.test/']) assert.equal(policy.decide(raw).cancel, undefined, raw);
});
test('path equivalents and neutral education have the same policy', () => {
  const policy = api.createPolicy(baseline);
  for (const suffix of ['/promotion/alcohol', '/promotion//alcohol', '//promotion/alcohol', '/promotion/%61lcohol', '/promotion/%41lcohol', '/promotion%2falcohol', '/promotion/x/../alcohol', '/promotion/%2e/alcohol']) assert.equal(policy.decide('https://mixed.protection.test' + suffix, {document:false}).cancel, true, suffix);
  for (const suffix of ['/promotion/alcoholic', '/education/alcohol']) assert.equal(policy.decide('https://mixed.protection.test' + suffix, {document:false}).cancel, undefined);
});
test('additional domains apply to every hop and documents stay exact', () => {
  const policy = api.createPolicy(baseline);
  policy.setRestrictions({blockedDomains:['blocked-neutral.test'], blockedUrls:['https://document-neutral.test/hidden'], searchBlocked:false});
  assert.equal(policy.decide('https://allowed-neutral.test/redirect', {document:false}).cancel, undefined);
  assert.equal(policy.decide('https://blocked-neutral.test/image.png', {document:false}).cancel, true);
  assert.equal(policy.decide('https://sub.blocked-neutral.test/image.png', {document:false}).cancel, true);
  assert.equal(policy.decide('https://document-neutral.test/hidden#saved').cancel, true);
  assert.equal(policy.decide('https://document-neutral.test/other').cancel, undefined);
  assert.throws(() => policy.setRestrictions({blockedDomains:[''], blockedUrls:[], searchBlocked:false}));
  assert.equal(policy.decide('https://blocked-neutral.test/image.png').cancel, true);
});
test('strict searches, result wrappers, suggestions and POST methods retain boundaries', () => {
  const policy = api.createPolicy(baseline);
  assert.equal(policy.decide('https://www.google.com/search?q=moon').redirectUrl, api.buildQuery('moon'));
  assert.equal(policy.decide('https://www.google.com/search?q=moon', {method:'POST'}).cancel, true);
  assert.equal(policy.decide('https://safe.duckduckgo.com/?q=moon&kp=-2', {method:'POST'}).cancel, undefined);
  assert.equal(policy.decide('https://safe.duckduckgo.com/ac/?q=moon', {document:false}).cancel, true);
  assert.equal(policy.decide('https://duckduckgo.com/l/?uddg=' + encodeURIComponent('https://mixed.protection.test/promotion/alcohol')).cancel, true);
  assert.equal(policy.decide('https://duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2F&next=evil').cancel, true);
  policy.setRestrictions({blockedDomains:[], blockedUrls:[], searchBlocked:true});
  assert.equal(policy.decide(api.buildQuery('moon')).cancel, true);
});
test('invalid URLs, credentials and absent category data never authorize requests', () => {
  const policy = api.createPolicy(baseline);
  for (const raw of ['https://user:pass@example.com/', 'https://example.com/%FF', 'https://example.com/%00', 'https://%65xample.com/', 'javascript:alert(1)', 'file:///tmp/private']) assert.equal(policy.decide(raw).cancel, true);
  const broken = {...baseline, categories:{...baseline.categories, gambling:[]}};
  assert.throws(() => api.createPolicy(broken));
});
test('tracker requests include service worker/background scope and preserve same-host resources', () => {
  const policy = api.createPolicy(baseline), host = baseline.trackers.find(h => !baseline.categories['security-threat'].includes(h));
  assert.equal(policy.decide('https://' + host + '/pixel', {document:false, initiator:'https://neutral.test/'}).cancel, true);
  assert.equal(policy.decide('https://' + host + '/pixel', {document:false, initiator:null}).cancel, true);
  assert.equal(policy.decide('https://' + host + '/pixel', {document:false, initiator:'https://' + host + '/page'}).cancel, undefined);
});
test('neutral WebSocket handshakes are resource-only and never rewrite transport', () => {
  const policy = api.createPolicy(baseline);
  for (const raw of ['ws://neutral.test/socket', 'wss://neutral.test/socket', 'WSS://neutral.test:8443/socket']) {
    assert.deepEqual(policy.decide(raw, {document:false, initiator:'https://neutral.test/'}), {reason:'permitted'});
    assert.equal(policy.decide(raw).cancel, true);
  }
});
test('WebSocket handshakes retain mandatory domain/path and additional domain decisions', () => {
  const policy = api.createPolicy(baseline);
  policy.setRestrictions({blockedDomains:['blocked-neutral.test'], blockedUrls:[], searchBlocked:false});
  for (const scheme of ['ws', 'wss']) {
    for (const category of api.CATEGORIES) {
      const host = baseline.categories[category].find(h => h.endsWith('.protection.test'));
      assert.equal(policy.decide(scheme + '://' + host + '/socket', {document:false}).reason, 'mandatory-category');
    }
    assert.equal(policy.decide(scheme + '://mixed.protection.test/promotion/%61lcohol', {document:false}).reason, 'mandatory-category');
    assert.equal(policy.decide(scheme + '://sub.blocked-neutral.test/socket', {document:false}).reason, 'additional-domain');
  }
});
test('WebSocket handshakes retain tracker, credential and malformed-address boundaries', () => {
  const policy = api.createPolicy(baseline), host = baseline.trackers.find(h => !baseline.categories['security-threat'].includes(h));
  assert.equal(policy.decide('wss://' + host + '/socket', {document:false, initiator:'https://neutral.test/'}).reason, 'tracker');
  assert.equal(policy.decide('wss://' + host + '/socket', {document:false, initiator:null}).reason, 'tracker');
  assert.equal(policy.decide('wss://' + host + '/socket', {document:false, initiator:'https://' + host + '/page'}).cancel, undefined);
  for (const raw of ['wss://user:secret@neutral.test/socket', 'wss://neutral.test/%FF', 'wss://neutral.test:0/socket', 'wss://%6eeutral.test/socket']) {
    assert.equal(policy.decide(raw, {document:false}).cancel, true);
  }
});

function backgroundHarness(bytes = baselineBytes) {
  let listener, onMessage, onDisconnect, resolveFetch, postingFails = false;
  const messages = [], registrations = [];
  const port = {postMessage:m => {if (postingFails) throw new Error('disconnected'); messages.push(m);}, onMessage:{addListener:f => {onMessage = f;}}, onDisconnect:{addListener:f => {onDisconnect = f;}}};
  const context = vm.createContext({URL, TextEncoder, TextDecoder, crypto:webcrypto,
    browser:{runtime:{getURL:p => 'moz-extension://policy/' + p, connectNative:name => {assert.equal(name, 'wingman_policy'); return port;}}, webRequest:{onBeforeRequest:{addListener:(f, filter, options) => {listener = f; registrations.push({filter, options});}}}},
    fetch:() => new Promise(resolve => {resolveFetch = () => resolve({ok:true, arrayBuffer:async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)});})});
  vm.runInContext(fs.readFileSync(path.join(extension, 'policy.js'), 'utf8'), context);
  vm.runInContext(fs.readFileSync(path.join(extension, 'background.js'), 'utf8'), context);
  const request = detail => JSON.parse(JSON.stringify(listener({type:'image', method:'GET', url:'https://neutral.test/image', tabId:-1, ...detail})));
  const configure = (revision = 1, extra = {}) => onMessage({type:'configure', protocol:1, edition:'consumer', revision, restrictions:{blockedDomains:['blocked-neutral.test'], blockedUrls:[], searchBlocked:false}, ...extra});
  return {messages, registrations, request, configure, failPosting:() => {postingFails = true;}, suspend:() => onMessage({type:'suspend', protocol:1}), disconnect:() => onDisconnect(), resolveFetch:() => resolveFetch()};
}
async function waitFor(check) { for (let i = 0; i < 200; i++) { if (check()) return; await new Promise(r => setTimeout(r, 10)); } assert.fail('background initialization did not complete'); }
test('background registers synchronously, validates asset, gates native configuration and disconnect', async () => {
  const h = backgroundHarness();
  assert.equal(h.registrations.length, 1);
  assert.deepEqual(JSON.parse(JSON.stringify(h.registrations)), [{filter:{urls:['<all_urls>']}, options:['blocking']}]);
  assert.deepEqual(h.request({}), {cancel:true});
  h.configure(); assert.deepEqual(h.request({}), {cancel:true});
  h.resolveFetch(); await waitFor(() => h.messages.some(m => m.type === 'ready'));
  const ready = h.messages.find(m => m.type === 'ready');
  assert.equal(ready.revision, 1); assert.equal(ready.sequence, 1); assert.equal(ready.purpose, 'consumer-policy');
  assert.deepEqual(h.request({}), {});
  // Simulates the second callback in a redirect chain; runtime must independently prove it occurs.
  assert.deepEqual(h.request({url:'https://blocked-neutral.test/image', tabId:-1}), {cancel:true});
  assert.deepEqual(h.request({url:'https://blocked-neutral.test/image', incognito:true}), {cancel:true});
  h.suspend(); assert.deepEqual(h.request({}), {cancel:true});
  h.configure(2); assert.deepEqual(h.request({}), {});
  h.disconnect(); assert.deepEqual(h.request({}), {cancel:true});
});
test('bad baseline or replayed/malformed configuration stays closed', async () => {
  const bad = backgroundHarness(Buffer.from('{}')); bad.configure(); bad.resolveFetch();
  await waitFor(() => bad.messages.some(m => m.type === 'error')); assert.deepEqual(bad.request({}), {cancel:true});
  const h = backgroundHarness(); h.configure(); h.resolveFetch(); await waitFor(() => h.messages.some(m => m.type === 'ready'));
  h.configure(1); assert.deepEqual(h.request({}), {cancel:true});
  h.configure(2, {edition:'student'}); assert.deepEqual(h.request({}), {cancel:true});
  h.configure(3, {restrictions:{blockedDomains:['good.test', 'https://evil.test'], blockedUrls:[], searchBlocked:false}}); assert.deepEqual(h.request({}), {cancel:true});
  h.configure(4); assert.deepEqual(h.request({}), {});
});
test('manifest has no page content scripts or native content-message permission', () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(extension, 'manifest.json')));
  assert.equal(manifest.content_scripts, undefined);
  assert.equal(manifest.permissions.includes('nativeMessagingFromContent'), false);
  assert.equal(manifest.background.persistent, true);
  assert.equal(manifest.browser_specific_settings.gecko.id, 'wingman-policy@wingmanbrowser.test');
});
test('lost ready acknowledgement closes request gate before disconnect callback', async () => {
  const h = backgroundHarness(); h.configure(); h.resolveFetch(); await waitFor(() => h.messages.some(m => m.type === 'ready'));
  h.failPosting(); h.configure(2); assert.deepEqual(h.request({}), {cancel:true});
});
