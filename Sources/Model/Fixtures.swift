import AppKit

/// The three providers from the design frame, at the levels it shows.
/// These stand in until the adapters in M4 land.
enum Fixtures {
    static func snapshots(now: Date = Date(), calendar: Calendar = .current) -> [ProviderSnapshot] {
        let sessionReset = now.addingTimeInterval(51 * 60)
        let midnight = calendar.startOfDay(for: now.addingTimeInterval(24 * 60 * 60))

        return [
            ProviderSnapshot(
                id: "claude",
                displayName: "Claude",
                glyph: .claude,
                fidelity: .derived,
                status: .ok,
                windows: [
                    LimitWindow(id: "claude.session", label: L10n.t("Current session"),
                                usedFraction: 0.73, resetsAt: sessionReset),
                    LimitWindow(id: "claude.all", label: L10n.t("All models"),
                                usedFraction: 0.07, resetsAt: midnight)
                ]
            ),
            ProviderSnapshot(
                id: "openai",
                displayName: "OpenAI",
                glyph: .openai,
                fidelity: .manual,
                status: .ok,
                windows: [
                    LimitWindow(id: "openai.session", label: L10n.t("Current session"),
                                usedFraction: 0.21, resetsAt: now.addingTimeInterval(3 * 60 * 60))
                ]
            ),
            ProviderSnapshot(
                id: "third",
                displayName: "Perplexity",
                glyph: .third,
                fidelity: .manual,
                status: .ok,
                windows: [
                    LimitWindow(id: "third.daily", label: L10n.t("Daily quota"),
                                usedFraction: 0.52, resetsAt: midnight)
                ]
            )
        ]
    }

    /// A history with one of each kind of copy, for `CODENOTCH_DEMO=1`.
    /// Nothing here comes from the real pasteboard.
    static func clipboardEntries(now: Date = Date()) -> [ClipboardEntry] {
        func text(_ string: String) -> ClipboardItem {
            ClipboardItem(representations: [ClipboardType.plainText: Data(string.utf8)])
        }
        func file(_ path: String) -> ClipboardItem {
            ClipboardItem(representations: [ClipboardType.fileURL: Data(URL(fileURLWithPath: path).absoluteString.utf8)])
        }
        let rich = ClipboardItem(representations: [
            ClipboardType.plainText: Data("Ship the clipboard history behind a setting".utf8),
            ClipboardType.html: Data("<b>Ship</b> the clipboard history behind a setting".utf8),
        ])
        return [
            ClipboardEntry(items: [text("git checkout -b clipboard-history")],
                           copiedAt: now.addingTimeInterval(-25), sourceBundleID: "com.apple.Terminal"),
            ClipboardEntry(items: [rich], copiedAt: now.addingTimeInterval(-6 * 60), sourceBundleID: "com.apple.Notes"),
            ClipboardEntry(items: [ClipboardItem(representations: [ClipboardType.png: demoImage()])],
                           copiedAt: now.addingTimeInterval(-22 * 60)),
            ClipboardEntry(items: [file("/etc/hosts"), file("/etc/shells")],
                           copiedAt: now.addingTimeInterval(-70 * 60), sourceBundleID: "com.apple.finder"),
            ClipboardEntry(items: [text("https://github.com/vinzdg/codenotch")],
                           copiedAt: now.addingTimeInterval(-3 * 3600), sourceBundleID: "com.apple.Safari"),
        ]
    }

    /// A small two-tone swatch, drawn rather than shipped.
    private static func demoImage() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 200,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGradient(starting: NSColor(deviceRed: 0.0, green: 0.55, blue: 0.95, alpha: 1),
                   ending: NSColor(deviceRed: 0.55, green: 0.2, blue: 0.95, alpha: 1))?
            .draw(in: NSRect(x: 0, y: 0, width: 320, height: 200), angle: 30)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
