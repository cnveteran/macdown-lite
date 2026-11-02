import AppKit

/// A slim find bar that slides in above the preview, driven by native controls.
///
/// Search itself runs inside the web view (see Resources/search.js) so the
/// highlights survive theme changes without re-parsing the document.
final class FindBarViewController: NSViewController, NSSearchFieldDelegate {

    let searchField = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let caseButton = NSButton()
    private let doneButton = NSButton()

    /// Fired as the user types or changes options.
    var onQueryChange: ((String, Bool) -> Void)?
    /// Fired for "next"/"previous" (dir is +1 or -1).
    var onStep: ((Int) -> Void)?
    var onDismiss: (() -> Void)?

    private var caseSensitive = false

    override func loadView() {
        let container = NSView()

        searchField.placeholderString = "查找"
        searchField.delegate = self
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = false

        countLabel.alignment = .right
        countLabel.textColor = .secondaryLabelColor
        countLabel.font = NSFont.systemFont(ofSize: 11)
        countLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        countLabel.stringValue = ""
        countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 62).isActive = true

        configure(previousButton, symbol: "chevron.up", fallback: "↑", action: #selector(stepBackward))
        configure(nextButton, symbol: "chevron.down", fallback: "↓", action: #selector(stepForward))

        caseButton.title = "Aa"
        caseButton.bezelStyle = .recessed
        caseButton.setButtonType(.pushOnPushOff)
        caseButton.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        caseButton.target = self
        caseButton.action = #selector(toggleCase)
        caseButton.toolTip = "区分大小写"
        caseButton.widthAnchor.constraint(equalToConstant: 34).isActive = true

        doneButton.title = "完成"
        doneButton.bezelStyle = .recessed
        doneButton.target = self
        doneButton.action = #selector(dismissBar)
        doneButton.keyEquivalent = "\u{1b}"      // Esc

        let stack = NSStackView(views: [
            searchField, countLabel, previousButton, nextButton, caseButton, doneButton,
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])

        self.view = container
    }

    private func configure(_ button: NSButton, symbol: String, fallback: String, action: Selector) {
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.title = fallback
        }
        button.bezelStyle = .recessed
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
    }

    // MARK: - State

    /// Result of the last search, shown as "3 / 17".
    func updateCount(matches: Int, current: Int) {
        if matches == 0 {
            let hasQuery = !searchField.stringValue.isEmpty
            countLabel.stringValue = hasQuery ? "无结果" : ""
            countLabel.textColor = hasQuery ? .systemRed : .secondaryLabelColor
        } else {
            countLabel.stringValue = "\(current + 1) / \(matches)"
            countLabel.textColor = .secondaryLabelColor
        }
        let hasMatches = matches > 0
        previousButton.isEnabled = hasMatches
        nextButton.isEnabled = hasMatches
    }

    func clearCount() {
        countLabel.stringValue = ""
        countLabel.textColor = .secondaryLabelColor
        previousButton.isEnabled = false
        nextButton.isEnabled = false
    }

    func focus() {
        view.window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
    }

    var query: String { searchField.stringValue }

    // MARK: - Actions

    private func emitQuery() {
        onQueryChange?(searchField.stringValue, caseSensitive)
    }

    @objc private func stepForward()  { onStep?(1) }
    @objc private func stepBackward() { onStep?(-1) }

    @objc private func toggleCase() {
        caseSensitive = (caseButton.state == .on)
        caseButton.bezelColor = caseSensitive ? .controlAccentColor : nil
        emitQuery()
    }

    @objc private func dismissBar() { onDismiss?() }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        emitQuery()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            // Return = find next (Shift+Return = previous, handled by the field).
            onStep?(1)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismissBar()
            return true
        default:
            return false
        }
    }
}
