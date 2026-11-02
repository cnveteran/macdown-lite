import AppKit
import WebKit

/// One window showing one markdown document.
///
/// The window is a split view: an optional plain-text editor on the left and the
/// rendered preview on the right. With the editor collapsed it is a pure
/// read-only viewer.
final class ViewerWindowController: NSWindowController {

    private(set) var fileURL: URL
    let webView: DropWebView

    private let editorVC = EditorViewController()
    private let splitVC = NSSplitViewController()
    private var editorItem: NSSplitViewItem!

    /// Preview column: find bar stacked above the web view.
    private let findBarVC = FindBarViewController()
    private var findBarHeight: NSLayoutConstraint!
    private var findBarVisible = false
    private var previewColumn: NSStackView!

    /// Guards against out-of-order `evaluateJavaScript` callbacks: typing
    /// "MARKER" fires one search per keystroke, and a slow reply for "M" must
    /// not overwrite the result for "MARKER".
    private var searchGeneration = 0

    private let schemeHandler = AssetSchemeHandler()
    private var watcher: FileWatcher?
    private var markdown: String = ""
    private var isDirty = false
    private var previewWorkItem: DispatchWorkItem?

    var onClose: ((ViewerWindowController) -> Void)?
    var onOpenURLs: (([URL]) -> Void)?

    private static let autosaveName = "MacDownLiteWindow"

    // MARK: - Init

    init(fileURL: URL) {
        self.fileURL = fileURL

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: AssetSchemeHandler.scheme)
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let web = DropWebView(frame: NSRect(x: 0, y: 0, width: 620, height: 720),
                              configuration: config)
        self.webView = web

        // Preview column = [find bar][web view], the bar collapsed by default.
        let column = NSStackView(views: [findBarVC.view, web])
        column.orientation = .vertical
        column.spacing = 0
        column.distribution = .fill
        self.previewColumn = column

        let previewVC = NSViewController()
        previewVC.view = column

        // Collapse the bar until the user asks for it.
        findBarVC.view.isHidden = true
        findBarHeight = findBarVC.view.heightAnchor.constraint(equalToConstant: 0)
        findBarHeight.isActive = true

        let editorItem = NSSplitViewItem(viewController: editorVC)
        editorItem.minimumThickness = 220
        editorItem.canCollapse = true
        let previewItem = NSSplitViewItem(viewController: previewVC)
        previewItem.minimumThickness = 260

        splitVC.addSplitViewItem(editorItem)
        splitVC.addSplitViewItem(previewItem)
        self.editorItem = editorItem

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.minSize = NSSize(width: 360, height: 260)
        window.contentViewController = splitVC
        window.tabbingMode = .preferred

        super.init(window: window)

        editorItem.isCollapsed = !Settings.editorVisible

        window.delegate = self
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsMagnification = true
        web.setValue(false, forKey: "drawsBackground")
        web.onDropFiles = { [weak self] urls in self?.onOpenURLs?(urls) }

        editorVC.onTextChange = { [weak self] text in
            guard let self else { return }
            self.isDirty = true
            self.updateTitle()
            self.schedulePreview(text)
        }
        editorVC.onSave = { [weak self] in self?.save() }

        findBarVC.onQueryChange = { [weak self] query, caseSensitive in
            self?.runSearch(query: query, caseSensitive: caseSensitive, resetIndex: true)
        }
        findBarVC.onStep = { [weak self] direction in
            self?.stepSearch(direction)
        }
        findBarVC.onDismiss = { [weak self] in self?.hideFindBar() }

        if !window.setFrameUsingName(Self.autosaveName) { window.center() }
        window.setFrameAutosaveName(Self.autosaveName)

        startWatching()
        render()
        restoreZoom()
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit { watcher?.stop() }

    // MARK: - Editing state

    var isEditing: Bool { !editorItem.isCollapsed }

    func toggleEditor() {
        if editorItem.isCollapsed {
            editorVC.setText(markdown)
            editorVC.applyAppearance(isDark: ThemeManager.current.isDark)
            editorItem.isCollapsed = false
            window?.makeFirstResponder(editorVC.textView)
        } else {
            editorItem.isCollapsed = true
        }
        Settings.editorVisible = isEditing
    }

