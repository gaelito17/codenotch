import AppKit
import SwiftUI

/// The clipboard history, beside the notch where a tooltip would be.
///
/// Built in the tooltip's own shell so it opens away from the bezel on every
/// edge, with the same tail, glass and reduce-transparency handling. It draws
/// and reports where its rows are; the window controller answers the clicks
/// (see `NotchPanel.onClickFirst`). The notch never becomes key, so the app
/// being worked in keeps focus and ⌘V pastes at once.
struct ClipboardPanel: View {
    let entries: [ClipboardEntry]
    let direction: NotchEdge.TooltipDirection
    var tailOffset: CGFloat = 0
    var now: Date = Date()
    var copiedID: UUID?
    /// Where to record the rows' and buttons' frames. Clicks are answered by
    /// the window controller from these; see `NotchPanel.onClickFirst`.
    var targets: ClipboardHitTargets?
    /// For VoiceOver, which acts through accessibility rather than clicks.
    var onPick: (ClipboardEntry) -> Void = { _ in }
    var onRemove: (UUID) -> Void = { _ in }
    var onClear: () -> Void = {}

    @Environment(\.tooltipSecondaryInk) private var secondaryInk

    private var contentHeight: CGFloat {
        NotchLayout.clipboardPanelHeight - 2 * NotchLayout.cardPadding
    }

    var body: some View {
        TooltipShell(height: NotchLayout.clipboardPanelHeight, direction: direction, tailOffset: tailOffset) {
            VStack(alignment: .leading, spacing: NotchLayout.cardPadding / 2) {
                header
                if entries.isEmpty {
                    empty
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(entries) { entry in
                                ClipboardRow(entry: entry, now: now, isCopied: entry.id == copiedID,
                                             targets: targets, onPick: onPick, onRemove: onRemove)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .reportFrame(to: targets) { $0.viewport = $1 }
                }
            }
            .frame(height: contentHeight, alignment: .top)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("Clipboard history"))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.t("Clipboard"))
                .font(Typography.cardTitle)
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 0)
            if !entries.isEmpty {
                Text(L10n.t("Clear"))
                    .font(Typography.cardBody)
                    .foregroundStyle(secondaryInk)
                    // A generous target: this is small text by a screen edge.
                    .padding(NotchLayout.clipboardRowPadding)
                    .contentShape(Rectangle())
                    .padding(-NotchLayout.clipboardRowPadding)
                    .reportFrame(to: targets) { $0.set(.clear, $1) }
                    .accessibilityElement()
                    .accessibilityLabel(L10n.t("Clear history"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onClear() }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: NotchLayout.cardPadding / 2) {
            Image(systemName: "list.clipboard")
                .font(.system(size: NotchLayout.clipboardRowIcon * 0.6))
            Text(L10n.t("Nothing copied yet"))
                .font(Typography.cardBody)
        }
        .foregroundStyle(secondaryInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One copy: what it is, where it came from, and when.
private struct ClipboardRow: View {
    let entry: ClipboardEntry
    let now: Date
    let isCopied: Bool
    let targets: ClipboardHitTargets?
    let onPick: (ClipboardEntry) -> Void
    let onRemove: (UUID) -> Void

    @Environment(\.tooltipSecondaryInk) private var secondaryInk

    private var isMissing: Bool { entry.isMissingFiles }

    var body: some View {
        HStack(alignment: .center, spacing: NotchLayout.headerGap) {
            ClipboardRowIcon(entry: entry)
                .frame(width: NotchLayout.clipboardRowIcon, height: NotchLayout.clipboardRowIcon)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(isCopied ? L10n.t("Copied") : detail)
                    .font(Typography.cardBody)
                    .foregroundStyle(isCopied ? Palette.ample : secondaryInk)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "xmark")
                .font(.system(size: NotchLayout.clipboardRowIcon * 0.3, weight: .semibold))
                .foregroundStyle(secondaryInk)
                .frame(width: NotchLayout.clipboardRowIcon * 0.5, height: NotchLayout.clipboardRowIcon)
                .contentShape(Rectangle())
                .reportFrame(to: targets) { [id = entry.id] in $0.set(.remove(id), $1) }
                .accessibilityHidden(true)
        }
        .padding(.vertical, NotchLayout.clipboardRowPadding)
        .opacity(isMissing ? 0.45 : 1)
        .contentShape(Rectangle())
        .reportFrame(to: targets) { [id = entry.id] in $0.set(.pick(id), $1) }
        .onDisappear { [id = entry.id] in
            targets?.set(.pick(id), nil)
            targets?.set(.remove(id), nil)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !isMissing { onPick(entry) } }
        .accessibilityAction(named: L10n.t("Remove from history")) { onRemove(entry.id) }
    }

    private var title: String {
        switch entry.kind {
        case .files:
            let urls = entry.fileURLs
            let first = urls.first?.lastPathComponent ?? L10n.t("File")
            return urls.count > 1 ? L10n.t("\(first) and \(urls.count - 1) more") : first
        case .image:
            if let size = ClipboardThumbnails.pixelSize(of: entry) {
                return L10n.t("Image, \(size.width) × \(size.height)")
            }
            return L10n.t("Image")
        case .richText, .text:
            // One line of whitespace per gap, so indented code and blank lines
            // do not spend the two lines the row has.
            let text = (entry.plainText ?? "")
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            return text.isEmpty ? L10n.t("Empty text") : text
        }
    }

    private var detail: String {
        let ago = ElapsedCopy.ago(since: entry.copiedAt, now: now)
        if isMissing { return L10n.t("Missing · \(ago)") }
        if entry.kind == .richText { return L10n.t("Rich text · \(ago)") }
        return ago
    }
}

private struct ClipboardRowIcon: View {
    let entry: ClipboardEntry

    var body: some View {
        switch entry.kind {
        case .image:
            if let image = ClipboardThumbnails.image(for: entry) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: NotchLayout.clipboardRowIcon, height: NotchLayout.clipboardRowIcon)
                    .clipShape(RoundedRectangle(cornerRadius: NotchLayout.clipboardRowIcon / 6, style: .continuous))
            } else {
                symbol("photo")
            }
        case .files:
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.fileURLs.first?.path ?? "/"))
                .resizable()
        case .richText, .text:
            if let icon = ClipboardThumbnails.appIcon(for: entry.sourceBundleID) {
                Image(nsImage: icon).resizable()
            } else {
                symbol("doc.text")
            }
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: NotchLayout.clipboardRowIcon * 0.55))
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Decoding a screenshot on every redraw of the list would be felt, so each
/// image is decoded once per entry and kept.
@MainActor
enum ClipboardThumbnails {
    private static let images = NSCache<NSUUID, NSImage>()
    private static var sizes: [UUID: CGSize] = [:]

