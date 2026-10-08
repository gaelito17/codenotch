import SwiftUI
import XCTest
@testable import Codenotch

/// The screenshot cell is the last cell in the stack, after the clipboard's.
/// These pin that it is counted by the geometry, never mistaken for a
/// provider or the clipboard, and that a click on it folds the notch and
/// captures rather than refetching or pinning.
@MainActor
final class ScreenshotCellTests: XCTestCase {
    private func model(edge: NotchEdge = .right, cells: Int = 3, clipboard: Bool = false,
                       screenshot: Bool = true) -> NotchViewModel {
        let model = NotchViewModel()
        model.edge = edge
        model.isExpanded = true
        model.surfaceStyle = .solid
        model.snapshots = (0..<cells).map { index in
            ProviderSnapshot(
                id: "p\(index)", displayName: "P\(index)", glyph: .claude,
                fidelity: .official, status: .ok,
                windows: [LimitWindow(id: "w", label: "Session", usedFraction: 0.4)],
                headlineID: "w"
            )
        }
        model.showsClipboardCell = clipboard
        model.showsScreenshotCell = screenshot
        return model
    }

    // MARK: Geometry

    func testOffByDefaultAndCountsNothing() {
        let m = NotchViewModel()
        XCTAssertFalse(m.showsScreenshotCell)
        XCTAssertEqual(m.screenshotMode, .selection, "part of the screen, as ⇧⌘4, is the default")
        m.snapshots = model(screenshot: false).snapshots
        XCTAssertEqual(m.cellCount, 3)
        XCTAssertNil(m.screenshotIndex)
    }

    func testItIsTheLastCell() {
        let m = model()
        XCTAssertEqual(m.cellCount, 4)
        XCTAssertEqual(m.screenshotIndex, 3)
        XCTAssertNil(m.clipboardIndex)
    }

    func testItComesAfterTheClipboard() {
        let m = model(clipboard: true)
        XCTAssertEqual(m.cellCount, 5)
        XCTAssertEqual(m.clipboardIndex, 3)
        XCTAssertEqual(m.screenshotIndex, 4)
    }

    func testItSitsCloserToTheClipboardThanCellsDoToEachOther() {
        for edge in NotchEdge.allCases {
            let m = model(edge: edge, clipboard: true)
            XCTAssertGreaterThan(m.screenshotTuck, 0, "\(edge)")
            let providers = m.ringCenter(index: 1) - m.ringCenter(index: 0)
            let clipboard = m.ringCenter(index: m.clipboardIndex!) - m.ringCenter(index: m.snapshots.count - 1)
            let pair = m.ringCenter(index: m.screenshotIndex!) - m.ringCenter(index: m.clipboardIndex!)
            XCTAssertEqual(providers, m.cellPitch, accuracy: 0.001, "\(edge)")
            XCTAssertEqual(clipboard, m.cellPitch, accuracy: 0.001, "\(edge): the clipboard cell keeps its place")
            XCTAssertEqual(pair, m.cellPitch - m.screenshotTuck, accuracy: 0.001, "\(edge)")
            XCTAssertLessThan(m.ringCenter(index: m.screenshotIndex!), m.orbAlong, "\(edge)")
        }
    }

    func testTheShapeShrinksByTheTuck() {
        let m = model(clipboard: true)
        let untucked = NotchLayout.bodyLength(cellCount: m.cellCount, edge: m.edge,
                                              spacing: m.cellSpacing)
            + m.leadAllowance + m.endAllowance
        XCTAssertEqual(m.shapeLength, untucked - m.screenshotTuck, accuracy: 0.001)
    }

    func testNoTuckWithoutTheClipboard() {
        let m = model()
        XCTAssertEqual(m.screenshotTuck, 0)
        XCTAssertEqual(m.ringCenter(index: m.screenshotIndex!) - m.ringCenter(index: 2), m.cellPitch, accuracy: 0.001)
    }

    // MARK: Drawing

