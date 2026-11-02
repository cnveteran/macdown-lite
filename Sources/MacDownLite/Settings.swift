import Foundation

/// UserDefaults keys and small helpers shared across the app.
enum Settings {
    static let themeNameKey = "themeName"
    static let zoomKey = "zoomLevel"
    static let recentFilesKey = "recentFiles"
    static let windowFrameKey = "windowFrame"
    static let editorVisibleKey = "editorVisible"
    static let editorWidthKey = "editorWidth"
    static let mathJaxEnabledKey = "mathJaxEnabled"
    static let mathDollarDelimiterKey = "mathDollarDelimiter"
    static let findCaseSensitiveKey = "findCaseSensitive"
    static let findWrapAroundKey = "findWrapAround"

    static let defaultThemeName = "GitHub2"

    static var themeName: String {
        get { UserDefaults.standard.string(forKey: themeNameKey) ?? defaultThemeName }
        set { UserDefaults.standard.set(newValue, forKey: themeNameKey) }
    }

    static var zoom: Double {
        get {
            let v = UserDefaults.standard.double(forKey: zoomKey)
            return v > 0 ? v : 1.0
        }
        set { UserDefaults.standard.set(newValue, forKey: zoomKey) }
    }

    /// Editor pane visibility. Defaults to `false`: the app opens as a pure reader.
    static var editorVisible: Bool {
        get { UserDefaults.standard.bool(forKey: editorVisibleKey) }
        set { UserDefaults.standard.set(newValue, forKey: editorVisibleKey) }
    }

    /// TeX math (MathJax) rendering. Defaults to ON so `$...$` just works.
    static var mathJaxEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: mathJaxEnabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: mathJaxEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: mathJaxEnabledKey) }
    }

    /// Also treat `$...$` / `$$...$$` as math delimiters (MacDown's
    /// "use dollar sign as inline delimiter" option). `\(...\)` and
    /// `\[...\]` always work.
    static var mathDollarDelimiter: Bool {
        get {
            // MacDown ships with this on; default the same way.
            if UserDefaults.standard.object(forKey: mathDollarDelimiterKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: mathDollarDelimiterKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: mathDollarDelimiterKey) }
    }

    static var findCaseSensitive: Bool {
        get { UserDefaults.standard.bool(forKey: findCaseSensitiveKey) }
        set { UserDefaults.standard.set(newValue, forKey: findCaseSensitiveKey) }
    }

    static var findWrapAround: Bool {
        get {
            if UserDefaults.standard.object(forKey: findWrapAroundKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: findWrapAroundKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: findWrapAroundKey) }
    }

    static var recentFiles: [String] {
        get { UserDefaults.standard.stringArray(forKey: recentFilesKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: recentFilesKey) }
    }

    static let maxRecentFiles = 12

    static func noteRecent(_ url: URL) {
        var list = recentFiles
        let path = url.path
        list.removeAll { $0 == path }
        list.insert(path, at: 0)
        if list.count > maxRecentFiles { list = Array(list.prefix(maxRecentFiles)) }
        recentFiles = list
    }

    static func clearRecents() {
        recentFiles = []
    }
}
