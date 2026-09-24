import AppKit

/// What the screenshot cell captures, one per macOS shortcut it stands in for.
enum ScreenshotMode: String, CaseIterable, Identifiable {
    /// ⇧⌘4: drag out a part of the screen. Space still switches to a window,
    /// and Escape still cancels, because it is the system's own crosshair.
    case selection
    /// ⇧⌘4 then Space: click a window.
    case window
    /// ⇧⌘3: every display, one file each.
    case fullScreen

    var id: String { rawValue }

    static let `default`: ScreenshotMode = .selection

    var title: String {
        switch self {
        case .selection:  return L10n.t("Part of the screen")
        case .window:     return L10n.t("A window")
        case .fullScreen: return L10n.t("The whole screen")
        }
    }

    /// The keys macOS gives the same capture, shown beside the choice.
    var shortcut: String {
        switch self {
        case .selection:  return "⇧⌘4"
        case .window:     return "⇧⌘4 Space"
        case .fullScreen: return "⇧⌘3"
        }
    }

    /// The cell's glyph, so the notch says what a click will do.
    var symbol: String {
        switch self {
        case .selection:  return "rectangle.dashed"
        case .window:     return "macwindow"
        case .fullScreen: return "display"
        }
    }
}

/// Takes a screenshot with macOS' own `screencapture`, so the crosshair, the
/// window picker, the shutter sound and Escape are all the system's, and the
/// file lands where the system's shortcuts would have put it.
enum ScreenshotCapture {
    static let tool = URL(fileURLWithPath: "/usr/sbin/screencapture")

    /// Where a capture is saved: the folder chosen in Settings › Screenshot,
    /// otherwise the one macOS' own shortcuts save to — whatever Screenshot.app
    /// last stored as its location — otherwise the Desktop. A chosen folder
    /// that has since gone is passed over rather than failing the capture.
    static func destinationFolder(
        chosen: String? = nil,
        defaults: UserDefaults? = UserDefaults(suiteName: "com.apple.screencapture"),
        fileManager: FileManager = .default
    ) -> URL {
        for path in [chosen, defaults?.string(forKey: "location")] {
            if let folder = existingFolder(path, fileManager: fileManager) { return folder }
        }
        return fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    private static func existingFolder(_ path: String?, fileManager: FileManager) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return url
    }

    /// The format macOS has been set to save in; PNG unless told otherwise.
    static func fileType(defaults: UserDefaults? = UserDefaults(suiteName: "com.apple.screencapture")) -> String {
        let known = ["png", "jpg", "jpeg", "heic", "tiff", "gif", "pdf", "bmp"]
        guard let type = defaults?.string(forKey: "type")?.lowercased(), known.contains(type) else { return "png" }
        return type
    }

    /// One file per display for a full-screen capture, as ⇧⌘3 makes; one
    /// otherwise. Named the way the system names its own.
    static func destinations(mode: ScreenshotMode, displays: Int, folder: URL,
                             type: String, date: Date = Date()) -> [URL] {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "HH.mm.ss"
        let base = L10n.t("Screenshot \(day.string(from: date)) at \(time.string(from: date))")

        let count = mode == .fullScreen ? max(1, displays) : 1
        return (1...count).map { display in
            let name = count == 1 ? base : "\(base) (\(display))"
            return folder.appendingPathComponent(name).appendingPathExtension(type)
        }
    }

    /// With `toClipboard`, the capture goes to the clipboard, as ⌃ added to
    /// the shortcut does, and no file is written.
    static func arguments(mode: ScreenshotMode, destinations: [URL], type: String,
                          toClipboard: Bool = false) -> [String] {
        var arguments: [String]
        switch mode {
        case .selection:  arguments = ["-i"]
        case .window:     arguments = ["-i", "-W"]
        case .fullScreen: arguments = []
        }
        if toClipboard { return arguments + ["-c"] }
        arguments += ["-t", type]
        return arguments + destinations.map(\.path)
    }

    /// Runs the capture and calls back on the main queue once it is over —
    /// taken, or cancelled with Escape — with the files it left behind, none
    /// when it went to the clipboard.
    static func capture(mode: ScreenshotMode, folder chosen: String? = nil, toClipboard: Bool = false,
                        completion: @escaping ([URL]) -> Void) {
        let type = fileType()
        let destinations = toClipboard ? [] : destinations(mode: mode, displays: NSScreen.screens.count,
                                                           folder: destinationFolder(chosen: chosen), type: type)
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments(mode: mode, destinations: destinations, type: type,
                                      toClipboard: toClipboard)
        process.terminationHandler = { _ in
            let saved = destinations.filter { FileManager.default.fileExists(atPath: $0.path) }
            DispatchQueue.main.async { completion(saved) }
        }
        do {
            try process.run()
        } catch {
            Log.screenshot.error("screencapture did not start: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async { completion([]) }
        }
    }
}
