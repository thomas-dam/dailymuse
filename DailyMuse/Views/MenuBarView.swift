import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Status
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(appState.statusMessage)
                    .font(.headline)
            }

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            Divider()

            // Last generated preview
            if let imageURL = appState.lastGeneratedImage,
               let nsImage = NSImage(contentsOf: imageURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 320, maxHeight: 180)
                    .clipShape(.rect(cornerRadius: 8))

                if let date = appState.lastGeneratedDate {
                    Text("Generated \(date, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Actions
            Button {
                Task { await appState.generate() }
            } label: {
                Label("Generate Now", systemImage: "sparkles")
            }
            .disabled(appState.isGenerating)
            .keyboardShortcut("g", modifiers: .command)

            if let imageURL = appState.lastGeneratedImage {
                Button {
                    try? WallpaperService().setWallpaper(imageURL)
                } label: {
                    Label("Set as Wallpaper", systemImage: "desktopcomputer")
                }

                Button {
                    NSWorkspace.shared.selectFile(imageURL.path, inFileViewerRootedAtPath: "")
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            }

            Divider()

            // Style picker
            Menu {
                ForEach(StyleTemplate.allCases) { style in
                    Button {
                        appState.styleTemplate = style.rawValue
                    } label: {
                        HStack {
                            Text(style.displayName)
                            if appState.styleTemplate == style.rawValue {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let current = StyleTemplate(rawValue: appState.styleTemplate) ?? .editorial
                Label("Style: \(current.displayName)", systemImage: "paintpalette")
            }

            Divider()

            // Schedule indicator
            HStack {
                Image(systemName: appState.schedulingEnabled ? "clock.fill" : "clock")
                    .foregroundStyle(appState.schedulingEnabled ? .green : .secondary)
                Text(appState.schedulingEnabled
                     ? "Daily at \(String(format: "%02d:%02d", appState.scheduleHour, appState.scheduleMinute))"
                     : "No schedule")
                    .font(.caption)
            }

            Divider()

            SettingsLink {
                Label("Settings…", systemImage: "gear")
            }

            Button("Quit DailyMuse") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding()
        .frame(width: 360)
    }

    private var statusColor: Color {
        if appState.errorMessage != nil { return .red }
        if appState.isGenerating { return .orange }
        return .green
    }
}
