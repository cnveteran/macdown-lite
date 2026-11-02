/* Extracts a flat, Word-friendly document model from the rendered preview.
 *
 * Why walk the live DOM instead of re-parsing the HTML: the page is already
 * laid out (MathJax typeset, Prism applied, images measured), so every block,
 * run and image size is known exactly. The host turns this JSON into OOXML.
 *
 * Returns a JSON string via window.__macdownLiteExport.build().
 */
(function () {
  'use strict';

  var math = [];      // math boxes, in document order
  var images = [];    // image boxes, in document order
  var BLOCK_TAGS = ['P','H1','H2','H3','H4','H5','H6','UL','OL','PRE','BLOCKQUOTE',
                    'TABLE','HR','DIV'];

  function isBlock(el) { return BLOCK_TAGS.indexOf(el.tagName) !== -1; }

  function collapsed(text) {
    // Mirror HTML whitespace collapsing so Word output matches the screen.
    return text.replace(/[\t\n\r ]+/g, ' ');
  }

  // ---- inline ------------------------------------------------------------

  function inline(node, fmt, out) {
    var kids = node.childNodes;
    for (var i = 0; i < kids.length; i++) {
      var n = kids[i];
      if (n.nodeType === 3) {
        var t = collapsed(n.nodeValue);
        if (t) out.push(merge(fmt, { text: t }));
        continue;
      }
      if (n.nodeType !== 1) continue;

      var tag = n.tagName;

      if (tag === 'MJX-CONTAINER' || (n.classList && n.classList.contains('MathJax'))) {
        var r = n.getBoundingClientRect();
        var id = 'm' + math.length;
        var entry = { id: id, display: n.getAttribute('display') === 'true',
                      x: r.left, y: r.top, w: r.width, h: r.height, svg: '' };
        // Hand the host a self-contained SVG at its true CSS size. MathJax is
        // configured with fontCache:'local', so every formula carries its own
        // glyph defs and the clone rasterises correctly on its own.
        var svg = n.querySelector('svg');
        if (svg && r.width > 0 && r.height > 0) {
          var clone = svg.cloneNode(true);
          clone.setAttribute('width', r.width);
          clone.setAttribute('height', r.height);
          clone.setAttribute('preserveAspectRatio', 'xMidYMid meet');
          clone.setAttribute('style', 'background:transparent');
          try { entry.svg = new XMLSerializer().serializeToString(clone); } catch (e) {}
        }
        math.push(entry);
        out.push({ mathId: id });
        continue;
      }
      if (tag === 'BR') { out.push({ lineBreak: true }); continue; }
      if (tag === 'IMG') {
        var ir = n.getBoundingClientRect();
        images.push({ src: n.getAttribute('src') || '', alt: n.getAttribute('alt') || '',
                      w: ir.width, h: ir.height });
        out.push({ imageIndex: images.length - 1 });
        continue;
      }

      var f = fmt;
      if (tag === 'STRONG' || tag === 'B') f = merge(f, { bold: true });
      else if (tag === 'EM' || tag === 'I') f = merge(f, { italic: true });
      else if (tag === 'DEL' || tag === 'S' || tag === 'STRIKE') f = merge(f, { strike: true });
      else if (tag === 'U') f = merge(f, { underline: true });
      else if (tag === 'MARK') f = merge(f, { highlight: true });
      else if (tag === 'SUP') f = merge(f, { superscript: true });
      else if (tag === 'SUB') f = merge(f, { subscript: true });
      else if (tag === 'CODE' || tag === 'TT' || tag === 'KBD' || tag === 'SAMP') f = merge(f, { code: true });
      else if (tag === 'A') {
        var href = n.getAttribute('href');
        if (href) f = merge(f, { link: href });
      }

      inline(n, f, out);
    }
  }

  function merge(a, b) {
    var o = {}, k;
    for (k in a) o[k] = a[k];
    for (k in b) o[k] = b[k];
    return o;
  }

  // ---- blocks ------------------------------------------------------------

  function blocks(container, ctx, out) {
    var kids = container.childNodes;
    for (var i = 0; i < kids.length; i++) {
      var el = kids[i];
      if (el.nodeType !== 1) continue;
      if (!isBlock(el)) {           // stray inline content: treat as paragraph
        var runs = [];
        inline(el, {}, runs);
        if (runs.length) out.push(block('para', ctx, { runs: runs }));
        continue;
      }
      emit(el, ctx, out);
    }
  }

  function block(kind, ctx, extra) {
    var b = { kind: kind, quoteDepth: ctx.quote || 0, level: ctx.level || 0 };
    for (var k in extra) b[k] = extra[k];
    return b;
  }

  function emit(el, ctx, out) {
    var tag = el.tagName, runs, i;

    if (/^H[1-6]$/.test(tag)) {
      runs = []; inline(el, {}, runs);
      out.push(block('heading', ctx, { headingLevel: parseInt(tag[1], 10), runs: runs }));
      return;
    }
    if (tag === 'P') {
      runs = []; inline(el, {}, runs);
      if (runs.length) out.push(block('para', ctx, { runs: runs }));
      return;
    }
    if (tag === 'HR') { out.push(block('hr', ctx, {})); return; }

    if (tag === 'PRE') {
      var code = el.textContent.replace(/\n$/, '');
      var codeEl = el.querySelector('code');
      var lang = '';
      if (codeEl && codeEl.className) {
        var m = /language-([\w+#-]+)/.exec(codeEl.className);
        if (m) lang = m[1];
      }
      out.push(block('code', ctx, { text: code, lang: lang }));
      return;
    }
    // hoedown wraps code blocks as <div><pre>…</pre></div>
    if (tag === 'DIV') {
      if (el.querySelector('pre')) { blocks(el, ctx, out); return; }
      if (el.classList && el.classList.contains('footnotes')) {
        blocks(el, merge(ctx, {}), out); return;
      }
      var inner = []; inline(el, {}, inner);
      if (inner.length) out.push(block('para', ctx, { runs: inner }));
      return;
    }

    if (tag === 'BLOCKQUOTE') {
      blocks(el, merge(ctx, { quote: (ctx.quote || 0) + 1 }), out);
      return;
    }

    if (tag === 'UL' || tag === 'OL') {
      emitList(el, ctx, out);
      return;
    }

    if (tag === 'TABLE') {
      var rows = [], maxCols = 0;
      var trs = el.querySelectorAll('tr');
      for (i = 0; i < trs.length; i++) {
        var cells = [], tds = trs[i].children;
        for (var j = 0; j < tds.length; j++) {
          var cr = [], cellRuns = [];
          inline(tds[j], {}, cellRuns);
          cells.push({ runs: cellRuns, header: tds[j].tagName === 'TH' });
        }
        rows.push(cells);
        maxCols = Math.max(maxCols, cells.length);
      }
      out.push(block('table', ctx, { rows: rows, cols: maxCols }));
      return;
    }
  }

  function emitList(listEl, ctx, out) {
    var ordered = listEl.tagName === 'OL';
    var level = ctx.level || 0;
    var kids = listEl.children;
    for (var i = 0; i < kids.length; i++) {
      var li = kids[i];
      if (li.tagName !== 'LI') continue;

      var checked = null;
      var cb = li.querySelector('input[type="checkbox"]');
      if (cb) checked = cb.hasAttribute('checked') || cb.checked === true;

      // Inline content of THIS item only (nested lists handled separately).
      var runs = [];
      var childNodes = li.childNodes;
      for (var k = 0; k < childNodes.length; k++) {
        var c = childNodes[k];
        if (c.nodeType === 3) {                       // text directly under <li>
          var t = collapsed(c.nodeValue);
          if (t) runs.push({ text: t });
          continue;
        }
        if (c.nodeType !== 1) continue;
        if (c.tagName === 'UL' || c.tagName === 'OL') continue;
        if (c.tagName === 'INPUT') continue;
        inline(c, {}, runs);
      }
      out.push(block('list', { quote: ctx.quote, level: level },
                      { ordered: ordered, checked: checked, runs: runs }));

      // Recurse for nested lists.
      for (var m = 0; m < childNodes.length; m++) {
        var n2 = childNodes[m];
        if (n2.nodeType === 1 && (n2.tagName === 'UL' || n2.tagName === 'OL')) {
          emitList(n2, { quote: ctx.quote, level: level + 1 }, out);
        }
      }
    }
  }

  window.__macdownLiteExport = {
    build: function () {
      math = []; images = [];
      var out = [];
      blocks(document.body, { level: 0, quote: 0 }, out);
      return JSON.stringify({
        blocks: out,
        math: math,
        images: images,
        title: (document.title || '').trim()
      });
    }
  };
})();
