import AppKit
import XCTest
@testable import Codenotch

/// The history as the app runs it — against a private pasteboard and a
/// temporary folder, never the real ones.
@MainActor
final class ClipboardServiceTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var directory: URL!
    private var store: ClipboardStore { ClipboardStore(directory: directory) }

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard.withUniqueName()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardServiceTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func service() -> ClipboardService {
        ClipboardService(store: store, pasteboard: pasteboard, frontmostBundleID: { "com.example.editor" })
    }

    private func copy(_ string: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// Long enough for the monitor's timer to have fired at least once.
    private func waitForPoll() {
        RunLoop.current.run(until: Date().addingTimeInterval(ClipboardMonitor.pollInterval * 1.6))
    }

    func testOffRecordsNothing() {
        let clipboard = service()
        copy("secret-ish")
        waitForPoll()
        XCTAssertFalse(clipboard.isEnabled)
        XCTAssertTrue(clipboard.entries.isEmpty)
    }

    func testOnRecordsNewCopiesOnly() {
        copy("before it was switched on")
        let clipboard = service()
        clipboard.setEnabled(true, limit: 50)
        waitForPoll()
        XCTAssertTrue(clipboard.entries.isEmpty)

        copy("hello")
        waitForPoll()
        XCTAssertEqual(clipboard.entries.map(\.plainText), ["hello"])
        XCTAssertEqual(clipboard.entries.first?.sourceBundleID, "com.example.editor")
    }

    func testTheHistoryOutlivesAQuit() {
        let first = service()
        first.setEnabled(true, limit: 50)
        copy("one")
        waitForPoll()
        copy("two")
        waitForPoll()
        first.flushForTesting()

        let second = service()
        second.setEnabled(true, limit: 50)
        second.flushForTesting()
        XCTAssertEqual(second.entries.map(\.plainText), ["two", "one"])
    }

    func testSwitchingOffForgetsAndDeletes() {
        let clipboard = service()
        clipboard.setEnabled(true, limit: 50)
        copy("one")
        waitForPoll()
        clipboard.flushForTesting()
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))

        clipboard.setEnabled(false, limit: 50)
        clipboard.flushForTesting()
        XCTAssertTrue(clipboard.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))

        copy("after")
        waitForPoll()
        XCTAssertTrue(clipboard.entries.isEmpty, "switched off, it must stop polling too")
    }

    func testPickingPutsItBackMovesItUpAndIsNotRecorded() {
        let clipboard = service()
        clipboard.setEnabled(true, limit: 50)
        copy("old")
        waitForPoll()
        copy("new")
        waitForPoll()

        let old = clipboard.entries[1]
        clipboard.pick(old)
        waitForPoll()

        XCTAssertEqual(pasteboard.string(forType: .string), "old")
        XCTAssertEqual(clipboard.entries.map(\.plainText), ["old", "new"])
        XCTAssertEqual(clipboard.entries[0].id, old.id)
    }

    func testALoadThatFinishesAfterSwitchingOffIsDropped() {
        let first = service()
        first.setEnabled(true, limit: 50)
        waitForPoll()
        copy("kept on disk")
        waitForPoll()
        first.flushForTesting()

        let second = service()
        second.setEnabled(true, limit: 50)
        second.setEnabled(false, limit: 50)
        second.flushForTesting()
        XCTAssertTrue(second.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testCopiesMadeWhileLoadingGoOnTopAndNothingIsLost() {
        let first = service()
        first.setEnabled(true, limit: 50)
        first.flushForTesting()
        copy("from last time")
        waitForPoll()
        first.flushForTesting()

        let second = service()
        second.setEnabled(true, limit: 50)
        // Before the load has come back.
        copy("while loading")
        RunLoop.current.run(until: Date().addingTimeInterval(ClipboardMonitor.pollInterval * 1.6))
        second.flushForTesting()
        XCTAssertEqual(second.entries.map(\.plainText), ["while loading", "from last time"])
        second.flushForTesting()
        XCTAssertEqual(store.load().entries.map(\.plainText), ["while loading", "from last time"])
    }

    func testRemoveClearAndLimitAreKept() {
        let clipboard = service()
        clipboard.setEnabled(true, limit: 50)
        for word in ["a", "b", "c"] {
            copy(word)
            waitForPoll()
        }
        clipboard.remove(clipboard.entries[1].id)
        XCTAssertEqual(clipboard.entries.map(\.plainText), ["c", "a"])

        clipboard.setEnabled(true, limit: 25)
        clipboard.flushForTesting()
        XCTAssertEqual(store.load().limit, 25)
        XCTAssertEqual(store.load().entries.map(\.plainText), ["c", "a"])

        clipboard.clear()
        clipboard.flushForTesting()
        XCTAssertTrue(clipboard.entries.isEmpty)
        XCTAssertTrue(store.load().entries.isEmpty)
    }

    // MARK: Preferences

    private func defaults() -> UserDefaults {
        let name = "ClipboardServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testThePreferenceIsOffByDefault() {
        let preferences = Preferences(defaults: defaults())
        XCTAssertFalse(preferences.clipboardHistoryEnabled)
        XCTAssertEqual(preferences.clipboardHistoryLimit, ClipboardHistory.defaultLimit)
    }

    func testThePreferenceIsKeptAndAStrangeLimitIsIgnored() {
        let store = defaults()
        let preferences = Preferences(defaults: store)
        preferences.clipboardHistoryEnabled = true
        preferences.clipboardHistoryLimit = 100
        XCTAssertTrue(Preferences(defaults: store).clipboardHistoryEnabled)
        XCTAssertEqual(Preferences(defaults: store).clipboardHistoryLimit, 100)

        store.set(7, forKey: "clipboardHistoryLimit")
        XCTAssertEqual(Preferences(defaults: store).clipboardHistoryLimit, ClipboardHistory.defaultLimit)
    }

    // MARK: Fleet

    func testTheFleetHandsTheHistoryToEveryNotchIncludingLateOnes() throws {
        let entries = Fixtures.clipboardEntries()
        let fleet = NotchFleet(scope: .mainDisplay, edge: .right)
        var picked: [UUID] = []
        fleet.onPickClipboardEntry = { picked.append($0.id) }
        // Set before the first controller exists, as the app does.
        fleet.setClipboard(shown: true, entries: entries)
        fleet.show()
        defer { fleet.stop() }

        let controller = try XCTUnwrap(fleet.controllersForTesting.first)
        XCTAssertTrue(controller.model.showsClipboardCell)
        XCTAssertEqual(controller.model.clipboardEntries, entries)
        controller.model.onPickClipboardEntry?(entries[0])
        XCTAssertEqual(picked, [entries[0].id])

        fleet.setClipboard(shown: false, entries: [])
        XCTAssertFalse(controller.model.showsClipboardCell)
        XCTAssertTrue(controller.model.clipboardEntries.isEmpty)
    }

    func testTheDemoHistoryHasOneOfEachKind() {
        let kinds = Fixtures.clipboardEntries().map(\.kind)
        XCTAssertTrue(kinds.contains(.text))
        XCTAssertTrue(kinds.contains(.richText))
        XCTAssertTrue(kinds.contains(.image))
        XCTAssertTrue(kinds.contains(.files))
    }
}
