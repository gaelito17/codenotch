import SwiftUI
import XCTest
@testable import Codenotch

/// The clipboard cell is one more cell at the foot of the stack. These pin that
/// it is counted by the geometry, never mistaken for a provider, and drawn
/// where the hover bands and clicks expect it on every edge.
@MainActor
final class ClipboardCellTests: XCTestCase {
    private func model(edge: NotchEdge = .right, cells: Int = 3, clipboard: Bool = true) -> NotchViewModel {
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
        return model
    }

    // MARK: Geometry

    func testOffByDefaultAndCountsNothing() {
        let m = NotchViewModel()
        XCTAssertFalse(m.showsClipboardCell)
        m.snapshots = model(clipboard: false).snapshots
        XCTAssertEqual(m.cellCount, 3)
        XCTAssertNil(m.clipboardIndex)
    }

    func testItIsTheLastCell() {
        let m = model()
        XCTAssertEqual(m.cellCount, 4)
        XCTAssertEqual(m.clipboardIndex, 3)
        XCTAssertFalse(m.snapshots.indices.contains(m.clipboardIndex!),
                       "the clipboard index must fall outside the providers, or it would be read as one")
    }

    func testItIsTheLastCellWithNoProvidersAtAll() {
        let m = model(cells: 0)
        XCTAssertEqual(m.clipboardIndex, 0)
        XCTAssertEqual(m.cellCount, 1)
    }

    func testTheShapeAndPanelMakeRoomForIt() {
        for edge in NotchEdge.allCases {
            let without = model(edge: edge, clipboard: false)
            let with = model(edge: edge)
            XCTAssertEqual(with.shapeLength, without.shapeLength(cellCount: 4), accuracy: 0.001, "\(edge)")
            XCTAssertGreaterThan(with.shapeLength, without.shapeLength, "\(edge)")
            // At least a fourth cell's worth, and more where the history
            // panel is taller than any tooltip.
            XCTAssertGreaterThanOrEqual(with.panelSize.width, without.panelSize(cellCount: 4).width, "\(edge)")
            XCTAssertGreaterThanOrEqual(with.panelSize.height, without.panelSize(cellCount: 4).height, "\(edge)")
        }
    }

    func testItSitsAfterTheLastProviderAndBeforeTheSettingsOrb() {
        for edge in NotchEdge.allCases {
            let m = model(edge: edge)
            let last = m.ringCenter(index: m.snapshots.count - 1)
            let clipboard = m.ringCenter(index: m.clipboardIndex!)
            XCTAssertEqual(clipboard - last, m.cellPitch, accuracy: 0.001, "\(edge)")
            XCTAssertLessThan(clipboard, m.orbAlong, "\(edge)")
        }
    }

    func testHoveringItShowsNoTooltip() {
        let m = model()
        m.hoveredIndex = m.clipboardIndex
        XCTAssertNil(m.hoveredSnapshot)
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

    /// Bright pixels in the band along the stack that the clipboard cell's
    /// glyph should occupy, across the whole depth. The glyph is white on the
    /// notch's black; the track and the resting orb arc are far dimmer, and
    /// the cell has no reading text, so an empty band counts none.
    private func brightPixels(in rep: NSBitmapImageRep, model m: NotchViewModel, index: Int) -> Int {
        let place = NotchPlacement(edge: m.edge, panelSize: m.panelSize)
        let centre = m.ringAlong(index: index, in: m.cellWing)
        let half = NotchLayout.glyphSize * m.sizeScale / 2
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

    func testTheGlyphIsDrawnWhereItsBandIsOnEveryEdge() {
        for edge in NotchEdge.allCases {
            let with = model(edge: edge)
            let without = model(edge: edge, clipboard: false)
            guard let shown = render(with), let hidden = render(without) else {
                XCTFail("\(edge): no image"); continue
            }
            let index = with.clipboardIndex!
            XCTAssertGreaterThan(brightPixels(in: shown, model: with, index: index), 10,
                                 "\(edge): nothing drawn at the clipboard cell's centre")
            XCTAssertEqual(brightPixels(in: hidden, model: without, index: index), 0,
                           "\(edge): the probe finds something even with no clipboard cell")
        }
    }

    // MARK: Clicks

    func testClickingItAsksForTheHistoryAndRefetchesNothing() throws {
        let controller = NotchWindowController()
        controller.show()
        defer { controller.stop() }

        let m = controller.model
        m.snapshots = model().snapshots
        m.showsClipboardCell = true
        m.isExpanded = true
        // The resize on a new cell count is deferred a run-loop turn.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let frame = try XCTUnwrap(controller.panelFrameForTesting)
        // AppKit rounds the frame to whole points.
        XCTAssertEqual(frame.height, m.panelSize.height, accuracy: 1, "the panel was not resized for the new cell")

        var refetched: [String] = []
        controller.onRefreshProvider = { refetched.append($0) }

        let place = NotchPlacement(edge: m.edge, panelSize: frame.size)
        func click(cell index: Int) {
            let along = m.ringAlong(index: index, in: m.cellWing)
            let local = place.point(along: along, across: m.notchDrawnDepth / 2)
            XCTAssertEqual(controller.cellIndex(along: along), index)
            controller.handleClick(at: CGPoint(x: local.x, y: frame.height - local.y))
        }

        click(cell: m.clipboardIndex!)
        XCTAssertTrue(m.isClipboardOpen)
        XCTAssertFalse(m.isPinned, "a click on the clipboard cell must not also pin the notch")
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(refetched.isEmpty)

        // With the history open, a click on a ring only puts it away.
        click(cell: 0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(m.isClipboardOpen)
        XCTAssertTrue(refetched.isEmpty)

        click(cell: 0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(refetched.count, 1, "a provider cell still refetches")
    }
}
