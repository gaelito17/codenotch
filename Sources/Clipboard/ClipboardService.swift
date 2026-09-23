import AppKit
import Combine

/// The clipboard history as the app runs it: capture, the list, and disk.
///
/// Off until switched on, and switching off keeps nothing — polling stops and
/// the folder on disk is deleted.
@MainActor
final class ClipboardService: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var isEnabled = false
    /// What macOS has been told to do when Codenotch reads the pasteboard.
    @Published private(set) var access: Access = .notAsked

    enum Access: Equatable {
        /// No alert yet: the first capture will raise one.
        case notAsked
        case ask
        case allowed
        case denied
    }

    private var history = ClipboardHistory()
    private let monitor: ClipboardMonitor
    private let store: ClipboardStore
    private let pasteboard: NSPasteboard
    private let now: () -> Date
    /// One queue for every write and the delete, so they land in the order
    /// they were asked for: a save still in flight can never recreate the
    /// folder that switching off has just removed.
    private let disk = DispatchQueue(label: "com.vinz.codenotch.clipboard-store", qos: .utility)
    private var pendingSave: DispatchWorkItem?

    /// Coalesces a burst of copies into one write.
    static let saveDelay: TimeInterval = 0.4

    init(store: ClipboardStore = ClipboardStore(),
         pasteboard: NSPasteboard = .general,
         now: @escaping () -> Date = Date.init,
         frontmostBundleID: @escaping () -> String? = {
             NSWorkspace.shared.frontmostApplication?.bundleIdentifier
         }) {
        self.store = store
        self.pasteboard = pasteboard
        self.now = now
        self.monitor = ClipboardMonitor(pasteboard: pasteboard, now: now,
                                        frontmostBundleID: frontmostBundleID)
        monitor.onCapture = { [weak self] entry in
            MainActor.assumeIsolated { self?.capture(entry) }
        }
    }

    // MARK: Switching

    func setEnabled(_ enabled: Bool, limit: Int) {
        guard enabled != isEnabled else { return setLimit(limit) }
        isEnabled = enabled
        if enabled {
            history = store.load()
            history.limit = limit
            publish()
            monitor.start()
        } else {
            monitor.stop()
            pendingSave?.cancel()
            pendingSave = nil
            history.clear()
            publish()
            disk.async { [store] in
                do { try store.destroy() } catch { Log.clipboard.error("Could not delete the history: \(error.localizedDescription, privacy: .public)") }
            }
        }
        refreshAccess()
    }

    func setLimit(_ limit: Int) {
        guard history.limit != limit else { return }
        history.limit = limit
        changed()
    }

    // MARK: Actions

    func pick(_ entry: ClipboardEntry) {
        monitor.write(entry)
        history.promote(entry.id, at: now())
        changed()
    }

    func remove(_ id: UUID) {
        history.remove(id)
        changed()
    }

    func clear() {
        history.clear()
        changed()
    }

    /// Re-read on demand — when Settings comes forward — since the user
    /// changes it in System Settings and nothing tells us.
    func refreshAccess() {
        guard #available(macOS 15.4, *) else { return access = .allowed }
        switch pasteboard.accessBehavior {
        case .default:     access = .notAsked
        case .ask:         access = .ask
        case .alwaysAllow: access = .allowed
        case .alwaysDeny:  access = .denied
        @unknown default:  access = .ask
        }
    }

    /// Where the user changes that answer.
    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Pasteboard")!

    /// Waits for pending writes; tests only.
    func flushForTesting() {
        pendingSave?.perform()
        pendingSave = nil
        disk.sync {}
    }

    // MARK: Private

    private func capture(_ entry: ClipboardEntry) {
        guard isEnabled else { return }
        history.record(entry)
        changed()
    }

    private func changed() {
        publish()
        scheduleSave()
    }

    private func publish() {
        if entries != history.entries { entries = history.entries }
    }

    private func scheduleSave() {
        guard isEnabled else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isEnabled else { return }
                self.pendingSave = nil
                let snapshot = self.history
                self.disk.async { [store = self.store] in
                    do { try store.save(snapshot) } catch {
                        Log.clipboard.error("Could not save the history: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }
}
