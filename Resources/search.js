/* In-page find support for MacDown Lite.
 *
 * The host drives this from native UI (an NSSearchField overlay). We use the
 * CSS Custom Highlight API when available so we never mutate the DOM: injecting
 * <mark> elements would break Prism's highlighting and MathJax's SVG output.
 *
 * Falls back to Range-based scrolling when highlights are unavailable.
 */
(function () {
  'use strict';

  if (window.__macdownLiteSearch) return;

  var api = {
    ready: true,
    supportsHighlight: typeof CSS !== 'undefined' && CSS.highlights !== undefined &&
                       typeof Highlight !== 'undefined',
    count: 0,
    index: 0
  };

  var matches = [];
  var activeIndex = -1;
  var hlAll = null, hlActive = null;

  function collectMatches(query, caseSensitive) {
    matches = [];
    if (!query) return;
    var root = document.body;
    if (!root) return;

    var needle = caseSensitive ? query : query.toLowerCase();
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (node) {
        if (!node.nodeValue || !node.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
        var el = node.parentElement;
        if (!el) return NodeFilter.FILTER_REJECT;
        var tag = el.tagName;
        if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT') return NodeFilter.FILTER_REJECT;
        // Skip MathJax's generated containers: their text is glyph soup.
        if (el.closest && el.closest('mjx-container, .MathJax, .MathJax_Preview')) {
          return NodeFilter.FILTER_REJECT;
        }
        return NodeFilter.FILTER_ACCEPT;
      }
    });

    var n;
    while ((n = walker.nextNode())) {
      var hay = caseSensitive ? n.nodeValue : n.nodeValue.toLowerCase();
      var from = 0, at;
      while ((at = hay.indexOf(needle, from)) !== -1) {
        var r = document.createRange();
        r.setStart(n, at);
        r.setEnd(n, at + needle.length);
        matches.push(r);
        from = at + needle.length;
      }
    }
  }

  function clearHighlights() {
    if (api.supportsHighlight) {
      CSS.highlights.delete('mdl-find');
      CSS.highlights.delete('mdl-find-active');
    }
    hlAll = null; hlActive = null;
  }

  function paintHighlights() {
    if (!api.supportsHighlight) return;
    clearHighlights();
    if (!matches.length) return;
    hlAll = new Highlight();
    for (var i = 0; i < matches.length; i++) {
      if (i !== activeIndex) hlAll.add(matches[i]);
    }
    hlActive = new Highlight();
    if (activeIndex >= 0 && matches[activeIndex]) hlActive.add(matches[activeIndex]);
    CSS.highlights.set('mdl-find', hlAll);
    CSS.highlights.set('mdl-find-active', hlActive);
  }

  function scrollToActive() {
    var r = matches[activeIndex];
    if (!r) return;
    var rect = r.getBoundingClientRect();
    var viewH = window.innerHeight || document.documentElement.clientHeight;
    // Already comfortably in view: do nothing (avoids jumpy scrolling).
    if (rect.top >= viewH * 0.15 && rect.bottom <= viewH * 0.85) return;
    var target = window.scrollY + rect.top - viewH * 0.35;
    window.scrollTo({ top: Math.max(0, target), behavior: 'auto' });
  }

  function clamp(i) {
    if (!matches.length) return -1;
    return ((i % matches.length) + matches.length) % matches.length;
  }

  function select(i) {
    activeIndex = clamp(i);
    paintHighlights();
    if (activeIndex >= 0) scrollToActive();
  }

  /* --- public API ------------------------------------------------------- */

  api.search = function (query, caseSensitive) {
    collectMatches(query || '', !!caseSensitive);
    api.count = matches.length;
    activeIndex = matches.length ? 0 : -1;
    paintHighlights();
    if (activeIndex >= 0) scrollToActive();
    api.index = activeIndex;
    return api.count;
  };

  // dir: +1 forwards, -1 backwards. Wraps when wrapAround is true.
  api.next = function (dir, wrapAround) {
    if (!matches.length) return 0;
    var next = activeIndex + (dir >= 0 ? 1 : -1);
    if (next >= matches.length) {
      if (!wrapAround) return activeIndex;
      next = 0;
    } else if (next < 0) {
      if (!wrapAround) return activeIndex;
      next = matches.length - 1;
    }
    select(next);
    api.index = activeIndex;
    return activeIndex;
  };

  api.clear = function () {
    matches = [];
    activeIndex = -1;
    api.count = 0; api.index = 0;
    clearHighlights();
  };

  api.activeIndex = function () { return activeIndex; };

  // Keep the page searchable after a theme/zoom reflow.
  api.refresh = function () {
    if (matches.length) { paintHighlights(); }
  };

  window.__macdownLiteSearch = api;
})();
