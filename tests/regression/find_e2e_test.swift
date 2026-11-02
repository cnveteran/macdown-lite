import AppKit
import WebKit

// End-to-end regression: build the same HTML the app builds, load it in an
// offscreen WKWebView, drive the bundled search.js, and assert on the results.
//
// Run via tests/run_regression.sh (it supplies the project sources).

final class Probe: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let handler = AssetSchemeHandler()
    var failures = 0
    var checks = 0

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(handler, forURLScheme: AssetSchemeHandler.scheme)
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 900),
                            configuration: cfg)
        super.init()
        webView.navigationDelegate = self
    }

    func check(_ label: String, _ actual: Int, _ expected: Int) {
        checks += 1
        if actual == expected { print("  ok   \(label)  (\(actual))") }
        else { failures += 1; print("  FAIL \(label)  expected \(expected), got \(actual)") }
    }

    func check(_ label: String, _ actual: Bool, _ expected: Bool) {
        checks += 1
        if actual == expected { print("  ok   \(label)  (\(actual))") }
        else { failures += 1; print("  FAIL \(label)  expected \(expected), got \(actual)") }
    }

    func js(_ script: String) async -> Any? {
        await withCheckedContinuation { cont in
            webView.evaluateJavaScript(script) { result, error in
                if let error { print("      [js error] \(error)") }
                cont.resume(returning: result)
            }
        }
    }

    func int(_ script: String) async -> Int {
        (await js(script) as? NSNumber)?.intValue ?? -1
    }

    func load(_ path: String) async {
        let md = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let prepared = MathPreprocessor.preprocess(md, enableDollar: Settings.mathDollarDelimiter)
        var body = MarkdownRenderer.bodyHTML(prepared.markdown)
        body = MathPreprocessor.restore(in: body, spans: prepared.spans)
        body = HTMLBuilder.rewriteFileURLs(body)
        body = HTMLBuilder.expandTOC(in: body, markdown: prepared.markdown)
        let html = HTMLBuilder.document(bodyHTML: body, title: "test", theme: ThemeManager.current)
        webView.loadHTMLString(html,
            baseURL: AssetSchemeHandler.baseURL(forDocumentAt: URL(fileURLWithPath: path)))
        try? await Task.sleep(nanoseconds: 6_000_000_000)
    }

    func run() async {
        // ---- 1. math.md: delimiters, search counts, highlight scope ----------
        await load("tests/math.md")

        print("--- 依赖就绪 ---")
        check("search.js 已加载", await js("!!window.__macdownLiteSearch") as? Bool ?? false, true)
        check("MathJax 已加载", await js("!!window.MathJax") as? Bool ?? false, true)
        check("Highlight API 可用",
              await js("window.__macdownLiteSearch.supportsHighlight") as? Bool ?? false, true)
        check("MathJax 渲染了公式", await int("document.querySelectorAll('mjx-container').length") > 0, true)

        print("--- 查找计数与环绕 ---")
        check("MARKER 不区分大小写 = 3",
              await int("window.__macdownLiteSearch.search('MARKER', false)"), 3)
        check("初始定位 0", await int("window.__macdownLiteSearch.index"), 0)
        check("下一个 -> 1", await int("window.__macdownLiteSearch.next(1, true)"), 1)
        check("下一个 -> 2", await int("window.__macdownLiteSearch.next(1, true)"), 2)
        check("环绕 -> 0", await int("window.__macdownLiteSearch.next(1, true)"), 0)
        check("后退环绕 -> 2", await int("window.__macdownLiteSearch.next(-1, true)"), 2)

        print("--- 大小写敏感 ---")
        check("区分大小写 MARKER = 2",
              await int("window.__macdownLiteSearch.search('MARKER', true)"), 2)
        check("区分大小写 marker = 1",
              await int("window.__macdownLiteSearch.search('marker', true)"), 1)

        print("--- 高亮生命周期 ---")
        _ = await js("window.__macdownLiteSearch.search('MARKER', false)")
        check("全部高亮已注册", await int("CSS.highlights.has('mdl-find') ? 1 : 0"), 1)
        check("当前项高亮已注册", await int("CSS.highlights.has('mdl-find-active') ? 1 : 0"), 1)
        _ = await js("window.__macdownLiteSearch.clear()")
        check("清理后高亮移除", await int("CSS.highlights.has('mdl-find') ? 1 : 0"), 0)

        // ---- 2. probe_math.md: search scope around math and code -------------
        await load("tests/probe_math.md")
        print("--- 搜索范围隔离 ---")
        check("正文可搜", await int("window.__macdownLiteSearch.search('UNIQTEXT', false)"), 1)
        check("公式内正文不可搜（避开字形）",
              await int("window.__macdownLiteSearch.search('UNIQMATH', false)"), 0)
        check("行内公式不可搜",
              await int("window.__macdownLiteSearch.search('UNIQINLINE', false)"), 0)
        check("代码块可搜", await int("window.__macdownLiteSearch.search('UNIQCODE', false)"), 1)
        check("数学字形不参与搜索",
              await int("window.__macdownLiteSearch.search('α', false)"), 0)

        print("")
        print("checks=\(checks) failures=\(failures)")
        exit(failures == 0 ? 0 : 1)
    }

    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) {
        print("navigation failed: \(e)"); exit(1)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let probe = Probe()
Task { await probe.run() }
app.run()
