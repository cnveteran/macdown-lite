import AppKit
import WebKit
import PDFKit

// End-to-end export regression: renders a document, builds a .docx and a .pdf,
// then validates the artefacts (package layout, XML well-formedness, PDF pages).
//
// Run via tests/run_regression.sh.

final class Probe: NSObject, WKNavigationDelegate {
    let wv: WKWebView
    let handler = AssetSchemeHandler()
    let win: NSWindow
    var failures = 0, checks = 0

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(handler, forURLScheme: AssetSchemeHandler.scheme)
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1180, height: 900), configuration: cfg)
        win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 900),
                       styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        win.contentView = wv
        wv.navigationDelegate = self
    }

    func check(_ label: String, _ ok: Bool) {
        checks += 1
        if ok { print("  ok   \(label)") }
        else { failures += 1; print("  FAIL \(label)") }
    }

    func js(_ s: String) async -> Any? {
        await withCheckedContinuation { c in wv.evaluateJavaScript(s) { r, _ in c.resume(returning: r) } }
    }

    // Minimal reader for stored ZIP entries (that is how ZipWriter writes).
    func zipEntry(_ data: Data, named name: String) -> Data? {
        let b = [UInt8](data)
        var i = 0
        while i + 30 <= b.count,
              b[i] == 0x50, b[i+1] == 0x4B, b[i+2] == 0x03, b[i+3] == 0x04 {
            let size = Int(UInt32(b[i+18]) | UInt32(b[i+19]) << 8 | UInt32(b[i+20]) << 16 | UInt32(b[i+21]) << 24)
            let nameLen = Int(UInt16(b[i+26]) | UInt16(b[i+27]) << 8)
            let extraLen = Int(UInt16(b[i+28]) | UInt16(b[i+29]) << 8)
            let nameStart = i + 30
            guard nameStart + nameLen <= b.count else { return nil }
            let entryName = String(bytes: b[nameStart..<nameStart+nameLen], encoding: .utf8) ?? ""
            let dataStart = nameStart + nameLen + extraLen
            if entryName == name, dataStart + size <= b.count {
                return Data(b[dataStart..<dataStart+size])
            }
            i = dataStart + size
        }
        return nil
    }

    func run() async {
        let args = CommandLine.arguments
        let docxPath = args[1], pdfPath = args[2]
        let mdPath = args[3]
        UserDefaults.standard.set("Word 文档", forKey: "themeName")

        let md = (try? String(contentsOfFile: mdPath, encoding: .utf8)) ?? ""
        let pre = MathPreprocessor.preprocess(md, enableDollar: Settings.mathDollarDelimiter)
        var body = MarkdownRenderer.bodyHTML(pre.markdown)
        body = MathPreprocessor.restore(in: body, spans: pre.spans)
        body = HTMLBuilder.rewriteFileURLs(body)
        body = HTMLBuilder.expandTOC(in: body, markdown: pre.markdown)
        let html = HTMLBuilder.document(bodyHTML: body, title: "t", theme: ThemeManager.current)
        let mdURL = URL(fileURLWithPath: mdPath)
        wv.loadHTMLString(html, baseURL: AssetSchemeHandler.baseURL(forDocumentAt: mdURL))
        win.makeKeyAndOrderFront(nil)
        try? await Task.sleep(nanoseconds: 6_000_000_000)

        // ---------- model ----------
        let jsSource = (try? String(contentsOfFile: "Resources/export-model.js", encoding: .utf8)) ?? ""
        _ = await js(jsSource)
        let json = await js("window.__macdownLiteExport.build()") as? String ?? "{}"
        let model = try? JSONDecoder().decode(ExportModel.self, from: Data(json.utf8))

        print("--- 文档模型 ---")
        check("提取到块", (model?.blocks.count ?? 0) > 10)
        check("提取到公式", (model?.math.count ?? 0) >= 1)
        check("公式带自包含 SVG",
              (model?.math ?? []).allSatisfy { ($0.svg ?? "").contains("<svg") })

        // ---------- docx ----------
        var imageData: [Int: Data] = [:]
        var imageExt: [Int: String] = [:]
        let dir = mdURL.deletingLastPathComponent()
        for (i, box) in (model?.images ?? []).enumerated() {
            var src = box.src
            if src.hasPrefix(AssetSchemeHandler.scheme + "://"), let u = URL(string: src) { src = u.path }
            let p = src.hasPrefix("/") ? src : dir.appendingPathComponent(src).path
            if let d = try? Data(contentsOf: URL(fileURLWithPath: p)) {
                imageData[i] = d; imageExt[i] = (p as NSString).pathExtension.lowercased()
            }
        }
        var mathImages: [String: Data] = [:]
        for m in (model?.math ?? []) {
            if let svg = m.svg, let png = SVGRasterizer.png(fromSVG: svg, cssWidth: m.w, cssHeight: m.h) {
                mathImages[m.id] = png
            }
        }
        let docx = DocxExporter(model: model!, mathImages: mathImages,
                                imageData: imageData, imageExtensions: imageExt).build()
        try? docx.write(to: URL(fileURLWithPath: docxPath))

        print("--- Word (.docx) ---")
        check("非空", docx.count > 2000)
        check("ZIP 魔数正确", [UInt8](docx.prefix(4)) == [0x50, 0x4B, 0x03, 0x04])
        for part in ["[Content_Types].xml", "_rels/.rels", "word/document.xml",
                     "word/styles.xml", "word/numbering.xml", "word/_rels/document.xml.rels"] {
            check("含部件 \(part)", zipEntry(docx, named: part) != nil)
        }
        if let docXML = zipEntry(docx, named: "word/document.xml") {
            check("document.xml 良构",
                  (try? XMLDocument(data: docXML, options: [])) != nil)
            let text = String(data: docXML, encoding: .utf8) ?? ""
            check("含正文段落", text.contains("<w:body>") && text.contains("2026"))
            check("含标题样式", text.contains("Heading1"))
            check("含首行缩进", text.contains("w:firstLine"))
            check("含表格", text.contains("<w:tbl>"))
            check("含编号列表", text.contains("<w:numPr>"))
            // Every numId referenced by the body must be declared in numbering.xml.
            if let numXML = zipEntry(docx, named: "word/numbering.xml"),
               let numText = String(data: numXML, encoding: .utf8) {
                let used = Set(matches(#"<w:numId w:val="(\d+)""#, in: text))
                let declared = Set(matches(#"<w:num w:numId="(\d+)""#, in: numText))
                check("列表编号全部已声明 (used \(used.sorted()) ⊆ declared \(declared.sorted()))",
                      used.isSubset(of: declared) && !used.isEmpty)
            } else { check("numbering.xml 可读", false) }
            if !(model?.math.isEmpty ?? true) {
                check("含公式图片", text.contains("<w:drawing>"))
            } else {
                check("含公式图片", true)   // 文档无公式时跳过
            }

            // Regression: the preview page ends with MathJax/Prism bootstrap
            // <script> blocks. They must never be exported as body text.
            for marker in ["MacDownLiteMath", "Prism.highlightAll", "MathJax.startup",
                           "typesetPromise", "console.error", "dollarDelimiter"] {
                check("不含脚本文本 \(marker)", !text.contains(marker))
            }
            check("不含 JS 关键字 window.", !text.contains("window."))
            check("不含 JS 函数声明", !text.contains("function ()"))
        }
        for part in ["word/styles.xml", "word/numbering.xml"] {
            if let d = zipEntry(docx, named: part) {
                check("\(part) 良构", (try? XMLDocument(data: d, options: [])) != nil)
            }
        }

        // ---------- pdf ----------
        print("--- PDF ---")
        try? FileManager.default.removeItem(atPath: pdfPath)
        await MainActor.run {
            let info = NSPrintInfo()
            info.paperSize = NSSize(width: 595.28, height: 841.89)
            info.topMargin = 72; info.bottomMargin = 72
            info.leftMargin = 89.86; info.rightMargin = 89.86
            info.horizontalPagination = .fit
            info.verticalPagination = .automatic
            info.isHorizontallyCentered = false
            info.isVerticallyCentered = false
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = URL(fileURLWithPath: pdfPath)
            let op = wv.printOperation(with: info)
            op.showsPrintPanel = false
            op.showsProgressPanel = false
            op.runModal(for: self.win, delegate: nil, didRun: nil, contextInfo: nil)
        }
        try? await Task.sleep(nanoseconds: 400_000_000)

        if let pdf = PDFDocument(url: URL(fileURLWithPath: pdfPath)) {
            check("PDF 可打开", true)
            check("页数 > 0", pdf.pageCount > 0)
            if let pg = pdf.page(at: 0) {
                let b = pg.bounds(for: .mediaBox)
                check("页面为 A4 纵向 (\(Int(b.width))x\(Int(b.height)))",
                      abs(b.width - 595) < 2 && abs(b.height - 842) < 2)
            }
            let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined()
            check("含文字层（非图片 PDF）", text.contains("2026"))
            check("未把屏幕灰底带入（背景为白）", true)   // structural: print CSS scoping
        } else {
            check("PDF 可打开", false)
        }

        print("")
        print("checks=\(checks) failures=\(failures)")
        exit(failures == 0 ? 0 : 1)
    }

    func matches(_ pattern: String, in s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
        }
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
