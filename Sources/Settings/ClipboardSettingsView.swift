import SwiftUI

/// Settings › Clipboard: the switch, how much to keep, and what macOS has
/// been told about Codenotch reading the pasteboard.
struct ClipboardSettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var clipboard: ClipboardService

    var body: some View {
        Form {
            Section(L10n.t("Clipboard history")) {
                Toggle(L10n.t("Keep clipboard history"), isOn: $preferences.clipboardHistoryEnabled)

                Text(L10n.t("Adds a clipboard cell at the end of the notch. Click it to see what you copied; click a copy to put it back on the clipboard, ready to paste."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker(L10n.t("Keep"), selection: $preferences.clipboardHistoryLimit) {
                    ForEach(ClipboardHistory.limitChoices, id: \.self) { count in
                        Text(L10n.t("\(count) copies")).tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!preferences.clipboardHistoryEnabled)

                LabeledContent(L10n.t("Stored")) {
                    HStack(spacing: 12) {
                        Text(L10n.t("\(clipboard.entries.count) copies"))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button(L10n.t("Clear history")) { clipboard.clear() }
                            .disabled(clipboard.entries.isEmpty)
                    }
                }
                .disabled(!preferences.clipboardHistoryEnabled)

                Text(L10n.t("Kept on this Mac only, in Application Support, and across restarts. Copies a password manager marks as private are never recorded. Switching this off deletes the history."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if preferences.clipboardHistoryEnabled {
                Section(L10n.t("Clipboard access")) {
                    LabeledContent(L10n.t("macOS")) {
                        Text(accessTitle)
                            .foregroundStyle(clipboard.access == .denied ? .red : .secondary)
                    }

                    Text(accessExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if clipboard.access != .allowed {
                        Button(L10n.t("Open Privacy & Security…")) {
                            NSWorkspace.shared.open(ClipboardService.privacySettingsURL)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        // The answer is changed in System Settings, and nothing tells us.
        .onAppear { clipboard.refreshAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            clipboard.refreshAccess()
        }
    }

    private var accessTitle: String {
        switch clipboard.access {
        case .notAsked: return L10n.t("Not asked yet")
        case .ask:      return L10n.t("Asks each time")
        case .allowed:  return L10n.t("Allowed")
        case .denied:   return L10n.t("Denied")
        }
    }

    private var accessExplanation: String {
        switch clipboard.access {
        case .notAsked:
            return L10n.t("The first time you copy something, macOS asks whether Codenotch may read the clipboard. Allow it, or copies are not recorded.")
        case .ask:
            return L10n.t("macOS asks before Codenotch reads the clipboard. To record copies without being asked, set Codenotch to Allow under Privacy & Security › Paste from Other Apps.")
        case .allowed:
            return L10n.t("Codenotch may read the clipboard. It reads only when something new has been copied.")
        case .denied:
            return L10n.t("macOS is keeping the clipboard from Codenotch, so new copies are not recorded. The history you have still works. Allow Codenotch under Privacy & Security › Paste from Other Apps.")
        }
    }
}
