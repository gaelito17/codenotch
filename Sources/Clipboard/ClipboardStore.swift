import Foundation

/// Keeps the history on disk across quits.
///
/// Layout, under a directory only the user can read:
///
///     history.json                       order and metadata, no content
///     items/<entry id>/<item>/<type>     one file per representation
///
/// Content lives beside the index rather than inside it so a history full of
/// screenshots is not base64-encoded into one JSON file and rewritten whole on
/// every copy: a save writes the blobs of new entries and deletes the folders
/// of evicted ones, and leaves the rest alone.
struct ClipboardStore {
    let directory: URL

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Codenotch", isDirectory: true)
            .appendingPathComponent("Clipboard", isDirectory: true)
    }

    init(directory: URL = Self.defaultDirectory) {
        self.directory = directory
    }

    private var indexURL: URL { directory.appendingPathComponent("history.json") }
    private var itemsURL: URL { directory.appendingPathComponent("items", isDirectory: true) }

    private struct Index: Codable {
        var version = 1
        var limit: Int
        var entries: [Record]
    }

    private struct Record: Codable {
        var id: UUID
        var copiedAt: Date
        var sourceBundleID: String?
        /// Each item's types, in item order. The content is on disk under them.
        var items: [[String]]
    }

    /// An entry whose files have gone missing is dropped rather than restored
    /// half-empty; a history that cannot be read at all starts over.
    func load() -> ClipboardHistory {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(Index.self, from: data)
        else { return ClipboardHistory() }

        let entries = index.entries.compactMap { record -> ClipboardEntry? in
            var items: [ClipboardItem] = []
            for (position, types) in record.items.enumerated() {
                var representations: [String: Data] = [:]
                for type in types {
                    guard let content = try? Data(contentsOf: blobURL(record.id, position, type))
                    else { return nil }
                    representations[type] = content
                }
                items.append(ClipboardItem(representations: representations))
            }
            return ClipboardEntry(id: record.id, items: items, copiedAt: record.copiedAt,
                                  sourceBundleID: record.sourceBundleID)
        }
        return ClipboardHistory(entries: entries, limit: index.limit)
    }

    func save(_ history: ClipboardHistory) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: itemsURL, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        // Created with the right mode only when it did not exist; enforced
        // every time in case an older copy was made more permissive.
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let current = Set(history.entries.map(\.id.uuidString))
        for existing in (try? fm.contentsOfDirectory(atPath: itemsURL.path)) ?? []
        where !current.contains(existing) {
            try? fm.removeItem(at: itemsURL.appendingPathComponent(existing))
        }

        for entry in history.entries {
            let folder = itemsURL.appendingPathComponent(entry.id.uuidString, isDirectory: true)
            // Content never changes under an id, so a folder that is there is done.
            guard !fm.fileExists(atPath: folder.path) else { continue }
            for (position, item) in entry.items.enumerated() {
                for (type, content) in item.representations {
                    let url = blobURL(entry.id, position, type)
                    try fm.createDirectory(at: url.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
                    try content.write(to: url, options: .atomic)
                }
            }
        }

        let index = Index(limit: history.limit, entries: history.entries.map { entry in
            Record(id: entry.id, copiedAt: entry.copiedAt, sourceBundleID: entry.sourceBundleID,
                   items: entry.items.map { $0.representations.keys.sorted() })
        })
        try JSONEncoder().encode(index).write(to: indexURL, options: .atomic)
    }

    /// Switching the feature off keeps nothing.
    func destroy() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    private func blobURL(_ id: UUID, _ position: Int, _ type: String) -> URL {
        itemsURL
            .appendingPathComponent(id.uuidString, isDirectory: true)
            .appendingPathComponent(String(position), isDirectory: true)
            // A UTI is dots and letters, but a stored index is still input.
            .appendingPathComponent(type.replacingOccurrences(of: "/", with: "_"))
    }
}