    func save() {
        guard isEditing else { return }
        do {
            try editorVC.text.write(to: fileURL, atomically: true, encoding: .utf8)
            markdown = editorVC.text
            isDirty = false
            updateTitle()
            watcher?.refreshBaseline()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "保存失败"
            alert.informativeText = "无法写入 \(fileURL.path)"
            if let window { alert.beginSheetModal(for: window) }
        }
    }

    // MARK: - Rendering

    func render() {
        markdown = Self.readMarkdown(at: fileURL)
        if isEditing { editorVC.reloadText(markdown) }
        loadPreview(markdown)
    }

    func reload() { render() }

    private func schedulePreview(_ text: String) {
        previewWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.loadPreview(text) }
        previewWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }

    private func loadPreview(_ text: String) {
        // Pull TeX out first so hoedown never sees it (see MathPreprocessor).
        let mathEnabled = Settings.mathJaxEnabled
        let prepared = mathEnabled
            ? MathPreprocessor.preprocess(text, enableDollar: Settings.mathDollarDelimiter)
            : MathPreprocessor.Result(markdown: text, spans: [])

        var body = MarkdownRenderer.bodyHTML(prepared.markdown)
        if mathEnabled, prepared.hasMath {
            body = MathPreprocessor.restore(in: body, spans: prepared.spans)
        }
        body = HTMLBuilder.rewriteFileURLs(body)
        body = HTMLBuilder.expandTOC(in: body, markdown: prepared.markdown)

        let theme = ThemeManager.current
        let html = HTMLBuilder.document(bodyHTML: body,
                                        title: fileURL.deletingPathExtension().lastPathComponent,
                                        theme: theme)

        window?.appearance = theme.isDark ? NSAppearance(named: .darkAqua) : nil
        editorVC.applyAppearance(isDark: theme.isDark)
        webView.loadHTMLString(html, baseURL: AssetSchemeHandler.baseURL(forDocumentAt: fileURL))
        refreshSearchAfterRender()
    }

    private func updateTitle() {
        let name = fileURL.lastPathComponent
        window?.title = isDirty ? "• \(name)" : name
        window?.isDocumentEdited = isDirty
    }

    // MARK: - Find (⌘F)

    var isFinding: Bool { findBarVisible }

    func showFindBar() {
        if findBarVisible {
            findBarVC.focus()
            return
        }
        findBarVisible = true
        findBarVC.view.isHidden = false
        findBarHeight.animator().constant = 38
        findBarVC.focus()
        // Re-apply the query so highlights come back after the bar was hidden.
        if !findBarVC.query.isEmpty {
            runSearch(query: findBarVC.query,
                      caseSensitive: Settings.findCaseSensitive,
                      resetIndex: true)
        }
    }

    func hideFindBar() {
        guard findBarVisible else { return }
        searchGeneration += 1          // invalidate any in-flight search
        findBarVisible = false
        findBarHeight.animator().constant = 0
        findBarVC.view.isHidden = true
        findBarVC.clearCount()
        webView.evaluateJavaScript("window.__macdownLiteSearch && window.__macdownLiteSearch.clear();",
                                   completionHandler: nil)
        window?.makeFirstResponder(webView)
    }

    /// Jump straight into find, pre-filled with the current selection if any.
    func performFind() {
        showFindBar()
    }

    /// Run a fresh search and report the count back to the bar.
    private func runSearch(query: String, caseSensitive: Bool, resetIndex: Bool) {
        guard findBarVisible else { return }
        guard !query.isEmpty else {
            findBarVC.clearCount()
            webView.evaluateJavaScript("window.__macdownLiteSearch && window.__macdownLiteSearch.clear();",
                                       completionHandler: nil)
            return
        }

        searchGeneration += 1
        let generation = searchGeneration

        let escaped = Self.jsString(query)
        let script = """
        (function () {
          var s = window.__macdownLiteSearch;
          if (!s) return { count: 0, index: -1, supported: false };
          var n = s.search(\(escaped), \(caseSensitive ? "true" : "false"));
          return { count: n, index: s.index, supported: true };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }
            guard generation == self.searchGeneration else { return }   // stale reply
            if let error {
                NSLog("find failed: \(error)")
                self.findBarVC.updateCount(matches: 0, current: 0)
                return
            }
            let dict = result as? [String: Any]
            let count = dict?["count"] as? Int ?? 0
            let index = dict?["index"] as? Int ?? 0
            self.findBarVC.updateCount(matches: count, current: max(0, index))
        }
    }

    /// Menu-driven "find next/previous": opens the bar if needed, then steps.
    func stepSearchFromMenu(_ direction: Int) {
        if !findBarVisible {
            guard !findBarVC.query.isEmpty else {
                showFindBar()
                return
            }
            showFindBar()
        }
        guard !findBarVC.query.isEmpty else { return }
        stepSearch(direction)
    }

    private func stepSearch(_ direction: Int) {
        guard findBarVisible, !findBarVC.query.isEmpty else { return }
        searchGeneration += 1
        let generation = searchGeneration

        let script = """
        (function () {
          var s = window.__macdownLiteSearch;
          if (!s || !s.count) return { count: 0, index: -1 };
          var i = s.next(\(direction), \(Settings.findWrapAround ? "true" : "false"));
          return { count: s.count, index: i };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self else { return }
            guard generation == self.searchGeneration else { return }
            let dict = result as? [String: Any]
            let count = dict?["count"] as? Int ?? 0
            let index = dict?["index"] as? Int ?? 0
            self.findBarVC.updateCount(matches: count, current: max(0, index))
        }
    }

    /// Re-run the active query after the document was re-rendered.
    private func refreshSearchAfterRender() {
        guard findBarVisible, !findBarVC.query.isEmpty else { return }
        // The new document needs its search.js to finish loading first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.findBarVisible else { return }
            self.runSearch(query: self.findBarVC.query,
                           caseSensitive: Settings.findCaseSensitive,
                           resetIndex: true)
        }
    }

    private static func jsString(_ s: String) -> String {
        // JSON-encode so quotes/newlines/backslashes cannot break out.
        let data = try? JSONSerialization.data(withJSONObject: [s], options: [])
        guard let data,
              let arr = String(data: data, encoding: .utf8),
              arr.count >= 2 else {
            return "\"\""
        }
        return String(arr.dropFirst().dropLast())   // strip the surrounding [ ]
    }

    // MARK: - Zoom

    var zoom: Double {
        get { webView.pageZoom }
        set {
            let clamped = min(max(newValue, 0.25), 5.0)
            webView.pageZoom = clamped
            Settings.zoom = clamped
        }
    }

    func zoomIn()    { zoom += 0.1 }
    func zoomOut()   { zoom -= 0.1 }
    func zoomReset() { zoom = 1.0 }
    func restoreZoom() { webView.pageZoom = Settings.zoom }

    // MARK: - Printing

    func printDocument() {
        guard let window else { return }
        let info = configuredPrintInfo()
        let op = webView.printOperation(with: info)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: - File watching

    private func startWatching() {
        let w = FileWatcher(url: fileURL)
        w.onChange = { [weak self] in
            guard let self, self.window?.isVisible == true else { return }
            // While editing, only pick up external changes if we have nothing
            // unsaved (otherwise our own save would clobber the buffer).
            if self.isEditing && self.isDirty { return }
            self.render()
        }
        w.start()
        watcher = w
    }

    private static func readMarkdown(at url: URL) -> String {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        var enc: String.Encoding = .utf8
        if let s = try? String(contentsOf: url, usedEncoding: &enc) { return s }
        return "# 无法读取文件\n\n`\(url.path)`\n\n可能是二进制文件，或使用了不支持的文本编码。"
    }
}

// MARK: - NSWindowDelegate

extension ViewerWindowController: NSWindowDelegate {

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "要保存对“\(fileURL.lastPathComponent)”的更改吗？"
        alert.informativeText = "如果不保存，你的更改将丢失。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            save()
            return true
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        watcher?.stop()
        onClose?(self)
    }
}

// MARK: - Navigation

extension ViewerWindowController: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        switch url.scheme {
        case "http", "https":
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)

        case AssetSchemeHandler.scheme:
            if url.fragment != nil {
                decisionHandler(.allow)
            } else if url.host == AssetSchemeHandler.fileSystemHost {
                NSWorkspace.shared.open(URL(fileURLWithPath: url.path))
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }

        case "file":
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)

        default:
            decisionHandler(.allow)
        }
    }
}

extension ViewerWindowController: WKUIDelegate {

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
        return nil
    }
}
