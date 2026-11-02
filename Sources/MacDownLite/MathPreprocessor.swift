import Foundation

/// Extracts TeX math from the markdown source before it reaches hoedown.
///
/// Why this exists instead of hoedown's own math extension:
///
/// * hoedown only recognises `\\(...\\)` / `\\[...\\]` (a *literal double*
///   backslash in the source), which nobody types, and it mangles `\(x\)`
///   down to `(x)`.
/// * hoedown's `$` handling has no sanity checks, so `It costs $5 and $9` is
///   parsed as one math span.
///
/// So we find math ourselves — respecting fenced blocks and code spans — stash
/// each formula behind a private-use placeholder, and splice the real MathJax
/// delimiters back in after hoedown has produced HTML. That leaves hoedown's
/// math extension switched off entirely and keeps code blocks untouched.
enum MathPreprocessor {

    struct Span {
        let tex: String
        let isDisplay: Bool
    }

    struct Result {
        let markdown: String
        let spans: [Span]
        var hasMath: Bool { !spans.isEmpty }
    }

    // Private Use Area markers: hoedown passes these through verbatim.
    private static let markerStart: Character = "\u{E000}"
    private static let markerEnd: Character = "\u{E001}"
    private static let markerPrefix = "MDLM"

    // MARK: - Extraction

    static func preprocess(_ input: String, enableDollar: Bool) -> Result {
        var spans: [Span] = []
        var out = String()
        out.reserveCapacity(input.count)

        let chars = Array(input)
        let n = chars.count
        var i = 0

        var inFence = false
        var fenceChar: Character = "`"
        var fenceLen = 0
        var atLineStart = true

        while i < n {
            let c = chars[i]

            // --- fenced code blocks (``` / ~~~) -------------------------------
            if atLineStart && (c == "`" || c == "~") {
                var k = i
                while k < n && chars[k] == c { k += 1 }
                let runLen = k - i
                if runLen >= 3 {
                    if !inFence {
                        inFence = true
                        fenceChar = c
                        fenceLen = runLen
                    } else if c == fenceChar && runLen >= fenceLen {
                        inFence = false
                    }
                    while i < k { out.append(chars[i]); i += 1 }
                    atLineStart = false
                    continue
                }
            }

            if inFence {
                out.append(c)
                atLineStart = (c == "\n")
                i += 1
                continue
            }

            // --- inline code spans (`code`) ----------------------------------
            if c == "`" {
                var k = i
                while k < n && chars[k] == "`" { k += 1 }
                let ticks = k - i
                var j = k
                var close: Int? = nil
                while j < n {
                    if chars[j] == "`" {
                        var e = j
                        while e < n && chars[e] == "`" { e += 1 }
                        if e - j == ticks { close = e; break }
                        j = e
                    } else {
                        j += 1
                    }
                }
                let stop = close ?? min(n, k)
                while i < stop { out.append(chars[i]); i += 1 }
                atLineStart = false
                continue
            }

            // --- \( ... \)  and  \[ ... \] -----------------------------------
            if c == "\\", i + 1 < n, chars[i + 1] == "(" || chars[i + 1] == "[" {
                let isDisplay = chars[i + 1] == "["
                let closerChar: Character = isDisplay ? "]" : ")"
                var j = i + 2
                var closeIdx = -1
                while j + 1 < n {
                    if chars[j] == "\\", chars[j + 1] == closerChar { closeIdx = j; break }
                    j += 1
                }
                if closeIdx > i + 2 {
                    let tex = String(chars[(i + 2)..<closeIdx])
                    if !tex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        spans.append(Span(tex: tex, isDisplay: isDisplay))
                        out += placeholder(spans.count - 1)
                        i = closeIdx + 2
                        atLineStart = false
                        continue
                    }
                }
            }

            // --- $ ... $  and  $$ ... $$ -------------------------------------
            if c == "$", enableDollar {
                let isDisplay = (i + 1 < n && chars[i + 1] == "$")
                let delimLen = isDisplay ? 2 : 1
                let contentStart = i + delimLen
                var j = contentStart
                var closeIdx = -1

                while j < n {
                    if chars[j] == "\\" { j += 2; continue }
                    if chars[j] == "\n" && !isDisplay { break }   // inline: one line
                    if chars[j] == "$" {
                        if isDisplay {
                            if j + 1 < n && chars[j + 1] == "$" { closeIdx = j; break }
                        } else {
                            closeIdx = j
                            break
                        }
                    }
                    j += 1
                }

                if closeIdx > contentStart {
                    let tex = String(chars[contentStart..<closeIdx])
                    if isValidDollarMath(tex, isDisplay: isDisplay, chars: chars, openIndex: i) {
                        spans.append(Span(tex: tex, isDisplay: isDisplay))
                        out += placeholder(spans.count - 1)
                        i = closeIdx + delimLen
                        atLineStart = false
                        continue
                    }
                }
            }

            out.append(c)
            atLineStart = (c == "\n")
            i += 1
        }

        return Result(markdown: out, spans: spans)
    }

    /// Guards against the classic false positives: `$5`, `$ 5`, `x$y`, `$ `.
    private static func isValidDollarMath(_ tex: String,
                                          isDisplay: Bool,
                                          chars: [Character],
                                          openIndex: Int) -> Bool {
        if tex.isEmpty { return false }

        if isDisplay {
            // $$...$$ is explicit enough; just refuse a blank body.
            return !tex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        // Inline `$...$`: the content must be *tight* (no leading/trailing
        // whitespace) …
        guard tex == tex.trimmingCharacters(in: .whitespaces) else { return false }
        // … must contain something other than digits (so `$5$` stays literal) …
        guard tex.contains(where: { !$0.isNumber && !$0.isWhitespace }) else { return false }
        // … and the opening `$` must not be glued to a word character.
        if openIndex > 0 {
            let prev = chars[openIndex - 1]
            if prev.isLetter || prev.isNumber { return false }
        }
        // A trailing `$` preceded by a digit is a price, not a delimiter.
        if let last = tex.last, last.isNumber, tex.count == 1 { return false }
        return true
    }

    private static func placeholder(_ index: Int) -> String {
        "\(markerStart)\(markerPrefix)\(index)\(markerEnd)"
    }

    // MARK: - Restoration

    /// Replaces every placeholder in the rendered HTML with real MathJax
    /// delimiters. Skips over anything that is not a well-formed placeholder.
    static func restore(in html: String, spans: [Span]) -> String {
        guard !spans.isEmpty else { return html }

        var out = String()
        out.reserveCapacity(html.count + spans.count * 24)

        let chars = Array(html)
        let n = chars.count
        var i = 0

        while i < n {
            if chars[i] == markerStart {
                var j = i + 1
                var body = ""
                while j < n && chars[j] != markerEnd {
                    body.append(chars[j])
                    j += 1
                }
                if j < n, body.hasPrefix(markerPrefix) {
                    let digits = body.dropFirst(markerPrefix.count)
                    if let idx = Int(digits), spans.indices.contains(idx) {
                        let span = spans[idx]
                        out += span.isDisplay ? "\\[" : "\\("
                        out += escapeForHTML(span.tex)
                        out += span.isDisplay ? "\\]" : "\\)"
                        i = j + 1
                        continue
                    }
                }
                // Malformed: drop the stray marker so it cannot leak into the page.
                i += 1
                continue
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }

    /// TeX bodies sit in HTML text nodes, so `<`, `>` and `&` must be escaped.
    /// Backslashes and braces are left alone — MathJax needs them verbatim.
    private static func escapeForHTML(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.append(ch)
            }
        }
        return out
    }
}
