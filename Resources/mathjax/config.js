/* MathJax configuration for MacDown Lite.
 *
 * hoedown emits TeX with \( \) for inline math and \[ \] for display math
 * (see Sources/choedown/html.c, rndr_math), which is exactly MathJax's default
 * delimiter pair. When the "dollar sign" option is enabled we additionally
 * accept $...$ and $$...$$, mirroring MacDown's MATH_EXPLICIT behaviour.
 *
 * The delimiter set is read from window.MacDownLiteMath by the host before this
 * file runs; the fallback keeps the file usable standalone.
 */
(function () {
  var opts = window.MacDownLiteMath || {};
  var inline = [['\\(', '\\)']];
  var display = [['\\[', '\\]']];

  if (opts.dollarDelimiter) {
    inline.push(['$', '$']);
    // $$ must be tested before $ so MathJax does not split it.
    display.unshift(['$$', '$$']);
  }

  window.MathJax = {
    tex: {
      inlineMath: inline,
      displayMath: display,
      processEscapes: true,
      packages: { '[+]': ['ams', 'newcommand', 'configmacros'] }
    },
    svg: {
      fontCache: 'local',
      scale: 1.0
    },
    options: {
      enableMenu: false,
      skipHtmlTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code'],
      ignoreHtmlClass: 'no-mathjax',
      processHtmlClass: 'mathjax-process'
    },
    startup: {
      typeset: false          // the host triggers typesetting once loaded
    }
  };
})();
