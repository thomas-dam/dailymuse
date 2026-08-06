import SwiftUI
import Combine
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    @Published var isGenerating = false
    @Published var lastGeneratedImage: URL?
    @Published var lastGeneratedDate: Date?
    @Published var statusMessage = "Idle"
    @Published var errorMessage: String?
    @Published var llmAPIKeyForEditing = ""
    @Published var imageAPIKeyForEditing = ""

    // MARK: - Settings (persisted via AppStorage in SettingsView, read here)

    @AppStorage("llmBaseURL") var llmBaseURL = "http://localhost:1234/v1"
    @AppStorage("llmModelName") var llmModelName = "qwen3-vl-8b-instruct"
    @AppStorage("imageBaseURL") var imageBaseURL = "http://localhost:7860"
    @AppStorage("imageEndpointType") var imageEndpointType = ImageEndpointType.openAICompatible.rawValue
    @AppStorage("imageModelName") var imageModelName = "krea-2"
    @AppStorage("imageResponseFormat") var imageResponseFormat = ImageResponseFormat.b64JSON.rawValue
    @AppStorage("headlineSource") var headlineSource = HeadlineSourceType.hackerNews.rawValue
    @AppStorage("rssURL") var rssURL = ""
    @AppStorage("styleTemplate") var styleTemplate = StyleTemplate.editorial.rawValue
    @AppStorage("scheduleHour") var scheduleHour = 7
    @AppStorage("scheduleMinute") var scheduleMinute = 0
    @AppStorage("schedulingEnabled") var schedulingEnabled = false
    @AppStorage("setWallpaperAutomatically") var setWallpaperAutomatically = true
    @AppStorage("imageWidth") var imageWidth = 2560
    @AppStorage("imageHeight") var imageHeight = 1440
    @AppStorage("imageGenerationTimeoutMinutes") var imageGenerationTimeoutMinutes = 60
    @AppStorage("einkMode") var einkMode = false

    private let wallpaperService = WallpaperService()
    private var schedulerTimer: Timer?
    private var hasLoadedAPIKeysForEditing = false

    var outputDirectory: URL {
        let directory = URL.picturesDirectory.appending(path: "DailyMuse", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    init() {
        loadLastGenerated()
        setupSchedulerIfNeeded()
    }

    // MARK: - Endpoint editing

    func loadAPIKeysForEditingIfNeeded() {
        guard !hasLoadedAPIKeysForEditing else { return }

        llmAPIKeyForEditing = KeychainHelper.load(
            key: KeychainHelper.llmApiKey,
            service: KeychainHelper.serviceIdentifier
        ) ?? ""
        imageAPIKeyForEditing = KeychainHelper.load(
            key: KeychainHelper.imageApiKey,
            service: KeychainHelper.serviceIdentifier
        ) ?? ""
        hasLoadedAPIKeysForEditing = true
    }

    func saveAPIKeyForEditing(_ apiKey: String, key: String) throws {
        if apiKey.isEmpty {
            try KeychainHelper.delete(key: key, service: KeychainHelper.serviceIdentifier)
        } else {
            try KeychainHelper.save(key: key, service: KeychainHelper.serviceIdentifier, data: apiKey)
        }
    }

    // MARK: - Generation Pipeline

    func generate(isScheduledRun: Bool = false, forceSetWallpaper: Bool = false) async {
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
            let promptModel = try PromptService.validatedModelIdentifier(llmModelName)
            var promptService = PromptService(baseURL: llmBaseURL, model: promptModel)
            promptService.apiKey = KeychainHelper.load(
                key: KeychainHelper.llmApiKey,
                service: KeychainHelper.serviceIdentifier
            )
            let target: GenerationTarget = einkMode ? .eink : .web
            let promptResult = try await promptService.generateImagePrompt(
                headlines: headlines,
                style: style,
                target: target
            )

            // 3. Generate image
            statusMessage = "Generating image…"
            let endpointType = ImageEndpointType(rawValue: imageEndpointType) ?? .openAICompatible
            var imageService = ImageService(
                baseURL: imageBaseURL,
                endpointType: endpointType,
                timeoutSeconds: imageGenerationTimeout,
                imageModel: imageModelName,
                responseFormat: ImageResponseFormat(rawValue: imageResponseFormat) ?? .b64JSON
            )
            imageService.apiKey = KeychainHelper.load(
                key: KeychainHelper.imageApiKey,
                service: KeychainHelper.serviceIdentifier
            )
            let imageData = try await imageService.generate(
                prompt: promptResult.imagePrompt,
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
                llmModel: promptModel,
                imageEndpoint: imageBaseURL,
                imageModel: imageModelName,
                imageResponseFormat: imageResponseFormat,
                style: style.rawValue,
                target: target.rawValue,
                headlines: headlines,
                rawPromptOutput: promptResult.rawOutput,
                imagePrompt: promptResult.imagePrompt
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
            if setWallpaperAutomatically || forceSetWallpaper {
                statusMessage = "Setting wallpaper…"
                try wallpaperService.setWallpaper(fileURL)
            }

            statusMessage = "Done"

            if isScheduledRun {
                sendNotification(
                    title: "DailyMuse",
                    body: "New wallpaper set — \(style.displayName)",
                    imageURL: fileURL
                )
            }
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Error"

            if isScheduledRun {
                sendNotification(
                    title: "DailyMuse",
                    body: "Generation failed: \(error.localizedDescription)"
                )
            }
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

                await generate(isScheduledRun: true)
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

    private var imageGenerationTimeout: TimeInterval {
        TimeInterval(max(1, imageGenerationTimeoutMinutes) * 60)
    }

    private func sendNotification(title: String, body: String, imageURL: URL? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        if let imageURL,
           let attachment = try? UNNotificationAttachment(identifier: "wallpaper", url: imageURL) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(
            identifier: "dailymuse-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Sidecar

struct GenerationSidecar: Codable {
    let generatedAt: Date
    let llmEndpoint: String
    let llmModel: String
    let imageEndpoint: String
    let imageModel: String
    let imageResponseFormat: String
    let style: String
    let target: String
    let headlines: [String]
    let rawPromptOutput: String
    let imagePrompt: String
}
