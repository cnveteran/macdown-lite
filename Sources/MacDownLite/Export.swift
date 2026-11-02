import AppKit
import WebKit
import UniformTypeIdentifiers

/// PDF and Word (.docx) export for a viewer window.
///
/// PDF goes through the same `NSPrintOperation` path as ⌘P, so it inherits the
/// print stylesheet (A4 pagination). Word export re-reads the *rendered* page,
/// turns it into a flat document model and writes an OOXML package.
extension ViewerWindowController {

    // MARK: - Save panels

    func presentExportPDF() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = fileURL.deletingPathExtension().lastPathComponent + ".pdf"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.exportPDF(to: url)
        }
    }

    func presentExportDocx() {
        guard let window else { return }
        let panel = NSSavePanel()
        if let type = UTType(filenameExtension: "docx") {
            panel.allowedContentTypes = [type]
        }
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = fileURL.deletingPathExtension().lastPathComponent + ".docx"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.exportDocx(to: url)
        }
    }

    // MARK: - PDF

    /// A4 with the same margins the on-screen paper model uses.
    func configuredPrintInfo() -> NSPrintInfo {
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595.28, height: 841.89)   // A4 in points
        info.topMargin = 72.0                                    // 2.54 cm
        info.bottomMargin = 72.0
        info.leftMargin = 89.86                                  // 3.17 cm
        info.rightMargin = 89.86
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        return info
    }

    func exportPDF(to url: URL) {
        guard let window else { return }
        let info = configuredPrintInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let op = webView.printOperation(with: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: - Word

    func exportDocx(to url: URL) {
        Task { @MainActor in
            do {
                let data = try await buildDocx()
                try data.write(to: url)
                presentExportSuccess(url, format: "Word 文档")
            } catch {
                presentExportFailure(error)
            }
        }
    }

    @MainActor
    private func buildDocx() async throws -> Data {
        // 1. Ask the page for its document model.
        let jsSource = Resources.text(at: Resources.exportModelScript) ?? ""
        guard !jsSource.isEmpty else { throw ExportError.missingResource }
        _ = try? await webView.evaluateJavaScriptAsync(jsSource)
        guard let json = try await webView.evaluateJavaScriptAsync("window.__macdownLiteExport.build()") as? String,
              let model = try? JSONDecoder().decode(ExportModel.self, from: Data(json.utf8)) else {
            throw ExportError.extractionFailed
        }

        // 2. Pull local images straight off disk (full quality, no re-encode).
        var imageData: [Int: Data] = [:]
        var imageExtensions: [Int: String] = [:]
        let docDirectory = fileURL.deletingLastPathComponent()
        for (index, box) in model.images.enumerated() {
            guard let path = Self.localPath(forImageSource: box.src, relativeTo: docDirectory),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
            imageData[index] = data
            imageExtensions[index] = Self.matchingExtension(for: path, fallback: "png")
        }

        // 3. Rasterise formulas from their inline SVG.
        var mathImages: [String: Data] = [:]
        for m in model.math {
            guard let svg = m.svg, !svg.isEmpty else { continue }
            if let png = SVGRasterizer.png(fromSVG: svg, cssWidth: m.w, cssHeight: m.h) {
                mathImages[m.id] = png
            }
        }

        return DocxExporter(model: model,
                            mathImages: mathImages,
                            imageData: imageData,
                            imageExtensions: imageExtensions).build()
    }

    /// Resolves `src` from the rendered page back to a file on disk.
    private static func localPath(forImageSource src: String, relativeTo directory: URL) -> String? {
        guard !src.isEmpty, !src.hasPrefix("http://"), !src.hasPrefix("https://"),
              !src.hasPrefix("data:") else { return nil }
        if src.hasPrefix(AssetSchemeHandler.scheme + "://") {
            guard let url = URL(string: src) else { return nil }
            return url.path
        }
        if src.hasPrefix("/") { return src }
        return directory.appendingPathComponent(src.removingPercentEncoding ?? src).path
    }

    /// Keeps the container extension honest if the source file is not a PNG.
    private static func matchingExtension(for path: String, fallback: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif": return ext
        default: return fallback
        }
    }

    private func presentExportSuccess(_ url: URL, format: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "已导出 \(format)"
        alert.informativeText = url.path
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "在访达中显示")
        alert.beginSheetModal(for: window) { response in
            if response == .alertSecondButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    private func presentExportFailure(_ error: Error) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "导出失败"
        alert.informativeText = (error as? ExportError)?.message ?? error.localizedDescription
        alert.beginSheetModal(for: window)
    }
}

enum ExportError: Error {
    case missingResource
    case extractionFailed

    var message: String {
        switch self {
        case .missingResource:   return "应用内缺少导出所需的资源文件。"
        case .extractionFailed:  return "无法从预览页面读取文档内容。"
        }
    }
}

extension WKWebView {
    /// async/await wrapper around `evaluateJavaScript`.
    @MainActor
    func evaluateJavaScriptAsync(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            self.evaluateJavaScript(script) { result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result) }
            }
        }
    }
}
