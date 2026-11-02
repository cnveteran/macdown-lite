// Standalone harness: compile MathPreprocessor together with this file.
import Foundation

var failures = 0
var checks = 0

func check(_ label: String, _ actual: String, _ expected: String) {
    checks += 1
    if actual == expected {
        print("  ok   \(label)")
    } else {
        failures += 1
        print("  FAIL \(label)")
        print("       expected: \(expected)")
        print("       actual:   \(actual)")
    }
}

// Simulated pipeline: preprocess -> (pretend hoedown) -> restore.
func roundtrip(_ src: String, dollar: Bool = true) -> (markdown: String, spans: Int, restored: String) {
    let r = MathPreprocessor.preprocess(src, enableDollar: dollar)
    let restored = MathPreprocessor.restore(in: r.markdown, spans: r.spans)
    return (r.markdown, r.spans.count, restored)
}

print("--- inline delimiters ---")
var t = roundtrip("Energy \\(E = mc^2\\) here.")
check("backslash-paren extracted", "\(t.spans)", "1")
check("backslash-paren restored", t.restored, "Energy \\(E = mc^2\\) here.")

t = roundtrip("Cost is $x^2$ ok.")
check("dollar extracted", "\(t.spans)", "1")
check("dollar restored (normalised to backslash form)", t.restored, "Cost is \\(x^2\\) ok.")

print("--- display delimiters ---")
t = roundtrip("a\n\n\\[\\int_0^1 x\\,dx\\]\n\nb")
check("display bracket extracted", "\(t.spans)", "1")
check("display bracket restored", t.restored, "a\n\n\\[\\int_0^1 x\\,dx\\]\n\nb")

t = roundtrip("a\n\n$$\\sum_{i=1}^n i$$\n\nb")
check("display dollar extracted", "\(t.spans)", "1")
check("display dollar restored (normalised)", t.restored, "a\n\n\\[\\sum_{i=1}^n i\\]\n\nb")

print("--- false positives must stay literal ---")
t = roundtrip("It costs $5 today.")
check("price $5 untouched", "\(t.spans)", "0")
check("price $5 text intact", t.restored, "It costs $5 today.")

t = roundtrip("Prices: $5 and $9 total.")
check("two prices untouched", "\(t.spans)", "0")

t = roundtrip("Use $ 5 dollars.")
check("spaced dollar untouched", "\(t.spans)", "0")

t = roundtrip("a$b$c")
check("glued dollar untouched", "\(t.spans)", "0")

print("--- code must be protected ---")
t = roundtrip("```\n\\(E = mc^2\\)\n```")
check("fenced code untouched", "\(t.spans)", "0")
check("fenced code text intact", t.restored, "```\n\\(E = mc^2\\)\n```")

t = roundtrip("Inline `\\(x\\)` code.")
check("inline code untouched", "\(t.spans)", "0")

print("--- escaping ---")
t = roundtrip("\\(a < b > c & d\\)")
check("html-escaped in restore", t.restored, "\\(a &lt; b &gt; c &amp; d\\)")

print("--- dollar disabled ---")
t = roundtrip("Cost is $x^2$ ok.", dollar: false)
check("dollar off -> no spans", "\(t.spans)", "0")
t = roundtrip("Energy \\(E = mc^2\\) here.", dollar: false)
check("backslash still works when dollar off", "\(t.spans)", "1")

print("")
print("checks=\(checks) failures=\(failures)")
exit(failures == 0 ? 0 : 1)
