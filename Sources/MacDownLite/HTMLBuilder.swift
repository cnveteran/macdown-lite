import Foundation

/// Assembles the HTML document shown in the web view.
enum HTMLBuilder {

    /// Base CSS applied before the theme, so every MacDown theme keeps working
    /// while getting sensible fallbacks for what it does not define itself
    /// (notably table borders and inline-code background).
    private static let baseCSS = """
    html { -webkit-text-size-adjust: 100%; }
    body { word-wrap: break-word; }
    img, video, svg { max-width: 100%; height: auto; }
    pre { overflow-x: auto; }

    /* Fallbacks: not every bundled theme styles these. */
    table { border-collapse: collapse; }
    table th, table td { border: 1px solid rgba(128,128,128,.35); padding: 6px 12px; }
    code { padding: 0 .25em; border-radius: 3px; background: rgba(128,128,128,.15); }

    /* Task lists produced by the hoedown patch. */
    .task-list-item { list-style: none; }
    .task-list-item > input[type="checkbox"] { margin-right: .45em; vertical-align: .1em; }

    /* MathJax output: keep display math from overflowing the column. */
    mjx-container[display="true"] { margin: 1em 0; overflow-x: auto; overflow-y: hidden; }
    mjx-container { outline: none; }
    """

    /// Print rules, applied *after* the theme so ⌘P / "存储为 PDF" yields a
    /// clean page instead of the on-screen chrome (page frame, shadows, dark
    /// backgrounds). Applies to every theme.
    private static let printCSS = """
    /* Paper size only: margins come from NSPrintInfo (Cocoa honours them
       reliably, and leaving them here too would double the inset). */
    @page { size: A4; }
    @media print {
      html, body {
        background: #fff !important;
        box-shadow: none !important;
        margin: 0 !important;
        padding: 0 !important;
        width: auto !important;
        min-height: 0 !important;
        font-size: 12pt;
      }
      a { color: #0563C1 !important; text-decoration: underline !important; }
      /* Keep headings with the text that follows them. */
      h1, h2, h3, h4, h5, h6 { break-after: avoid; page-break-after: avoid; }
      /* Never split these across pages. */
      img, table, pre, blockquote, figure, mjx-container[display="true"] {
        break-inside: avoid; page-break-inside: avoid;
      }
      /* Long tables should repeat their header row on each page. */
      thead { display: table-header-group; }
      tr { break-inside: avoid; page-break-inside: avoid; }
      pre { white-space: pre-wrap; overflow-wrap: break-word; }
      h1 { break-before: auto; }
    }
    """

    /// Highlight colours for in-page find, using the CSS Custom Highlight API.
    /// These are deliberately theme-agnostic: a translucent accent that reads on
    /// both light and dark backgrounds.
    private static let findCSS = """
    ::highlight(mdl-find) {
      background-color: rgba(255, 214, 10, .38);
    }
    ::highlight(mdl-find-active) {
      background-color: rgba(255, 149, 0, .85);
      color: #1a1a1a;
    }
    """

    static func document(bodyHTML: String,
                         title: String,
                         theme: ThemeManager.Theme) -> String {
        let prismCSS = theme.prismCSS
        let safeTitle = escapeHTML(title)
        let scheme = theme.isDark ? "dark" : "light"
        let mathEnabled = Settings.mathJaxEnabled && Settings.mathDollarDelimiter

        // Only pay for MathJax when the feature is on.
        let mathScripts: String
        if Settings.mathJaxEnabled {
            mathScripts = """
            <script>window.MacDownLiteMath = { dollarDelimiter: \(mathEnabled ? "true" : "false") };</script>
            <script src="\(bundleURL("mathjax/config.js"))"></script>
            <script src="\(bundleURL("mathjax/mathjax.js"))"></script>
            """
        } else {
            mathScripts = ""
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">
        <title>\(safeTitle)</title>
        <style>:root { color-scheme: \(scheme); }</style>
        <style>\(baseCSS)</style>
        <style>\(findCSS)</style>
        <style>\(prismCSS)</style>
        <style>\(theme.css)</style>
        <style>\(printCSS)</style>
        </head>
        <body>
        \(bodyHTML)
        <script src="\(bundleURL("prism/prism.js"))"></script>
        <script src="\(bundleURL("search.js"))"></script>
        <!-- MathJax must load before the typeset call below. -->
        \(mathScripts)
        <script>
        (function () {
          if (window.Prism) { Prism.highlightAll(); }
          if (window.MathJax && window.MathJax.startup) {
            MathJax.startup.promise
              .then(function () { return MathJax.typesetPromise(); })
              .catch(function (e) { console.error('MathJax error:', e); });
          }
        })();
        </script>
        </body>
        </html>
        """
    }

    /// URL for a file inside the app bundle, served through our scheme handler.
    private static func bundleURL(_ path: String) -> String {
        "\(AssetSchemeHandler.scheme)://\(AssetSchemeHandler.bundleHost)/\(path)"
    }

    /// Rewrites markdown output so file:// links go through our scheme handler.
    static func rewriteFileURLs(_ html: String) -> String {
        html.replacingOccurrences(of: "=\"file://",
                                  with: "=\"\(AssetSchemeHandler.scheme)://\(AssetSchemeHandler.fileSystemHost)")
    }

    /// Expands a `[TOC]` token into a real table of contents (MacDown feature).
    static func expandTOC(in html: String, markdown: String) -> String {
        guard html.range(of: "[TOC]", options: .caseInsensitive) != nil else { return html }
        let toc = MarkdownRenderer.tocHTML(markdown)
        guard !toc.isEmpty else { return html }
        return html.replacingOccurrences(
            of: #"<p[^>]*>\s*\[TOC\]\s*</p>"#,
            with: toc,
            options: [.regularExpression, .caseInsensitive])
    }

    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
