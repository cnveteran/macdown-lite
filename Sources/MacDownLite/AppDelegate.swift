import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var controllers: [ViewerWindowController] = []
    private var pendingURLs: [URL] = []
    private var didFinishLaunching = false

    private let themeMenu = NSMenu()
    private let recentMenu = NSMenu()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        didFinishLaunching = true
        NSApp.activate(ignoringOtherApps: true)

        let queued = pendingURLs
        pendingURLs.removeAll()
        queued.forEach { open(url: $0) }

        if controllers.isEmpty { showWelcome() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWelcome() }
        return true
    }

    /// Finder "Open With" / `open -a`.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard didFinishLaunching else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        urls.forEach { open(url: $0) }
    }

    // MARK: - Opening

    @discardableResult
    func open(url: URL) -> ViewerWindowController {
        let standardized = url.standardizedFileURL

        if let existing = controllers.first(where: {
            $0.fileURL.standardizedFileURL == standardized
        }) {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            return existing
        }

        let controller = ViewerWindowController(fileURL: standardized)
        controller.onClose = { [weak self] ctl in
            self?.controllers.removeAll { $0 === ctl }
        }
        controller.onOpenURLs = { [weak self] urls in
            urls.forEach { self?.open(url: $0) }
        }
        controllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        Settings.noteRecent(standardized)
        return controller
    }

    private func showWelcome() {
        let help = Resources.root.appendingPathComponent("Help.md")
        if FileManager.default.fileExists(atPath: help.path) {
            open(url: help)
        }
    }

    private var activeController: ViewerWindowController? {
        if let c = NSApp.keyWindow?.windowController as? ViewerWindowController { return c }
        return controllers.last
    }

    // MARK: - Actions

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "选择要阅读的 Markdown 文件"
        panel.prompt = "打开"
        if panel.runModal() == .OK {
            panel.urls.forEach { open(url: $0) }
        }
    }

    @objc func openRecentFile(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        open(url: URL(fileURLWithPath: path))
    }

    @objc func clearRecents(_ sender: Any?) {
        Settings.clearRecents()
    }

    @objc func reloadDocument(_ sender: Any?) { activeController?.reload() }

    @objc func toggleEditorMode(_ sender: Any?) { activeController?.toggleEditor() }

    @objc func saveDocument(_ sender: Any?) { activeController?.save() }

    @objc func selectTheme(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        Settings.themeName = name
        controllers.forEach { $0.render() }
    }

    @objc func zoomIn(_ sender: Any?)      { activeController?.zoomIn() }
    @objc func zoomOut(_ sender: Any?)     { activeController?.zoomOut() }
    @objc func zoomActualSize(_ sender: Any?) { activeController?.zoomReset() }

    @objc func printDocument(_ sender: Any?) { activeController?.printDocument() }

    @objc func exportPDF(_ sender: Any?) { activeController?.presentExportPDF() }

    @objc func exportDocx(_ sender: Any?) { activeController?.presentExportDocx() }

    @objc func showHelp(_ sender: Any?) { showWelcome() }

    // MARK: Find

    @objc func performFind(_ sender: Any?) {
        activeController?.showFindBar()
    }

    @objc func findNext(_ sender: Any?) {
        activeController?.stepSearchFromMenu(1)
    }

    @objc func findPrevious(_ sender: Any?) {
        activeController?.stepSearchFromMenu(-1)
    }

    @objc func hideFindBar(_ sender: Any?) {
        activeController?.hideFindBar()
    }

    // MARK: Math

    @objc func toggleMathJax(_ sender: NSMenuItem) {
        Settings.mathJaxEnabled.toggle()
        sender.state = Settings.mathJaxEnabled ? .on : .off
        controllers.forEach { $0.render() }
    }

    @objc func toggleMathDollar(_ sender: NSMenuItem) {
        Settings.mathDollarDelimiter.toggle()
        sender.state = Settings.mathDollarDelimiter ? .on : .off
        controllers.forEach { $0.render() }
    }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appName = "MacDown Lite"

        // App menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 \(appName)",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 \(appName)",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "隐藏其他",
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "全部显示",
                        action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 \(appName)",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "打开…", action: #selector(openDocument(_:)), keyEquivalent: "o")

        let recentItem = NSMenuItem(title: "打开最近使用", action: nil, keyEquivalent: "")
        recentMenu.delegate = self
        recentItem.submenu = recentMenu
        fileMenu.addItem(recentItem)

        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "保存", action: #selector(saveDocument(_:)), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "关闭窗口",
                         action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(.separator())

        let exportItem = NSMenuItem(title: "导出为", action: nil, keyEquivalent: "")
        let exportMenu = NSMenu(title: "导出为")
        for (title, action) in [("PDF…", #selector(exportPDF(_:))),
                                ("Word 文档 (.docx)…", #selector(exportDocx(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            exportMenu.addItem(item)
        }
        exportItem.submenu = exportMenu
        fileMenu.addItem(exportItem)

        fileMenu.addItem(withTitle: "打印…", action: #selector(printDocument(_:)), keyEquivalent: "p")

        // Edit menu (reading-oriented subset)
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())

        // These must target the delegate explicitly: while the web view holds
        // focus the responder chain never reaches AppDelegate, so an untargeted
        // ⌘G would silently do nothing.
        let findItems: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("查找…", #selector(performFind(_:)), "f", .command),
            ("查找下一个", #selector(findNext(_:)), "g", .command),
            ("查找上一个", #selector(findPrevious(_:)), "g", [.command, .shift]),
        ]
        for (title, action, key, mask) in findItems {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mask
            item.target = self
            editMenu.addItem(item)
        }

        // View menu
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "显示")
        viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "重新载入", action: #selector(reloadDocument(_:)), keyEquivalent: "r")
        viewMenu.addItem(withTitle: "编辑模式", action: #selector(toggleEditorMode(_:)), keyEquivalent: "e")
        viewMenu.addItem(.separator())

        let themeItem = NSMenuItem(title: "主题", action: nil, keyEquivalent: "")
        themeMenu.delegate = self
        themeItem.submenu = themeMenu
        viewMenu.addItem(themeItem)

        viewMenu.addItem(.separator())

        let mathItem = NSMenuItem(title: "数学公式 (MathJax)",
                                  action: #selector(toggleMathJax(_:)),
                                  keyEquivalent: "")
        mathItem.target = self
        mathItem.state = Settings.mathJaxEnabled ? .on : .off
        viewMenu.addItem(mathItem)

        let dollarItem = NSMenuItem(title: "用 $ 作为行内公式定界符",
                                    action: #selector(toggleMathDollar(_:)),
                                    keyEquivalent: "")
        dollarItem.target = self
        dollarItem.state = Settings.mathDollarDelimiter ? .on : .off
        viewMenu.addItem(dollarItem)

        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "放大", action: #selector(zoomIn(_:)), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "缩小", action: #selector(zoomOut(_:)), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "实际大小", action: #selector(zoomActualSize(_:)), keyEquivalent: "0")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "进入全屏幕",
                         action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]

        // Window menu
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "最小化",
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "前置全部窗口",
                           action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        // Help menu
        let helpItem = NSMenuItem()
        mainMenu.addItem(helpItem)
        let helpMenu = NSMenu(title: "帮助")
        helpItem.submenu = helpMenu
        helpMenu.addItem(withTitle: "MacDown Lite 帮助", action: #selector(showHelp(_:)), keyEquivalent: "?")
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    private func rebuildThemeMenu() {
        themeMenu.removeAllItems()
        for theme in ThemeManager.themes {
            let item = NSMenuItem(title: theme.name,
                                  action: #selector(selectTheme(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = theme.resource
            item.state = (theme.resource == Settings.themeName) ? .on : .off
            themeMenu.addItem(item)
        }
    }

    private func rebuildRecentMenu() {
        recentMenu.removeAllItems()
        let recents = Settings.recentFiles
        if recents.isEmpty {
            let empty = NSMenuItem(title: "无最近文件", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
            return
        }
        for path in recents {
            let item = NSMenuItem(title: (path as NSString).lastPathComponent,
                                  action: #selector(openRecentFile(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = path
            item.toolTip = path
            recentMenu.addItem(item)
        }
        recentMenu.addItem(.separator())
        let clear = NSMenuItem(title: "清除菜单", action: #selector(clearRecents(_:)), keyEquivalent: "")
        clear.target = self
        recentMenu.addItem(clear)
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === themeMenu { rebuildThemeMenu() }
        if menu === recentMenu { rebuildRecentMenu() }
    }
}
