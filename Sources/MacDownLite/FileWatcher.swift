import Foundation

/// Watches a single file for on-disk changes by polling its modification date
/// and size. Simple, robust and cheap for a viewer (editors often replace the
/// file rather than writing in place, which defeats plain vnode watching).
final class FileWatcher {

    private let url: URL
    private let interval: TimeInterval
    private var timer: Timer?
    private var lastStamp: Stamp?

    var onChange: (() -> Void)?

    private struct Stamp: Equatable {
        let modified: Date?
        let size: UInt64?
    }

    init(url: URL, interval: TimeInterval = 0.7) {
        self.url = url
        self.interval = interval
    }

    func start() {
        stop()
        lastStamp = currentStamp()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Re-read the baseline stamp after we wrote the file ourselves, so our own
    /// save does not immediately look like an external change.
    func refreshBaseline() {
        lastStamp = currentStamp()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let stamp = currentStamp()
        if stamp != lastStamp {
            lastStamp = stamp
            onChange?()
        }
    }

    private func currentStamp() -> Stamp {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return Stamp(modified: values?.contentModificationDate,
                     size: values?.fileSize.map { UInt64($0) })
    }

    deinit { stop() }
}
