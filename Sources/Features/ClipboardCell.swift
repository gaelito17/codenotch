import SwiftUI

/// The clipboard history's cell, at the foot of the stack.
///
/// Built on a provider cell's frame — the same track, glyph size and label
/// line — so the stack keeps one rhythm. It has no arc: it measures nothing,
/// and an arc here would read as a usage limit.
struct ClipboardCell: View {
    var isHovered: Bool = false
    var isOpen: Bool = false

    var body: some View {
        VStack(spacing: NotchLayout.ringLabelGap) {
            ZStack {
                Circle()
                    .strokeBorder(isHovered || isOpen ? Palette.textSecondary : Palette.ringTrack,
                                  lineWidth: NotchLayout.trackStroke)
                Image(systemName: "list.clipboard")
                    .font(.system(size: NotchLayout.glyphSize * 0.8, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
            }
            .frame(width: NotchLayout.ringDiameter, height: NotchLayout.ringDiameter)
            .animation(.easeOut(duration: 0.15), value: isHovered || isOpen)

            // Holds the label line a provider cell has, so the ring lines up
            // with the centres `ringCenter` hands out.
            Color.clear.frame(height: NotchLayout.percentLineHeight)
        }
        .frame(height: NotchLayout.cellExtent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("Clipboard history"))
        .accessibilityAddTraits(.isButton)
    }
}
