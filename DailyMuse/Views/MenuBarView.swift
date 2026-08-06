import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let imageURL = appState.lastGeneratedImage {
                generatedImageHeader(imageURL)
            }

            Button {
                Task {
                    await appState.generate()
                }
            } label: {
                Label(appState.isGenerating ? "Generating..." : "Generate Now", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isGenerating)

            if let imageURL = appState.lastGeneratedImage {
                HStack(spacing: 8) {
                    Button("Set as Wallpaper", systemImage: "photo") {
                        setAsWallpaper(imageURL)
                    }
                    .buttonStyle(.plain)

                    Button("Show in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([imageURL])
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            Menu {
                Picker("Style", selection: Binding(
                    get: { StyleTemplate(rawValue: appState.styleTemplate) ?? .editorial },
                    set: { appState.styleTemplate = $0.rawValue }
                )) {
                    ForEach(StyleTemplate.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            } label: {
                Label(currentStyle.displayName, systemImage: "paintpalette")
            }

            scheduleIndicator

            Divider()

            SettingsLink {
                Label("Open Settings", systemImage: "gearshape")
            }

            Button("Quit DailyMuse") {
                NSApplication.shared.terminate(nil)
            }
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 360)
        .background(.ultraThinMaterial)
    }

    private var currentStyle: StyleTemplate {
        StyleTemplate(rawValue: appState.styleTemplate) ?? .editorial
    }

    @ViewBuilder
    private func generatedImageHeader(_ imageURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = NSImage(contentsOf: imageURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if let lastGeneratedDate = appState.lastGeneratedDate {
                Text(lastGeneratedDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var scheduleIndicator: some View {
        Label(scheduleText, systemImage: appState.schedulingEnabled ? "clock.badge.checkmark" : "clock")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var scheduleText: String {
        guard appState.schedulingEnabled else {
            return "Schedule off"
        }

        return "Daily at \(String(format: "%02d", appState.scheduleHour)):\(String(format: "%02d", appState.scheduleMinute))"
    }

    private func setAsWallpaper(_ imageURL: URL) {
        do {
            try WallpaperService().setWallpaper(imageURL)
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}