    private func render(_ model: NotchViewModel) -> NSBitmapImageRep? {
        let size = model.panelSize
        let renderer = ImageRenderer(
            content: NotchRootView(model: model)
                .frame(width: size.width, height: size.height)
                .environment(\.codenotchHeadlessGlass, true)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = 1
        return renderer.cgImage.map(NSBitmapImageRep.init(cgImage:))
    }

    /// Bright pixels within `half` of `centre` along the stack.
    private func brightPixels(in rep: NSBitmapImageRep, model m: NotchViewModel,
                              centre: CGFloat, half: CGFloat) -> Int {
        let place = NotchPlacement(edge: m.edge, panelSize: m.panelSize)
        var bright = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                let along = place.along(of: CGPoint(x: x, y: y))
                guard abs(along - centre) <= half,
                      let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                else { continue }
                if colour.alphaComponent > 0.5, colour.brightnessComponent > 0.6 { bright += 1 }
            }
        }
        return bright
    }

    func testTheTuckedGlyphIsDrawnWhereItsRingIsOnEveryEdge() {
        for edge in NotchEdge.allCases {
            let m = model(edge: edge, clipboard: true)
            guard let rep = render(m) else { XCTFail("\(edge): no image"); continue }
            let centre = m.ringAlong(index: m.screenshotIndex!, in: m.cellWing)
            let glyph = NotchLayout.glyphSize * m.sizeScale / 2
            XCTAssertGreaterThan(brightPixels(in: rep, model: m, centre: centre, half: glyph), 10,
                                 "\(edge): nothing drawn at the screenshot cell's centre")
            // Where it would have been untucked, past its glyph, is empty.
            let untucked = centre + m.screenshotTuck * m.sizeScale
            XCTAssertEqual(brightPixels(in: rep, model: m, centre: untucked + glyph, half: glyph / 3), 0,
                           "\(edge): the glyph is still drawn at its untucked place")
        }
    }

    func testHoveringItShowsNoTooltip() {
        let m = model()
        m.hoveredIndex = m.screenshotIndex
        XCTAssertNil(m.hoveredSnapshot)
    }

    // MARK: Clicks

    func testClickingItFoldsAndCapturesAndRefetchesNothing() throws {
        let controller = NotchWindowController()
        controller.show()
        defer { controller.stop() }

        let m = controller.model
        m.snapshots = model().snapshots
        m.showsClipboardCell = true
        m.showsScreenshotCell = true
        m.isExpanded = true
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let frame = try XCTUnwrap(controller.panelFrameForTesting)

        var refetched: [String] = []
        controller.onRefreshProvider = { refetched.append($0) }
        var finish: (() -> Void)?
        controller.onTakeScreenshot = { finish = $0 }

        let place = NotchPlacement(edge: m.edge, panelSize: frame.size)
        let along = m.ringAlong(index: m.screenshotIndex!, in: m.cellWing)
        XCTAssertEqual(controller.cellIndex(along: along), m.screenshotIndex)
        // Bands overlap where the pair is tucked together; each ring still
        // answers for its own half of the way between them.
        let clipboardAlong = m.slack + m.ringCenter(index: m.clipboardIndex!) * m.sizeScale
        XCTAssertEqual(controller.cellIndex(along: clipboardAlong), m.clipboardIndex)
        XCTAssertEqual(controller.cellIndex(along: along - (along - clipboardAlong) * 0.4), m.screenshotIndex)
        XCTAssertEqual(controller.cellIndex(along: along - (along - clipboardAlong) * 0.6), m.clipboardIndex)
        let local = place.point(along: along, across: m.notchDrawnDepth / 2)
        controller.handleClick(at: CGPoint(x: local.x, y: frame.height - local.y))

        XCTAssertFalse(m.isExpanded, "the notch folds out of the shot")
        XCTAssertFalse(m.isPinned)
        XCTAssertFalse(m.isClipboardOpen)
        XCTAssertTrue(controller.isCapturingScreenshot)
        XCTAssertNil(finish, "the capture waits for the fold")

        RunLoop.current.run(until: Date().addingTimeInterval(NotchWindowController.screenshotFoldPause + 0.1))
        XCTAssertNotNil(finish)
        XCTAssertTrue(refetched.isEmpty)

        finish?()
        XCTAssertFalse(controller.isCapturingScreenshot)
    }

    // MARK: Capture

    func testArgumentsMatchTheShortcuts() {
        let file = [URL(fileURLWithPath: "/tmp/a.png")]
        XCTAssertEqual(ScreenshotCapture.arguments(mode: .selection, destinations: file, type: "png"),
                       ["-i", "-t", "png", "/tmp/a.png"])
        XCTAssertEqual(ScreenshotCapture.arguments(mode: .window, destinations: file, type: "png"),
                       ["-i", "-W", "-t", "png", "/tmp/a.png"])
        XCTAssertEqual(ScreenshotCapture.arguments(mode: .fullScreen, destinations: file, type: "jpg"),
                       ["-t", "jpg", "/tmp/a.png"])
        XCTAssertEqual(ScreenshotCapture.arguments(mode: .selection, destinations: [], type: "png",
                                                   toClipboard: true),
                       ["-i", "-c"], "to the clipboard, and no file")
    }

    func testOneFilePerDisplayOnlyForTheWholeScreen() {
        let folder = URL(fileURLWithPath: "/tmp", isDirectory: true)
        var parts = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 24; parts.hour = 9; parts.minute = 5; parts.second = 7
        let date = Calendar.current.date(from: parts)!

        let one = ScreenshotCapture.destinations(mode: .selection, displays: 2, folder: folder, type: "png", date: date)
        XCTAssertEqual(one.map(\.lastPathComponent), ["Screenshot 2026-09-24 at 09.05.07.png"])

        let two = ScreenshotCapture.destinations(mode: .fullScreen, displays: 2, folder: folder, type: "png", date: date)
        XCTAssertEqual(two.map(\.lastPathComponent), [
            "Screenshot 2026-09-24 at 09.05.07 (1).png",
            "Screenshot 2026-09-24 at 09.05.07 (2).png",
        ])
    }

    func testItSavesWhereMacOSDoes() throws {
        let suite = "ScreenshotCellTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        XCTAssertEqual(ScreenshotCapture.destinationFolder(defaults: defaults), desktop)
        XCTAssertEqual(ScreenshotCapture.fileType(defaults: defaults), "png")

        let folder = FileManager.default.temporaryDirectory
        defaults.set(folder.path, forKey: "location")
        defaults.set("JPG", forKey: "type")
        XCTAssertEqual(ScreenshotCapture.destinationFolder(defaults: defaults).standardizedFileURL.path,
                       folder.standardizedFileURL.path)
        XCTAssertEqual(ScreenshotCapture.fileType(defaults: defaults), "jpg")

        defaults.set("/no/such/folder", forKey: "location")
        XCTAssertEqual(ScreenshotCapture.destinationFolder(defaults: defaults), desktop,
                       "a folder that has gone falls back to the Desktop")

        // A folder chosen in Settings wins over macOS' own, while it is there.
        let chosen = FileManager.default.temporaryDirectory.appendingPathComponent("shots-\(UUID())")
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: chosen) }
        defaults.set(folder.path, forKey: "location")
        XCTAssertEqual(ScreenshotCapture.destinationFolder(chosen: chosen.path, defaults: defaults)
                        .standardizedFileURL.path, chosen.standardizedFileURL.path)
        try FileManager.default.removeItem(at: chosen)
        XCTAssertEqual(ScreenshotCapture.destinationFolder(chosen: chosen.path, defaults: defaults)
                        .standardizedFileURL.path, folder.standardizedFileURL.path,
                       "a chosen folder that has gone falls back to macOS' own")
    }
}