    static func image(for entry: ClipboardEntry) -> NSImage? {
        if let cached = images.object(forKey: entry.id as NSUUID) { return cached }
        guard let data = entry.imageData, let image = NSImage(data: data) else { return nil }
        images.setObject(image, forKey: entry.id as NSUUID)
        return image
    }

    /// In pixels, which is what a screenshot's size is quoted in.
    static func pixelSize(of entry: ClipboardEntry) -> (width: Int, height: Int)? {
        if let size = sizes[entry.id] { return (Int(size.width), Int(size.height)) }
        guard let data = entry.imageData, let rep = NSBitmapImageRep(data: data) else { return nil }
        let size = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        sizes[entry.id] = size
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    static func appIcon(for bundleID: String?) -> NSImage? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Where the history panel's clickable parts were last laid out, in the
/// notch window's own top-left coordinates — the space the window controller
/// hit-tests in.
@MainActor
final class ClipboardHitTargets {
    enum Target: Hashable {
        case pick(UUID)
        case remove(UUID)
        case clear
    }

    static let coordinateSpace = "notchPanel"

    private(set) var frames: [Target: CGRect] = [:]
    /// The scrolled list's visible bounds. A row scrolled out of it keeps a
    /// frame, and a click there must not reach it.
    var viewport: CGRect?

    func set(_ target: Target, _ frame: CGRect?) {
        frames[target] = frame
    }

    /// A row's remove button sits inside the row, so it is asked first.
    func target(at point: CGPoint) -> Target? {
        let hits = frames.filter { target, frame in
            guard frame.contains(point) else { return false }
            if case .clear = target { return true }
            return viewport?.contains(point) ?? false
        }.map(\.key)
        if let clear = hits.first(where: { $0 == .clear }) { return clear }
        if let remove = hits.first(where: { if case .remove = $0 { return true } else { return false } }) {
            return remove
        }
        return hits.first
    }
}

private extension View {
    func reportFrame(to targets: ClipboardHitTargets?,
                     _ record: @escaping @MainActor (ClipboardHitTargets, CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(ClipboardHitTargets.coordinateSpace))
        } action: { frame in
            if let targets { record(targets, frame) }
        }
    }
}

extension ClipboardEntry {
    /// A file copied from Finder that has since moved or gone would paste a
    /// dead reference, so its row says so instead of offering it.
    var isMissingFiles: Bool {
        kind == .files && !fileURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
    }
}
