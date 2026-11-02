import Foundation

/// Locates the resources that ship inside the app bundle.
enum Resources {

    /// Contents/Resources inside the .app, or ./Resources when run from a checkout.
    static var root: URL {
        if let r = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: r.appendingPathComponent("Themes").path) {
            return r
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources")
    }

    static var themesDirectory: URL { root.appendingPathComponent("Themes") }
    static var prismCSS: URL { root.appendingPathComponent("prism").appendingPathComponent("prism.css") }

    static var mathJaxDirectory: URL { root.appendingPathComponent("mathjax") }
    static var mathJaxScript: URL { mathJaxDirectory.appendingPathComponent("mathjax.js") }
    static var mathJaxConfig: URL { mathJaxDirectory.appendingPathComponent("config.js") }

    static var searchScript: URL { root.appendingPathComponent("search.js") }
    static var exportModelScript: URL { root.appendingPathComponent("export-model.js") }

    static func text(at url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }
}
