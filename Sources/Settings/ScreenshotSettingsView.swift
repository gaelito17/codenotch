import SwiftUI

/// Settings › Screenshot: the switch, and what a click on the cell captures.
struct ScreenshotSettingsView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section(L10n.t("Screenshot")) {
                Toggle(L10n.t("Show the screenshot cell"), isOn: $preferences.screenshotCellEnabled)

                Text(L10n.t("Adds a screenshot cell at the end of the notch. Click it to take a screenshot, the same as the macOS shortcut."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker(L10n.t("Capture"), selection: $preferences.screenshotMode) {
                    ForEach(ScreenshotMode.allCases) { mode in
                        HStack {
                            Text(mode.title)
                            Text(mode.shortcut).foregroundStyle(.secondary)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(!preferences.screenshotCellEnabled)

                Toggle(L10n.t("Copy to the clipboard instead of saving a file"),
                       isOn: $preferences.screenshotToClipboard)
                    .disabled(!preferences.screenshotCellEnabled)

                LabeledContent(L10n.t("Saved to")) {
                    HStack(spacing: 12) {
                        Text(displayPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(L10n.t("Choose…"), action: chooseFolder)
                    }
                }
                .disabled(preferences.screenshotToClipboard)

                if preferences.screenshotFolder != nil {
                    Button(L10n.t("Use the macOS folder")) { preferences.screenshotFolder = nil }
                        .disabled(preferences.screenshotToClipboard)
                }

                Text(preferences.screenshotToClipboard
                     ? L10n.t("Screenshots go to the clipboard, ready to paste. No file is saved.")
                     : preferences.screenshotFolder == nil
                     ? L10n.t("Where macOS saves its own screenshots, until you choose another folder.")
                     : L10n.t("If this folder is moved or deleted, screenshots go where macOS saves its own."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var displayPath: String {
        ScreenshotCapture.destinationFolder(chosen: preferences.screenshotFolder)
            .path(percentEncoded: false)
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.t("Choose")
        panel.directoryURL = ScreenshotCapture.destinationFolder(chosen: preferences.screenshotFolder)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preferences.screenshotFolder = url.path(percentEncoded: false)
    }
}
