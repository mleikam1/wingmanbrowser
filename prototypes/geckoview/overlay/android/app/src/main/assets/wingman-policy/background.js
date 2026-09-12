/* Register before any asynchronous work: initial, redirected and background requests share this gate. */
(function () {
  'use strict';
  const SHA256 = 'f397d8f87a02fbb7754ce9c77931f740ba10271370e1e09f8402607bef59098f';
  let policy = null, port = null, configured = null, ready = false, highestRevision = 0;
  const counters = {allowed:0, blocked:0, rewritten:0};
  browser.webRequest.onBeforeRequest.addListener(details => {
    if (details.url.startsWith(browser.runtime.getURL(''))) return {};
    if (!ready || !policy || !port) { counters.blocked++; return {cancel:true}; }
    const decision = policy.decide(details.url, {
      document:details.type === 'main_frame' || details.type === 'sub_frame',
      initiator:details.originUrl || details.documentUrl || null,
      method:details.method
    });
    if (decision.cancel) { counters.blocked++; return {cancel:true}; }
    if (decision.redirectUrl) { counters.rewritten++; return {redirectUrl:decision.redirectUrl}; }
    counters.allowed++; return {};
  }, {urls:['<all_urls>']}, ['blocking']);
  function reply(message) {
    if (!port) return;
    try { port.postMessage(message); }
    catch (_) { ready = false; configured = null; port = null; }
  }
  function activate() {
    if (!policy || !configured || !port) return;
    policy.setRestrictions(configured.restrictions);
    ready = true;
    reply({type:'ready', protocol:1, revision:configured.revision, sequence:1, sha256:SHA256, purpose:'consumer-policy'});
  }
  try {
    port = browser.runtime.connectNative('wingman_policy');
    port.onDisconnect.addListener(() => { ready = false; configured = null; port = null; });
    port.onMessage.addListener(message => {
      if (message?.type === 'diagnostics') { reply({type:'diagnostics', protocol:1, ready, ...counters}); return; }
      ready = false; configured = null;
      if (message?.type === 'suspend' && message.protocol === 1) { reply({type:'suspended', protocol:1, revision:highestRevision}); return; }
      try {
        if (message?.type !== 'configure' || message.protocol !== 1 || message.edition !== 'consumer' || !Number.isSafeInteger(message.revision) || message.revision <= highestRevision) throw new Error('configuration');
        WingmanPolicy.restrictions(message.restrictions);
        highestRevision = message.revision; configured = message; activate();
      } catch (_) { reply({type:'error', protocol:1, code:'configuration-rejected'}); }
    });
    reply({type:'hello', protocol:1});
  } catch (_) { ready = false; port = null; }
  (async () => {
    try {
      const response = await fetch(browser.runtime.getURL('baseline.json'));
      if (!response.ok) throw new Error('asset');
      const bytes = await response.arrayBuffer(); if (bytes.byteLength < 100 || bytes.byteLength > 16 * 1024 * 1024) throw new Error('size');
      const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(n => n.toString(16).padStart(2, '0')).join('');
      if (hash !== SHA256) throw new Error('digest');
      policy = WingmanPolicy.createPolicy(JSON.parse(new TextDecoder('utf-8', {fatal:true}).decode(bytes))); activate();
    } catch (_) { ready = false; policy = null; reply({type:'error', protocol:1, code:'mandatory-baseline-invalid'}); }
  })();
})();
