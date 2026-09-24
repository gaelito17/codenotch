import SwiftUI

/// The screenshot cell, at the very foot of the stack.
///
/// The clipboard cell's frame — a quiet track, a glyph and an empty label
/// line — so the stack keeps one rhythm. No arc for the same reason: it
/// measures nothing. The glyph is the capture a click will take.
struct ScreenshotCell: View {
    var isHovered: Bool = false
    var mode: ScreenshotMode = .default

    var body: some View {
        VStack(spacing: NotchLayout.ringLabelGap) {
            ZStack {
                Circle()
                    .strokeBorder(isHovered ? Palette.textSecondary : Palette.ringTrack,
                                  lineWidth: NotchLayout.trackStroke)
                Image(systemName: mode.symbol)
                    .font(.system(size: NotchLayout.glyphSize * 0.8, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
            }
            .frame(width: NotchLayout.ringDiameter, height: NotchLayout.ringDiameter)
            .animation(.easeOut(duration: 0.15), value: isHovered)

            // The label line's height, kept empty, so the ring lines up with
            // the centres `ringCenter` hands out.
            Text(" ")
                .font(Typography.percent)
                .frame(height: NotchLayout.percentLineHeight)
        }
        .frame(height: NotchLayout.cellExtent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("Take a screenshot"))
        .accessibilityValue(mode.title)
        .accessibilityAddTraits(.isButton)
    }
}
