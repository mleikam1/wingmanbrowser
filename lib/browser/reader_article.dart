/// An ephemeral plain-text view of content the person explicitly chose to read.
class ReaderArticle {
  const ReaderArticle({
    required this.title,
    required this.text,
    required this.sourceUrl,
  });
  final String title;
  final String text;
  final String sourceUrl;
}

// Runs only after the user requests Reader. No network, storage, message bridge,
// HTML serialization, input values, subframes or hidden-content extraction.
const readerExtractionScript = r"""
(() => {
  const excluded = new Set(['SCRIPT','STYLE','NOSCRIPT','TEMPLATE','IFRAME',
    'FRAME','OBJECT','EMBED','CANVAS','SVG','FORM','INPUT','TEXTAREA','SELECT',
    'OPTION','BUTTON','DATALIST','OUTPUT','LABEL','NAV','ASIDE','FOOTER']);
  const blocks = new Set(['P','DIV','SECTION','ARTICLE','MAIN','H1','H2','H3',
    'H4','H5','H6','LI','BLOCKQUOTE','PRE','BR']);
  const deadline = performance.now() + 150;
  let budget = 12000;
  function rendered(el) {
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return !el.hidden && !el.inert && s.display !== 'none' &&
      s.visibility === 'visible' && s.contentVisibility !== 'hidden' &&
      Number(s.opacity) !== 0 && r.width > 0 && r.height > 0;
  }
  function ancestorsAllowed(el, bounds) {
    let depth = 0;
    for (let a = el; a; a = a.parentElement) {
      if (++depth > 80 || !rendered(a) || excluded.has(a.tagName) ||
          a.isContentEditable || a.getAttribute('aria-hidden') === 'true') return false;
      const s = getComputedStyle(a);
      if (s.filter !== 'none' || s.clipPath !== 'none' || s.clip !== 'auto') return false;
      const r = a.getBoundingClientRect();
      if ((s.overflowX === 'hidden' || s.overflowX === 'clip') &&
          (bounds.left < r.left - .5 || bounds.right > r.right + .5)) return false;
      if ((s.overflowY === 'hidden' || s.overflowY === 'clip') &&
          (bounds.top < r.top - .5 || bounds.bottom > r.bottom + .5)) return false;
    }
    return true;
  }
  if (!document.body) return null;
  // Complete a bounded preflight before extraction: visible modal content makes
  // Reader unavailable, rather than revealing the article behind the dialog.
  const roots = [];
  const scan = document.createTreeWalker(document.body, NodeFilter.SHOW_ALL);
  let node = scan.currentNode;
  while (node) {
    if (--budget < 0 || performance.now() > deadline) return null;
    if (node.nodeType === Node.ELEMENT_NODE) {
      const style = getComputedStyle(node);
      const bounds = node.getBoundingClientRect();
      if (rendered(node) && ['fixed','sticky','absolute'].includes(style.position) &&
          bounds.width > innerWidth * .5 && bounds.height > innerHeight * .2 &&
          bounds.bottom > 0 && bounds.top < innerHeight &&
          bounds.right > 0 && bounds.left < innerWidth) return null;
      if ((node.getAttribute('aria-modal') === 'true' ||
           (node.tagName === 'DIALOG' && node.open)) && rendered(node)) return null;
      if (roots.length < 8 && (node.tagName === 'ARTICLE' || node.tagName === 'MAIN' ||
          node.getAttribute('role') === 'main')) roots.push(node);
    }
    node = scan.nextNode();
  }
  let best = '';
  for (const root of roots) {
    if (!ancestorsAllowed(root, root.getBoundingClientRect())) continue;
    const parts = [];
    let length = 0;
    const walker = document.createTreeWalker(root,
      NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
        acceptNode(n) {
          if (--budget < 0 || performance.now() > deadline) throw new Error('Reader budget');
          if (n.nodeType === Node.ELEMENT_NODE &&
              (!ancestorsAllowed(n, n.getBoundingClientRect()))) return NodeFilter.FILTER_REJECT;
          return NodeFilter.FILTER_ACCEPT;
        }
      });
    node = walker.currentNode;
    while (node && length < 60000) {
      if (--budget < 0 || performance.now() > deadline) return null;
      if (node.nodeType === Node.TEXT_NODE && node.length > 0) {
        const count = Math.min(60000 - length, node.length);
        const range = document.createRange();
        range.setStart(node, 0); range.setEnd(node, count);
        if (ancestorsAllowed(node.parentElement, range.getBoundingClientRect())) {
          const text = node.substringData(0, count).replace(/\s+/g, ' ');
          parts.push(text); length += text.length;
        }
      } else if (node.nodeType === Node.ELEMENT_NODE && blocks.has(node.tagName)) {
        parts.push('\n\n'); length += 2;
      }
      node = walker.nextNode();
    }
    const text = parts.join('').replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim().slice(0, 60000);
    if (text.length > best.length) best = text;
  }
  if (best.length < 120) return null;
  return JSON.stringify({text:best, url:location.href});
})()
""";
