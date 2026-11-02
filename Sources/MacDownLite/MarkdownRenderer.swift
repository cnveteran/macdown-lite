import Foundation
import CHoedown

/// Thin Swift wrapper over the bundled hoedown renderer (same engine MacDown uses).
enum MarkdownRenderer {

    // MARK: hoedown_extensions (values mirror hoedown's document.h)
    private enum Ext {
        static let tables        = Int32(1 << 0)
        static let fencedCode    = Int32(1 << 1)
        static let footnotes     = Int32(1 << 2)
        static let autolink      = Int32(1 << 3)
        static let strikethrough = Int32(1 << 4)
        static let underline     = Int32(1 << 5)
        static let highlight     = Int32(1 << 6)
        static let quote         = Int32(1 << 7)
        static let superscript   = Int32(1 << 8)
        static let math          = Int32(1 << 9)
        static let noIntraEmphasis = Int32(1 << 11)
        static let mathExplicit  = Int32(1 << 13)
        static let disableIndentedCode = Int32(1 << 14)
    }

    // MARK: hoedown_html_flags (+ MacDown patch bits)
    private enum HtmlFlag {
        static let skipHTML    = Int32(1 << 0)
        static let escape      = Int32(1 << 1)
        static let hardWrap    = Int32(1 << 2)
        static let useXHTML    = Int32(1 << 3)
        static let taskList    = Int32(1 << 4)   // MacDown patch
        static let lineNumbers = Int32(1 << 5)   // MacDown patch
        static let blockcodeInformation = Int32(1 << 6) // MacDown patch
    }

    /// Same defaults MacDown ships with, minus math (which is opt-in at runtime).
    static let baseExtensions: Int32 = {
        Ext.tables | Ext.fencedCode | Ext.footnotes | Ext.autolink | Ext.strikethrough
            | Ext.underline | Ext.highlight | Ext.quote | Ext.superscript
    }()

    /// hoedown's own math extension stays OFF: `MathPreprocessor` extracts TeX
    /// before parsing and re-inserts it afterwards. hoedown's implementation
    /// requires a literal double backslash (`\\[`) and mis-reads prices such
    /// as `$5` as math.
    static var defaultExtensions: Int32 { baseExtensions }

    /// Task-list checkboxes + `language-xxx` classes (Prism) on code blocks.
    static let defaultHtmlFlags: Int32 = HtmlFlag.taskList | HtmlFlag.blockcodeInformation

    /// Render markdown to an HTML fragment (no <html> wrapper).
    static func bodyHTML(_ markdown: String,
                         extensions: Int32? = nil,
                         htmlFlags: Int32 = defaultHtmlFlags,
                         smartypants: Bool = true) -> String {
        let extensions = extensions ?? defaultExtensions
        return render(markdown, extensions: extensions,
                      htmlFlags: htmlFlags, smartypants: smartypants)
    }

    /// Render just the table of contents fragment.
    static func tocHTML(_ markdown: String,
                        extensions: Int32? = nil) -> String {
        let extensions = extensions ?? defaultExtensions
        let bytes = Array(markdown.utf8)
        let out: String? = bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return nil }
            return base.withMemoryRebound(to: CChar.self, capacity: buf.count) { ptr in
                guard let c = mp_render_toc(ptr, buf.count, extensions) else { return nil }
                defer { mp_free(c) }
                return String(cString: c)
            }
        }
        return out ?? ""
    }

    private static func render(_ markdown: String, extensions: Int32,
                               htmlFlags: Int32, smartypants: Bool) -> String {
        let bytes = Array(markdown.utf8)
        let out: String? = bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return nil }
            return base.withMemoryRebound(to: CChar.self, capacity: buf.count) { ptr in
                guard let c = mp_render_html(ptr, buf.count, extensions, htmlFlags,
                                             smartypants ? 1 : 0) else { return nil }
                defer { mp_free(c) }
                return String(cString: c)
            }
        }
        return out ?? ""
    }
}
