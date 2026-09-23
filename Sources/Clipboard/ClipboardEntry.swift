import AppKit
import CryptoKit

/// One pasteboard item as it was copied: each kept representation, keyed by its
/// uniform type identifier.
///
/// A copy can carry several items — four files from Finder are four items — and
/// each item several representations of the same thing (plain text beside RTF
/// beside HTML). Both levels are kept so that picking the entry later puts back
/// what the source app offered, and the app it is pasted into can still choose.
struct ClipboardItem: Equatable {
    var representations: [String: Data]

    var byteCount: Int { representations.values.reduce(0) { $0 + $1.count } }
}

/// One clipboard copy, as the history keeps it.
struct ClipboardEntry: Identifiable, Equatable {
    let id: UUID
    var items: [ClipboardItem]
    /// When it was last copied. A repeat copy moves the entry to the top, so
    /// this is the most recent time, not the first.
    var copiedAt: Date
    /// The frontmost app when the copy was seen. A guess, not a fact: the
    /// pasteboard does not record its writer, and a background app can copy.
    var sourceBundleID: String?
    /// Identifies the content for deduplication, independent of `id`.
    let contentHash: String

    init(id: UUID = UUID(), items: [ClipboardItem], copiedAt: Date, sourceBundleID: String? = nil) {
        self.id = id
        self.items = items
        self.copiedAt = copiedAt
        self.sourceBundleID = sourceBundleID
        self.contentHash = Self.hash(items)
    }

    var byteCount: Int { items.reduce(0) { $0 + $1.byteCount } }

    enum Kind: Equatable {
        case files
        case image
        case richText
        case text
    }

    /// What the row shows. Files outrank everything because Finder puts each
    /// file's name beside its URL, and a list of names is not what was copied.
    var kind: Kind {
        let types = Set(items.flatMap(\.representations.keys))
        if types.contains(ClipboardType.fileURL) { return .files }
        if types.contains(ClipboardType.png) { return .image }
        if !types.isDisjoint(with: ClipboardType.rich) { return .richText }
        return .text
    }

    /// The text a row previews, whatever the richest form was.
    var plainText: String? {
        for item in items {
            if let data = item.representations[ClipboardType.plainText],
               let text = String(data: data, encoding: .utf8) {
                return text
            }
            if let data = item.representations[ClipboardType.rtf],
               let text = NSAttributedString(rtf: data, documentAttributes: nil)?.string {
                return text
            }
            if let data = item.representations[ClipboardType.url],
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }
        return nil
    }

    var fileURLs: [URL] {
        items.compactMap { item in
            item.representations[ClipboardType.fileURL]
                .flatMap { String(data: $0, encoding: .utf8) }
                .flatMap(URL.init(string:))
        }
    }

    var imageData: Data? {
        items.lazy.compactMap { $0.representations[ClipboardType.png] }.first
    }

    /// SHA-256 over every item's representations in a fixed order. Types are
    /// part of the digest so the same bytes as text and as HTML stay distinct.
    static func hash(_ items: [ClipboardItem]) -> String {
        var hasher = SHA256()
        for item in items {
            for type in item.representations.keys.sorted() {
                hasher.update(data: Data(type.utf8))
                hasher.update(data: Data([0]))
                hasher.update(data: item.representations[type]!)
                hasher.update(data: Data([0]))
            }
            hasher.update(data: Data([1]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// The pasteboard types the history reads or refuses.
enum ClipboardType {
    static let plainText = NSPasteboard.PasteboardType.string.rawValue   // public.utf8-plain-text
    static let url = NSPasteboard.PasteboardType.URL.rawValue            // public.url
    static let fileURL = NSPasteboard.PasteboardType.fileURL.rawValue    // public.file-url
    static let rtf = NSPasteboard.PasteboardType.rtf.rawValue            // public.rtf
    static let rtfd = NSPasteboard.PasteboardType.rtfd.rawValue          // com.apple.flat-rtfd
    static let html = NSPasteboard.PasteboardType.html.rawValue          // public.html
    static let png = NSPasteboard.PasteboardType.png.rawValue            // public.png
    static let tiff = NSPasteboard.PasteboardType.tiff.rawValue          // public.tiff

    static let rich: Set<String> = [rtf, rtfd, html]

    /// Everything else a copy carries is dropped rather than stored opaquely:
    /// an app's private type can be large, and nothing but that app can paste it.
    static let kept: [String] = [plainText, url, fileURL, rtf, rtfd, html, png, tiff]

    /// The nspasteboard.org convention. Password managers mark a copied secret
    /// concealed, and apps mark clipboard traffic nobody asked for — a
    /// drag-and-drop helper, a clipboard-driven automation — as transient or
    /// auto-generated. None of it belongs in a history.
    static let privateMarkers: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
    ]
}
