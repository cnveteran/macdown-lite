import AppKit
import WebKit

// Verifies print-media semantics without invoking the print engine: flip the
// media queries via CSSOM (screen -> not all, print -> all) and measure layout.
final class P: NSObject, WKNavigationDelegate {
    let wv: WKWebView; let h = AssetSchemeHandler()
    var fails = 0, checks = 0
    override init() {
        let c = WKWebViewConfiguration()
        c.setURLSchemeHandler(h, forURLScheme: AssetSchemeHandler.scheme)
        c.defaultWebpagePreferences.allowsContentJavaScript = true
        wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1180, height: 900), configuration: c)
        super.init(); wv.navigationDelegate = self
    }
    func js(_ s: String) async -> Any? {
        await withCheckedContinuation { c in wv.evaluateJavaScript(s) { r, e in
            if let e { print("  [js] \(e)") }; c.resume(returning: r) } }
    }
    func num(_ s: String) async -> Double { (await js(s) as? NSNumber)?.doubleValue ?? -1 }
    func check(_ l: String, _ a: Double, _ e: Double) {
        checks += 1
        if abs(a - e) < 0.5 { print("  ok   \(l)  (\(Int(a)))") }
        else { fails += 1; print("  FAIL \(l)  expected \(Int(e)) got \(Int(a))") }
    }
    func run() async {
        UserDefaults.standard.set("Word 文档", forKey: "themeName")
        let md = (try? String(contentsOfFile: "tests/word_demo.md", encoding: .utf8)) ?? ""
        let pre = MathPreprocessor.preprocess(md, enableDollar: Settings.mathDollarDelimiter)
        var body = MarkdownRenderer.bodyHTML(pre.markdown)
        body = MathPreprocessor.restore(in: body, spans: pre.spans)
        body = HTMLBuilder.rewriteFileURLs(body)
        body = HTMLBuilder.expandTOC(in: body, markdown: pre.markdown)
        let html = HTMLBuilder.document(bodyHTML: body, title: "d", theme: ThemeManager.current)
        wv.loadHTMLString(html, baseURL: AssetSchemeHandler.baseURL(forDocumentAt: URL(fileURLWithPath: "tests/word_demo.md")))
        try? await Task.sleep(nanoseconds: 5_000_000_000)

        print("=== 屏幕媒体（当前）===")
        check("页宽 = 21cm", await num("document.body.getBoundingClientRect().width"), 794)
        let screenH = await num("document.body.getBoundingClientRect().height")
        checks += 1
        if screenH >= 1123 { print("  ok   最小页高生效  (\(Int(screenH))px)") }
        else { fails += 1; print("  FAIL 最小页高未生效 (\(Int(screenH))px)") }

        print()
        print("=== 切换到打印媒体 ===")
        let msg = await js("""
        (function(){
          var n = 0;
          for (var i = 0; i < document.styleSheets.length; i++) {
            var rules; try { rules = document.styleSheets[i].cssRules; } catch(e) { continue; }
            for (var j = 0; j < rules.length; j++) {
              var r = rules[j];
              if (r.media && r.media.mediaText) {
                var t = r.media.mediaText.trim();
                if (t === 'print') { r.media.mediaText = 'all'; n++; }
                else if (t.indexOf('screen') === 0) { r.media.mediaText = 'not all'; n++; }
              }
            }
          }
          return n;
        })();
        """)
        print("      已翻转媒体查询: \(msg ?? "?") 条")

        // The page must grow to the viewport instead of staying at 21cm (794px).
        // Assert a range, not an exact value: a classic scrollbar shaves ~17px.
        let printWidth = await num("document.body.getBoundingClientRect().width")
        checks += 1
        if printWidth > 900 {
            print("  ok   打印时页宽不再固定为 21cm  (\(Int(printWidth)))")
        } else {
            fails += 1
            print("  FAIL 打印时页宽仍被限制  (\(Int(printWidth)))")
        }
        check("打印时最小页高被清零", await num("parseFloat(getComputedStyle(document.body).minHeight) || 0"), 0)
        check("打印时阴影被移除", await num("getComputedStyle(document.body).boxShadow === 'none' ? 1 : 0"), 1)
        check("打印时内边距为 0（改用 @page 边距）", await num("parseFloat(getComputedStyle(document.body).paddingLeft) || 0"), 0)
        check("打印时背景为白", await num("getComputedStyle(document.body).backgroundColor === 'rgb(255, 255, 255)' ? 1 : 0"), 1)
        check("正文排版仍保留（字号 16px）", await num("parseFloat(getComputedStyle(document.body).fontSize)"), 16)
        check("首行缩进仍保留", await num("parseFloat(getComputedStyle(document.body.querySelector('p')).textIndent)"), 32)

        print()
        print("checks=\(checks) failures=\(fails)")
        exit(fails == 0 ? 0 : 1)
    }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { print("nav \(e)"); exit(1) }
}
let a = NSApplication.shared; a.setActivationPolicy(.accessory)
let p = P(); Task { await p.run() }; a.run()
