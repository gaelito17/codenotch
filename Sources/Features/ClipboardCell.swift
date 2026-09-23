import SwiftUI

/// The clipboard history's cell, at the foot of the stack.
///
/// Built on a provider cell's frame — the same track, glyph size and label
/// line — so the stack keeps one rhythm. It has no arc: it measures nothing,
/// and an arc here would read as a usage limit.
struct ClipboardCell: View {
    var isHovered: Bool = false
    var isOpen: Bool = false
    /// How many copies the history holds, where a provider cell shows its
    /// reading. Quieter than a reading: it is a count, not a warning.
    var count: Int = 0

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

            // Always the label line's height, count or not, so the ring lines
            // up with the centres `ringCenter` hands out.
            Text(count > 0 ? "\(count)" : " ")
                .font(Typography.percent)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .frame(height: NotchLayout.percentLineHeight)
                .contentTransition(.numericText())
        }
        .frame(height: NotchLayout.cellExtent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("Clipboard history"))
        .accessibilityValue(L10n.t("\(count) items"))
        .accessibilityAddTraits(.isButton)
    }
}
