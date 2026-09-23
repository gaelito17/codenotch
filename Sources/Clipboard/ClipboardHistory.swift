import AppKit

/// Turns what was read off the pasteboard into items worth keeping.
enum ClipboardCapture {
    /// A single copy larger than this is skipped. A copied 4K screenshot as PNG
    /// is a few megabytes; far past that is a video frame or a disk image's
    /// worth of data nobody pastes back from a history.
    static let maxEntryBytes = 20 * 1024 * 1024

    /// Decided on the type list alone, before any content is read, so a
    /// concealed password never leaves the pasteboard at all.
    static func isPrivate(_ types: [String]) -> Bool {
        !ClipboardType.privateMarkers.isDisjoint(with: types)
    }

    /// Keeps the allowed representations of each item and drops what adds
    /// bulk without adding a way to paste. Nil when nothing is left, or when
    /// what is left is too large to keep.
    static func normalise(_ raw: [[String: Data]]) -> [ClipboardItem]? {
        let items = raw.compactMap(normalise(item:))
        guard !items.isEmpty else { return nil }
        guard items.reduce(0, { $0 + $1.byteCount }) <= maxEntryBytes else { return nil }
        return items
    }

    private static func normalise(item raw: [String: Data]) -> ClipboardItem? {
        var kept = raw.filter { ClipboardType.kept.contains($0.key) && !$0.value.isEmpty }

        // Finder adds the file's icon as TIFF beside its URL. Pasting a file
        // needs the URL; the icon would be most of the entry's size.
        if kept[ClipboardType.fileURL] != nil {
            kept = kept.filter { $0.key == ClipboardType.fileURL || $0.key == ClipboardType.plainText }
        }

        // One image is enough, and PNG is the smaller: a screenshot copied as
        // TIFF is several times its PNG. Apps that read only TIFF still get an
        // image, because AppKit converts between the two on paste.
        if let tiff = kept.removeValue(forKey: ClipboardType.tiff), kept[ClipboardType.png] == nil,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            kept[ClipboardType.png] = png
        }

        return kept.isEmpty ? nil : ClipboardItem(representations: kept)
    }
}

/// The list of copies, newest first, and the rules that bound it.
///
/// A value type with no pasteboard or disk in it, so every rule is testable
/// on its own; `ClipboardMonitor` feeds it and `ClipboardStore` keeps it.
struct ClipboardHistory: Equatable {
    static let defaultLimit = 50
    static let limitChoices = [25, 50, 100, 200]
    /// A ceiling on disk use whatever the entry limit, since fifty screenshots
    /// can weigh more than a thousand snippets.
    static let maxTotalBytes = 250 * 1024 * 1024

    private(set) var entries: [ClipboardEntry] = []
    var limit: Int = defaultLimit {
        didSet { trim() }
    }

    init(entries: [ClipboardEntry] = [], limit: Int = defaultLimit) {
        self.entries = entries
        self.limit = limit
        trim()
    }

    var totalBytes: Int { entries.reduce(0) { $0 + $1.byteCount } }

    /// Adds a copy at the top. A copy already in the history moves up rather
    /// than appearing twice, keeping its id so a row does not flicker out and
    /// back in.
    mutating func record(_ entry: ClipboardEntry) {
        if let index = entries.firstIndex(where: { $0.contentHash == entry.contentHash }) {
            var existing = entries.remove(at: index)
            existing.copiedAt = entry.copiedAt
            existing.sourceBundleID = entry.sourceBundleID ?? existing.sourceBundleID
            entries.insert(existing, at: 0)
        } else {
            entries.insert(entry, at: 0)
        }
        trim()
    }

    /// Picking an entry makes it the most recent copy, as it now is.
    mutating func promote(_ id: UUID, at date: Date) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries.remove(at: index)
        entry.copiedAt = date
        entries.insert(entry, at: 0)
    }

    mutating func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    mutating func clear() {
        entries.removeAll()
    }

    /// Oldest first, until both bounds hold. The newest entry always survives,
    /// even alone over the byte ceiling: it is what the user just copied.
    private mutating func trim() {
        if entries.count > limit {
            entries.removeLast(entries.count - max(limit, 1))
        }
        var bytes = totalBytes
        while bytes > Self.maxTotalBytes, entries.count > 1 {
            bytes -= entries.removeLast().byteCount
        }
    }
}
