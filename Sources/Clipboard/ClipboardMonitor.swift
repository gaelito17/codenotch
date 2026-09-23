import AppKit

/// Watches the pasteboard for copies and writes picked entries back.
///
/// macOS has no notification for a pasteboard change, so this polls
/// `changeCount` — a cheap counter read that touches no content — and reads
/// the pasteboard only when it moves.
final class ClipboardMonitor {
    /// Fast enough that copying twice in quick succession still records both;
    /// slow enough to cost nothing measurable.
    static let pollInterval: TimeInterval = 0.5

    var onCapture: ((ClipboardEntry) -> Void)?

    private let pasteboard: NSPasteboard
    private let now: () -> Date
    private let frontmostBundleID: () -> String?
    private var timer: Timer?
    private var lastChangeCount: Int

    init(pasteboard: NSPasteboard = .general,
         now: @escaping () -> Date = Date.init,
         frontmostBundleID: @escaping () -> String? = {
             NSWorkspace.shared.frontmostApplication?.bundleIdentifier
         }) {
        self.pasteboard = pasteboard
        self.now = now
        self.frontmostBundleID = frontmostBundleID
        // Whatever is on the pasteboard at start was copied before the history
        // was switched on, and is not recorded.
        self.lastChangeCount = pasteboard.changeCount
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        // A copy made while a menu is open still counts.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Reads a new copy, if there is one. Called by the timer; exposed so
    /// tests can drive it without waiting on a run loop.
    func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard !ClipboardCapture.isPrivate(types) else {
            Log.clipboard.debug("Skipped a copy marked private")
            return
        }

        let raw: [[String: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            var representations: [String: Data] = [:]
            for type in item.types where ClipboardType.kept.contains(type.rawValue) {
                representations[type.rawValue] = item.data(forType: type)
            }
            return representations
        }
        guard let items = ClipboardCapture.normalise(raw) else { return }

        let entry = ClipboardEntry(items: items, copiedAt: now(), sourceBundleID: frontmostBundleID())
        Log.clipboard.debug("Captured \(items.count, privacy: .public) item(s), \(entry.byteCount, privacy: .public) bytes")
        onCapture?(entry)
    }

    /// Puts an entry back on the pasteboard, every representation it was
    /// copied with, so the app it is pasted into picks as it would have.
    ///
    /// The write moves `changeCount`, and is taken as already seen: picking
    /// from the history is not a new copy. The caller promotes the entry.
    func write(_ entry: ClipboardEntry) {
        pasteboard.clearContents()
        let items = entry.items.map { item -> NSPasteboardItem in
            let pasteboardItem = NSPasteboardItem()
            for (type, content) in item.representations {
                pasteboardItem.setData(content, forType: NSPasteboard.PasteboardType(type))
            }
            return pasteboardItem
        }
        pasteboard.writeObjects(items)
        lastChangeCount = pasteboard.changeCount
    }
}
