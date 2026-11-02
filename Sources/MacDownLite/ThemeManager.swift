import Foundation

/// Manages the CSS themes shipped with the app (taken from MacDown).
enum ThemeManager {

    struct Theme {
        let name: String        // display name
        let resource: String    // file name inside Resources/Themes
        let css: String
        let isDark: Bool
    }

    /// Friendly display names for MacDown's stylesheet files.
    private static let displayNames: [String: String] = [
        "Word 文档": "Word 文档",
        "GitHub2": "GitHub 2",
        "GitHub": "GitHub 1",
        "Clearness": "Clearness",
        "Clearness Dark": "Clearness Dark",
        "Solarized (Light)": "Solarized Light",
        "Solarized (Dark)": "Solarized Dark",
    ]

    private static let darkThemes: Set<String> = ["Clearness Dark", "Solarized (Dark)"]

    static let themes: [Theme] = {
        let dir = Resources.themesDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                  includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "css" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { lhs, rhs in
                // Keep a stable, sensible order: GitHub2 first, then alphabetical.
                if lhs == Settings.defaultThemeName { return true }
                if rhs == Settings.defaultThemeName { return false }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            .compactMap { base -> Theme? in
                guard let css = try? String(contentsOf: dir.appendingPathComponent(base + ".css"),
                                            encoding: .utf8) else { return nil }
                return Theme(name: displayNames[base] ?? base,
                             resource: base,
                             css: css,
                             isDark: darkThemes.contains(base))
            }
    }()

    static func theme(named name: String) -> Theme? {
        themes.first { $0.resource == name } ?? themes.first
    }

    static var current: Theme {
        theme(named: Settings.themeName) ?? themes.first!
    }

    /// True when the current theme is dark (used to pick a matching Prism look).
    static var currentIsDark: Bool { current.isDark }
}

extension ThemeManager.Theme {
    /// Prism syntax-highlighting stylesheet that pairs with this document theme:
    /// a light code palette for light themes, a dark one for dark themes.
    var prismCSS: String {
        let file = isDark ? "prism-tomorrow.css" : "prism.css"
        let url = Resources.root.appendingPathComponent("prism").appendingPathComponent(file)
        return Resources.text(at: url) ?? ""
    }
}
