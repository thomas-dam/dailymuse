import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var isGenerating = false
    @Published var lastGeneratedImage: URL?
    @Published var lastGeneratedDate: Date?
    @Published var statusMessage = "Idle"
    @Published var errorMessage: String?

    // MARK: - Settings (persisted via AppStorage in SettingsView, read here)

    @AppStorage("llmBaseURL") var llmBaseURL = "http://localhost:1234/v1"
    @AppStorage("llmModelName") var llmModelName = "qwen3-4b"
    @AppStorage("imageBaseURL") var imageBaseURL = "http://localhost:7860"
    @AppStorage("imageEndpointType") var imageEndpointType = ImageEndpointType.openAICompatible.rawValue
    @AppStorage("headlineSource") var headlineSource = HeadlineSourceType.hackerNews.rawValue
    @AppStorage("rssURL") var rssURL = ""
    @AppStorage("styleTemplate") var styleTemplate = StyleTemplate.editorial.rawValue
    @AppStorage("scheduleHour") var scheduleHour = 7
    @AppStorage("scheduleMinute") var scheduleMinute = 0
    @AppStorage("schedulingEnabled") var schedulingEnabled = false
    @AppStorage("setWallpaperAutomatically") var setWallpaperAutomatically = true
    @AppStorage("imageWidth") var imageWidth = 2560
    @AppStorage("imageHeight") var imageHeight = 1440
    @AppStorage("einkMode") var einkMode = false

    private let wallpaperService = WallpaperService()
    private var schedulerTimer: Timer?

    var outputDirectory: URL {
        let directory = URL.picturesDirectory.appending(path: "DailyMuse", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    init() {
        loadLastGenerated()
        setupSchedulerIfNeeded()
    }

    // MARK: - Generation Pipeline

    func generate() async {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil

        do {
            // 1. Fetch headlines
            statusMessage = "Fetching headlines…"
            let source = HeadlineSourceType(rawValue: headlineSource) ?? .hackerNews
            let headlines = try await HeadlineFetcher.fetch(source: source, rssURL: rssURL)

            // 2. Build image prompt via LLM
            statusMessage = "Crafting prompt…"
            let style = StyleTemplate(rawValue: styleTemplate) ?? .editorial
            let promptService = PromptService(baseURL: llmBaseURL, model: llmModelName)
            let imagePrompt = try await promptService.generateImagePrompt(
                headlines: headlines,
                style: style
            )

            // 3. Generate image
            statusMessage = "Generating image…"
            let endpointType = ImageEndpointType(rawValue: imageEndpointType) ?? .openAICompatible
            let imageService = ImageService(baseURL: imageBaseURL, endpointType: endpointType)
            let imageData = try await imageService.generate(
                prompt: imagePrompt,
                width: imageWidth,
                height: imageHeight
            )

            // 4. Post-process for e-ink if needed
            let finalData: Data
            if einkMode {
                statusMessage = "Processing for e-ink…"
                finalData = try ImageProcessor.processForEink(imageData)
            } else {
                finalData = imageData
            }

            // 5. Save
            statusMessage = "Saving…"
            let filename = Self.timestampedFilename(style: style, eink: einkMode)
            let fileURL = outputDirectory.appendingPathComponent(filename)
            try finalData.write(to: fileURL)

            // Save sidecar JSON
            let sidecar = GenerationSidecar(
                generatedAt: Date(),
                llmEndpoint: llmBaseURL,
                llmModel: llmModelName,
                imageEndpoint: imageBaseURL,
                style: style.rawValue,
                headlines: headlines,
                imagePrompt: imagePrompt
            )
            let sidecarURL = fileURL.deletingPathExtension().appendingPathExtension("json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(sidecar).write(to: sidecarURL)

            lastGeneratedImage = fileURL
            lastGeneratedDate = Date()
            saveLastGenerated()

            // 6. Set wallpaper
            if setWallpaperAutomatically {
                statusMessage = "Setting wallpaper…"
                try wallpaperService.setWallpaper(fileURL)
            }

            statusMessage = "Done"
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Error"
        }

        isGenerating = false
    }

    // MARK: - Scheduling

    func setupSchedulerIfNeeded() {
        schedulerTimer?.invalidate()
        guard schedulingEnabled else { return }

        // Check every 60 seconds if it's time to generate.
        schedulerTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let now = Calendar.current.dateComponents([.hour, .minute], from: .now)
                guard now.hour == scheduleHour, now.minute == scheduleMinute else { return }

                // Only generate once per scheduled minute.
                if let lastGeneratedDate,
                   Calendar.current.isDate(lastGeneratedDate, inSameDayAs: .now) {
                    return
                }

                await generate()
            }
        }
    }

    // MARK: - History

    func historyImages() -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .filter { $0.pathExtension == "png" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da > db
            }
    }

    // MARK: - Persistence helpers

    private func saveLastGenerated() {
        UserDefaults.standard.set(lastGeneratedImage?.path, forKey: "lastGeneratedImagePath")
        UserDefaults.standard.set(lastGeneratedDate, forKey: "lastGeneratedDate")
    }

    private func loadLastGenerated() {
        if let path = UserDefaults.standard.string(forKey: "lastGeneratedImagePath") {
            lastGeneratedImage = URL(fileURLWithPath: path)
        }
        lastGeneratedDate = UserDefaults.standard.object(forKey: "lastGeneratedDate") as? Date
    }

    // MARK: - Helpers

    private static func timestampedFilename(style: StyleTemplate, eink: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let suffix = eink ? "-eink" : ""
        return "dailymuse-\(formatter.string(from: Date()))-\(style.rawValue)\(suffix).png"
    }
}

// MARK: - Sidecar

struct GenerationSidecar: Codable {
    let generatedAt: Date
    let llmEndpoint: String
    let llmModel: String
    let imageEndpoint: String
    let style: String
    let headlines: [String]
    let imagePrompt: String
}
