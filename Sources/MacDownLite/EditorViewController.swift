import AppKit

/// Plain-text markdown editor pane (left side of the split view).
final class EditorViewController: NSViewController, NSTextViewDelegate {

    let textView = NSTextView()
    private let scrollView = NSScrollView()

    /// Fired on every edit with the current text.
    var onTextChange: ((String) -> Void)?
    /// Fired when the user asks to save (⌘S inside the text view).
    var onSave: (() -> Void)?

    private var suppressCallbacks = false

    override func loadView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.delegate = self
        textView.isEditable = true

        scrollView.documentView = textView
        self.view = scrollView
    }

    // MARK: - Content

    func setText(_ text: String) {
        suppressCallbacks = true
        textView.string = text
        textView.undoManager?.removeAllActions()
        suppressCallbacks = false
    }

    var text: String { textView.string }

    /// Replace the text without disturbing the undo stack (external file change).
    func reloadText(_ text: String) {
        guard text != textView.string else { return }
        setText(text)
    }

    func applyAppearance(isDark: Bool) {
        let bg = isDark ? NSColor(srgbRed: 0.11, green: 0.12, blue: 0.13, alpha: 1)
                        : NSColor.textBackgroundColor
        let fg = isDark ? NSColor(srgbRed: 0.85, green: 0.87, blue: 0.88, alpha: 1)
                        : NSColor.textColor
        scrollView.backgroundColor = bg
        textView.backgroundColor = bg
        textView.textColor = fg
        textView.insertionPointColor = isDark ? .white : .black
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard !suppressCallbacks else { return }
        onTextChange?(textView.string)
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            // Keep it simple: plain newline, no auto-indent games.
            return false
        }
        return false
    }
}
