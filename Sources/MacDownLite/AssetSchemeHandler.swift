import Foundation
import WebKit

/// Serves both bundled assets and the displayed document's local files to the
/// web view through a private URL scheme, so relative image paths, absolute
/// paths and file:// links all resolve without granting broad file access.
///
///   mdview://bundle/<path>   -> <app bundle>/Contents/Resources/<path>
///   mdview://fs/<abs path>   -> <abs path> on disk
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {

    static let scheme = "mdview"
    static let bundleHost = "bundle"
    static let fileSystemHost = "fs"

    /// Base URL to hand to WKWebView for a document: relative links resolve
    /// against this and land on mdview://fs/<absolute path>.
    static func baseURL(forDocumentAt url: URL) -> URL {
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = fileSystemHost
        comps.path = url.deletingLastPathComponent().path + "/"
        return comps.url ?? URL(string: "\(scheme)://\(fileSystemHost)/")!
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }

        var fileURL: URL?
        switch url.host {
        case Self.bundleHost:
            fileURL = Resources.root.appendingPathComponent(stripLeadingSlash(url.path))
        case Self.fileSystemHost:
            fileURL = URL(fileURLWithPath: url.path)   // url.path is already absolute
        default:
            fileURL = nil
        }

        guard let file = fileURL,
              let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = URLResponse(url: url,
                                   mimeType: Self.mimeType(for: file.pathExtension),
                                   expectedContentLength: data.count,
                                   textEncodingName: nil)
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        // Nothing to cancel: responses are produced synchronously.
    }

    private func stripLeadingSlash(_ s: String) -> String {
        s.hasPrefix("/") ? String(s.dropFirst()) : s
    }

    private static let mimeTypes: [String: String] = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "gif": "image/gif", "svg": "image/svg+xml", "webp": "image/webp",
        "bmp": "image/bmp", "ico": "image/x-icon", "tiff": "image/tiff",
        "css": "text/css", "js": "text/javascript", "json": "application/json",
        "html": "text/html", "htm": "text/html", "txt": "text/plain",
        "md": "text/plain", "pdf": "application/pdf",
        "mp4": "video/mp4", "webm": "video/webm", "mov": "video/quicktime",
        "mp3": "audio/mpeg", "wav": "audio/wav", "m4a": "audio/mp4",
        "woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf",
        "otf": "font/otf", "eot": "application/vnd.ms-fontobject",
    ]

    static func mimeType(for ext: String) -> String {
        mimeTypes[ext.lowercased()] ?? "application/octet-stream"
    }
}
