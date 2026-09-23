import SwiftUI
import XCTest
@testable import Codenotch

/// The history panel: when it is open, that it fits the notch's window on
/// every edge, that it draws every kind of copy, and that a row really does
/// take a click through AppKit into SwiftUI.
@MainActor
final class ClipboardPanelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func model(edge: NotchEdge = .right, cells: Int = 3) -> NotchViewModel {
        let model = NotchViewModel()
        model.edge = edge
        model.surfaceStyle = .solid
        model.snapshots = (0..<cells).map { index in
            ProviderSnapshot(
                id: "p\(index)", displayName: "P\(index)", glyph: .claude,
                fidelity: .official, status: .ok,
                windows: [LimitWindow(id: "w", label: "Session", usedFraction: 0.4)],
                headlineID: "w"
            )
        }
        model.showsClipboardCell = true
        model.isExpanded = true
        model.clipboardEntries = entries()
        model.now = now
        return model
    }

    private func entries() -> [ClipboardEntry] {
        func item(_ type: String, _ data: Data) -> ClipboardItem {
            ClipboardItem(representations: [type: data])
        }
        return [
            ClipboardEntry(items: [item(ClipboardType.plainText, Data("let answer = 42".utf8))],
                           copiedAt: now.addingTimeInterval(-20)),
            ClipboardEntry(items: [ClipboardItem(representations: [
                ClipboardType.plainText: Data("Bold move".utf8),
                ClipboardType.html: Data("<b>Bold move</b>".utf8),
            ])], copiedAt: now.addingTimeInterval(-300)),
            ClipboardEntry(items: [item(ClipboardType.png, Self.png())], copiedAt: now.addingTimeInterval(-900)),
            ClipboardEntry(items: [item(ClipboardType.fileURL, Data(URL(fileURLWithPath: "/etc/hosts").absoluteString.utf8))],
                           copiedAt: now.addingTimeInterval(-3600)),
            ClipboardEntry(items: [item(ClipboardType.fileURL, Data("file:///nowhere/gone.txt".utf8))],
                           copiedAt: now.addingTimeInterval(-7200)),
        ]
    }

    static func png() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 40,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let teal = NSColor(deviceRed: 0.1, green: 0.7, blue: 0.9, alpha: 1)
        for x in 0..<64 { for y in 0..<40 { rep.setColor(teal, atX: x, y: y) } }
        return rep.representation(using: .png, properties: [:])!
    }

    // MARK: State

    func testFoldingClosesIt() {
        let m = model()
        m.isClipboardOpen = true
        m.isExpanded = false
        XCTAssertFalse(m.isClipboardOpen)
    }

    func testSwitchingTheHistoryOffClosesIt() {
        let m = model()
        m.isClipboardOpen = true
        m.showsClipboardCell = false
        XCTAssertFalse(m.isClipboardOpen)
    }

    func testPickingHandsOverTheEntrySaysCopiedThenCloses() {
        let m = model()
        m.isClipboardOpen = true
        var picked: [UUID] = []
        m.onPickClipboardEntry = { picked.append($0.id) }

        let entry = m.clipboardEntries[2]
        m.pickClipboardEntry(entry)
        XCTAssertEqual(picked, [entry.id])
        XCTAssertEqual(m.clipboardCopiedID, entry.id)
        XCTAssertTrue(m.isClipboardOpen, "the row has to be seen saying Copied")

        RunLoop.current.run(until: Date().addingTimeInterval(NotchViewModel.clipboardCopiedPause + 0.1))
        XCTAssertFalse(m.isClipboardOpen)
        XCTAssertNil(m.clipboardCopiedID)
    }

    // MARK: Geometry

    func testTheWindowHoldsThePanelOnEveryEdgeAndSize() {
        for edge in NotchEdge.allCases {
            for size in NotchSize.allCases {
                for cells in [0, 1, 4] {
                    let m = model(edge: edge, cells: cells)
                    m.sizeScale = size.scale
                    let panel = m.panelSize
                    let length = edge.isVertical ? panel.height : panel.width
                    let depth = edge.isVertical ? panel.width : panel.height
                    let centre = try! XCTUnwrap(m.clipboardPanelCentreAlong)
                    let label = "\(edge) \(size.rawValue) \(cells) cells"

                    XCTAssertGreaterThanOrEqual(centre - m.clipboardPanelAlong / 2, -0.5, label)
                    XCTAssertLessThanOrEqual(centre + m.clipboardPanelAlong / 2, length + 0.5, label)
                    XCTAssertLessThanOrEqual(
                        m.notchDrawnDepth + NotchLayout.tailGap + NotchLayout.tailLength + m.clipboardPanelAcross,
                        depth + 0.5, label)
                }
            }
        }
    }

    func testTheWindowOnlyGrowsForItWhileTheCellIsThere() {
        let m = model(cells: 1)
        let with = m.maxCardHeight(cellCount: 2)
        m.showsClipboardCell = false
        XCTAssertGreaterThanOrEqual(with, NotchLayout.clipboardPanelHeight)
        XCTAssertLessThan(m.maxCardHeight(cellCount: 1), with)
    }

    // MARK: Drawing

    private func render(_ view: some View, size: CGSize) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: view
            .frame(width: size.width, height: size.height)
            .environment(\.codenotchHeadlessGlass, true)
            .environment(\.colorScheme, .dark))
        renderer.scale = 1
        return renderer.cgImage.map(NSBitmapImageRep.init(cgImage:))
    }

    private func inked(_ rep: NSBitmapImageRep, in rect: CGRect) -> Double {
        var inked = 0, total = 0
        for x in stride(from: Int(rect.minX), to: Int(rect.maxX), by: 2) {
            for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: 2) {
                total += 1
                if let colour = rep.colorAt(x: x, y: y), colour.alphaComponent > 0.5 { inked += 1 }
            }
        }
        return total == 0 ? 0 : Double(inked) / Double(total)
    }

    func testTheOpenPanelIsDrawnBesideTheNotchOnEveryEdge() {
        for edge in NotchEdge.allCases {
            let m = model(edge: edge)
            m.isClipboardOpen = true
            guard let rep = render(NotchRootView(model: m), size: m.panelSize) else {
                XCTFail("\(edge): no image"); continue
            }
            let place = NotchPlacement(edge: edge, panelSize: m.panelSize)
            let centre = m.clipboardPanelCentreAlong!
            let card = place.rect(
                along: centre - m.clipboardPanelAlong / 2 + NotchLayout.cardCorner,
                across: m.tooltipInset + NotchLayout.tailLength + NotchLayout.cardCorner,
                length: m.clipboardPanelAlong - 2 * NotchLayout.cardCorner,
                depth: m.clipboardPanelAcross - 2 * NotchLayout.cardCorner
            )
            XCTAssertGreaterThan(inked(rep, in: card), 0.95, "\(edge): the card is not where its hit region is")
        }
    }

    /// In the live window: `ImageRenderer` does not draw a scroll view's
    /// contents, so the list is only really there on screen.
    func testEveryKindOfRowRendersInTheLiveWindow() throws {
        let controller = NotchWindowController()
        controller.show()
        defer { controller.stop() }
        let m = controller.model
        m.surfaceStyle = .solid
        m.snapshots = model().snapshots
        m.showsClipboardCell = true
        m.clipboardEntries = entries()
        m.isExpanded = true
        m.isPinned = true
        pump()
        m.isClipboardOpen = true
        pump(0.5)

        for entry in m.clipboardEntries {
            XCTAssertNotNil(m.clipboardTargets.frames[.pick(entry.id)], "\(entry.kind) row was never laid out")
        }

        let view = try XCTUnwrap(controller.panelContentViewForTesting)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = try XCTUnwrap(m.clipboardTargets.frames[.pick(m.clipboardEntries[2].id)])
        var teal = 0
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        for x in stride(from: image.minX, to: image.midX, by: 1) {
            for y in stride(from: image.minY, to: image.maxY, by: 1) {
                if let c = rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.deviceRGB),
                   c.saturationComponent > 0.5, c.blueComponent > 0.6 { teal += 1 }
            }
        }
        XCTAssertGreaterThan(teal, 50, "the image row drew no thumbnail")
    }

    func testAnEmptyHistorySaysSo() throws {
        let size = CGSize(width: NotchLayout.cardWidth + NotchLayout.tailLength,
                          height: NotchLayout.clipboardPanelHeight)
        XCTAssertNotNil(render(ClipboardPanel(entries: [], direction: .leading, now: now), size: size))
    }

    // MARK: The real window

    private func pump(_ seconds: TimeInterval = 0.1) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Clicks go into the notch's own window as AppKit events, the way a
    /// hand's would — not through `handleClick` — so SwiftUI's gesture has to
    /// receive them in a window that never becomes key.
    func testARowTakesARealClick() throws {
        let controller = NotchWindowController()
        controller.show()
        defer { controller.stop() }
        let m = controller.model
        m.snapshots = model().snapshots
        m.showsClipboardCell = true
        m.clipboardEntries = entries()
        m.isExpanded = true
        m.isPinned = true
        pump()
        m.isClipboardOpen = true
        pump(0.4)

        var picked: [UUID] = []
        m.onPickClipboardEntry = { picked.append($0.id) }

        let content = try XCTUnwrap(controller.panelContentViewForTesting)
        let window = try XCTUnwrap(content.window)
        let place = NotchPlacement(edge: m.edge, panelSize: window.frame.size)
        let centre = try XCTUnwrap(m.clipboardPanelCentreAlong)
        // Just inside the first row: past the card's padding and the header.
        let firstRow = place.point(
            along: centre - m.clipboardPanelAlong / 2 + NotchLayout.cardPadding
                + (m.edge.isVertical ? Design.px(120) : NotchLayout.cardWidth / 2),
            across: m.tooltipInset + NotchLayout.tailLength + NotchLayout.cardWidth / 2
        )
        let inWindow = CGPoint(x: firstRow.x, y: window.frame.height - firstRow.y)

        // The controller lets the window take the mouse only while the real
        // pointer is over its chrome, and the test's pointer is wherever it
        // was left. This is the state a hand over the panel would have made.
        window.ignoresMouseEvents = false
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: inWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
        pump()

        XCTAssertEqual(picked, [m.clipboardEntries[0].id])
        XCTAssertTrue(m.isClipboardOpen, "a click inside the panel must not put it away")

        // The remove button and Clear, found where the panel says it laid
        // them out, and clicked the same way.
        var removed: [UUID] = []
        var cleared = 0
        m.onRemoveClipboardEntry = { removed.append($0) }
        m.onClearClipboard = { cleared += 1 }
        func click(_ target: ClipboardHitTargets.Target) throws {
            let frame = try XCTUnwrap(m.clipboardTargets.frames[target], "\(target) was never laid out")
            let point = CGPoint(x: frame.midX, y: window.frame.height - frame.midY)
            window.ignoresMouseEvents = false
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
            }
            pump()
        }
        let second = m.clipboardEntries[1].id
        try click(.remove(second))
        XCTAssertEqual(removed, [second])
        XCTAssertEqual(picked.count, 1, "the remove button sits inside its row and must not also pick it")
        try click(.clear)
        XCTAssertEqual(cleared, 1)

        // The missing file cannot be picked.
        try click(.pick(m.clipboardEntries[4].id))
        XCTAssertEqual(picked.count, 1)
    }

    func testARowScrolledOutOfViewIsNotHit() {
        let targets = ClipboardHitTargets()
        let row = UUID()
        targets.viewport = CGRect(x: 0, y: 100, width: 200, height: 300)
        targets.set(.pick(row), CGRect(x: 0, y: 40, width: 200, height: 40))
        XCTAssertNil(targets.target(at: CGPoint(x: 50, y: 60)))
        targets.set(.pick(row), CGRect(x: 0, y: 140, width: 200, height: 40))
        XCTAssertEqual(targets.target(at: CGPoint(x: 50, y: 160)), .pick(row))
    }
}
