import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: SettingsPane? = .endpoints

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch selection ?? .endpoints {
            case .endpoints:
                EndpointSettingsView()
                    .environmentObject(appState)
            case .generation:
                GenerationSettingsView()
                    .environmentObject(appState)
            case .schedule:
                ScheduleSettingsView()
                    .environmentObject(appState)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 620, minHeight: 460)
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case endpoints
    case generation
    case schedule

    var id: Self { self }

    var title: String {
        switch self {
        case .endpoints: "Endpoints"
        case .generation: "Generation"
        case .schedule: "Schedule"
        }
    }

    var systemImage: String {
        switch self {
        case .endpoints: "network"
        case .generation: "paintbrush"
        case .schedule: "clock"
        }
    }
}

// MARK: - Endpoint Settings

struct EndpointSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var llmTestStatus: TestStatus = .idle
    @State private var imageTestStatus: TestStatus = .idle
    @State private var keychainMessage: String?

    enum TestStatus {
        case idle, testing, success, failure(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Base URL", text: $appState.llmBaseURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            HStack {
                                Button("Paste", systemImage: "doc.on.clipboard") {
                                    pasteIntoLLMBaseURL()
                                }
                                Spacer()
                            }
                        }
                        SecureField("API Key (optional)", text: $appState.llmAPIKeyForEditing)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: 420)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .onChange(of: appState.llmAPIKeyForEditing) {
                                saveAPIKey(appState.llmAPIKeyForEditing, key: KeychainHelper.llmApiKey)
                            }
                        Text("Stored in Keychain. Leave blank to keep any saved key; enter a new value to replace it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text("e.g. http://localhost:1234/v1")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("LM Studio · Ollama · oMLX · OpenAI")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        TextField("Model name", text: $appState.llmModelName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        Text("Enter one exact model identifier from your LLM server. The model remains your choice.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            testStatusIndicator(llmTestStatus)
                            Spacer()
                            Button("Test", systemImage: "network.badge.shield.half.filled") {
                                Task { await testLLM() }
                            }
                            .help("Test Connection")
                            .disabled(isTestingLLM)
                        }
                    }
                } label: {
                    Label("LLM Endpoint", systemImage: "text.bubble")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Base URL", text: $appState.imageBaseURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            HStack {
                                Button("Paste", systemImage: "doc.on.clipboard") {
                                    pasteIntoImageBaseURL()
                                }
                                Button("Use fal.ai") {
                                    useFalPreset()
                                }
                                Spacer()
                            }
                        }
                        SecureField("API Key (optional)", text: $appState.imageAPIKeyForEditing)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: 420)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .onChange(of: appState.imageAPIKeyForEditing) {
                                saveAPIKey(appState.imageAPIKeyForEditing, key: KeychainHelper.imageApiKey)
                            }
                        Text("Stored in Keychain. Leave blank to keep any saved key; enter a new value to replace it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Endpoint Type", selection: Binding(
                            get: { ImageEndpointType(rawValue: appState.imageEndpointType) ?? .openAICompatible },
                            set: { appState.imageEndpointType = $0.rawValue }
                        )) {
                            ForEach(ImageEndpointType.allCases) { type in
                                Text(type.displayName).tag(type)
                            }
                        }

                        Text(selectedImageEndpointType.contractDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if selectedImageEndpointType == .openAICompatible || selectedImageEndpointType == .falQueue {
                            TextField(selectedImageEndpointType == .falQueue ? "fal.ai model ID" : "Image model", text: $appState.imageModelName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            Text(selectedImageEndpointType == .falQueue ? "Example: fal-ai/flux/schnell or openai/gpt-image-2." : "Example: krea-2.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if selectedImageEndpointType == .openAICompatible {
                            Picker("Response Format", selection: Binding(
                                get: { ImageResponseFormat(rawValue: appState.imageResponseFormat) ?? .b64JSON },
                                set: { appState.imageResponseFormat = $0.rawValue }
                            )) {
                                ForEach(ImageResponseFormat.allCases) { format in
                                    Text(format.displayName).tag(format)
                                }
                            }
                        }

                        HStack {
                            testStatusIndicator(imageTestStatus)
                            Spacer()
                            Button("Test", systemImage: "network.badge.shield.half.filled") {
                                Task { await testImage() }
                            }
                            .help("Test Generation Endpoint")
                            .disabled(isTestingImage)
                        }
                    }
                } label: {
                    Label("Image Generation Endpoint", systemImage: "photo")
                        .font(.headline)
                }

                if let keychainMessage {
                    Text(keychainMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    private var isTestingLLM: Bool {
        if case .testing = llmTestStatus { return true }
        return false
    }

    private var isTestingImage: Bool {
        if case .testing = imageTestStatus { return true }
        return false
    }

    private var selectedImageEndpointType: ImageEndpointType {
        ImageEndpointType(rawValue: appState.imageEndpointType) ?? .openAICompatible
    }

    @ViewBuilder
    private func testStatusIndicator(_ status: TestStatus) -> some View {
        switch status {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
                .controlSize(.small)
            Text("Testing…").font(.caption)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Connected").font(.caption).foregroundStyle(.green)
        case .failure(let msg):
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
            Text(msg).font(.caption).foregroundStyle(.red).lineLimit(2)
        }
    }

    private func testLLM() async {
        llmTestStatus = .testing
        do {
            var service = PromptService(baseURL: appState.llmBaseURL, model: appState.llmModelName)
            service.apiKey = appState.llmAPIKeyForEditing.nilIfEmpty ?? KeychainHelper.load(
                key: KeychainHelper.llmApiKey,
                service: KeychainHelper.serviceIdentifier
            )
            _ = try await service.generateImagePrompt(
                headlines: ["Test headline: technology advances"],
                style: .editorial,
                target: appState.einkMode ? .eink : .web
            )
            llmTestStatus = .success
        } catch {
            llmTestStatus = .failure(error.localizedDescription)
        }
    }

    private func testImage() async {
        imageTestStatus = .testing
        do {
            var service = ImageService(
                baseURL: appState.imageBaseURL,
                endpointType: selectedImageEndpointType,
                timeoutSeconds: TimeInterval(max(1, appState.imageGenerationTimeoutMinutes) * 60),
                imageModel: appState.imageModelName,
                responseFormat: ImageResponseFormat(rawValue: appState.imageResponseFormat) ?? .b64JSON
            )
            service.apiKey = appState.imageAPIKeyForEditing.nilIfEmpty ?? KeychainHelper.load(
                key: KeychainHelper.imageApiKey,
                service: KeychainHelper.serviceIdentifier
            )
            try await service.testEndpoint()
            imageTestStatus = .success
        } catch {
            imageTestStatus = .failure(error.localizedDescription)
        }
    }

    private func saveAPIKey(_ apiKey: String, key: String) {
        do {
            try appState.saveAPIKeyForEditing(apiKey, key: key)
            keychainMessage = nil
        } catch {
            keychainMessage = "API key could not be saved to Keychain."
        }
    }

    private func pasteIntoLLMBaseURL() {
        if let pasted = NSPasteboard.general.string(forType: .string) {
            appState.llmBaseURL = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func pasteIntoImageBaseURL() {
        if let pasted = NSPasteboard.general.string(forType: .string) {
            appState.imageBaseURL = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func useFalPreset() {
        appState.imageEndpointType = ImageEndpointType.falQueue.rawValue
        appState.imageBaseURL = "https://queue.fal.run"
        appState.imageModelName = "fal-ai/flux/schnell"
        appState.imageResponseFormat = ImageResponseFormat.url.rawValue
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Generation Settings

struct GenerationSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Headlines from", selection: Binding(
                            get: { HeadlineSourceType(rawValue: appState.headlineSource) ?? .hackerNews },
                            set: { appState.headlineSource = $0.rawValue }
                        )) {
                            ForEach(HeadlineSourceType.allCases) { source in
                                Text(source.displayName).tag(source)
                            }
                        }

                        if HeadlineSourceType(rawValue: appState.headlineSource) == .rss {
                            TextField("RSS Feed URL", text: $appState.rssURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                } label: {
                    Label("Content Source", systemImage: "newspaper")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Template", selection: Binding(
                            get: { StyleTemplate(rawValue: appState.styleTemplate) ?? .editorial },
                            set: { appState.styleTemplate = $0.rawValue }
                        )) {
                            ForEach(StyleTemplate.allCases) { style in
                                VStack(alignment: .leading) {
                                    Text(style.displayName)
                                    Text(style.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .tag(style)
                            }
                        }
                    }
                } label: {
                    Label("Style", systemImage: "paintpalette")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField("Width", value: $appState.imageWidth, format: .number.grouping(.never).precision(.fractionLength(0)))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("×")
                            TextField("Height", value: $appState.imageHeight, format: .number.grouping(.never).precision(.fractionLength(0)))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("px")
                        }

                        Stepper(
                            "Image wait time: \(appState.imageGenerationTimeoutMinutes) min",
                            value: $appState.imageGenerationTimeoutMinutes,
                            in: 1...180,
                            step: 5
                        )

                        Toggle("E-ink post-processing", isOn: $appState.einkMode)
                        Toggle("Set wallpaper automatically", isOn: $appState.setWallpaperAutomatically)

                        HStack {
                            if appState.isGenerating {
                                ProgressView()
                                    .controlSize(.small)
                                Text(appState.statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let errorMessage = appState.errorMessage {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            } else {
                                Text(appState.statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Generate & Set Wallpaper", systemImage: "photo.badge.arrow.down") {
                                Task {
                                    await appState.generate(forceSetWallpaper: true)
                                }
                            }
                            .disabled(appState.isGenerating)
                        }
                    }
                } label: {
                    Label("Output", systemImage: "square.and.arrow.down")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(appState.outputDirectory.path)
                                .font(.caption)
                                .monospaced()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Open") {
                                NSWorkspace.shared.open(appState.outputDirectory)
                            }
                        }
                    }
                } label: {
                    Label("Output Folder", systemImage: "folder")
                        .font(.headline)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Schedule Settings

struct ScheduleSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var loginItemError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Enable daily generation", isOn: $appState.schedulingEnabled)
                            .onChange(of: appState.schedulingEnabled) {
                                appState.setupSchedulerIfNeeded()
                            }

                        if appState.schedulingEnabled {
                            HStack {
                                Picker("Hour", selection: $appState.scheduleHour) {
                                    ForEach(0..<24, id: \.self) { h in
                                        Text(String(format: "%02d", h)).tag(h)
                                    }
                                }
                                .frame(width: 80)

                                Text(":")

                                Picker("Minute", selection: $appState.scheduleMinute) {
                                    ForEach([0, 15, 30, 45], id: \.self) { m in
                                        Text(String(format: "%02d", m)).tag(m)
                                    }
                                }
                                .frame(width: 80)
                            }
                            .onChange(of: appState.scheduleHour) { appState.setupSchedulerIfNeeded() }
                            .onChange(of: appState.scheduleMinute) { appState.setupSchedulerIfNeeded() }

                            Toggle("Launch at login", isOn: Binding(
                                get: { loginItemStatus == .enabled || loginItemStatus == .requiresApproval },
                                set: { isEnabled in
                                    setLaunchAtLogin(isEnabled)
                                }
                            ))

                            Label("DailyMuse must be running for scheduled generation. Enable Launch at Login to start automatically.", systemImage: "info.circle")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            loginItemStatusView
                        }
                    }
                } label: {
                    Label("Daily Schedule", systemImage: "calendar.badge.clock")
                        .font(.headline)
                }
            }
            .padding(16)
        }
        .onAppear(perform: refreshLoginItemStatus)
    }

    @ViewBuilder
    private var loginItemStatusView: some View {
        switch loginItemStatus {
        case .enabled:
            EmptyView()
        case .notRegistered:
            if let loginItemError {
                Text(loginItemError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .requiresApproval:
            VStack(alignment: .leading, spacing: 6) {
                Text("Enable DailyMuse in System Settings -> General -> Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Login Items Settings") {
                    openLoginItemsSettings()
                }
            }
        case .notFound:
            Text("Launch at login is unavailable for this build. A signed app bundle is required.")
                .font(.caption)
                .foregroundStyle(.secondary)
        @unknown default:
            Text("Launch at login status is unavailable.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func setLaunchAtLogin(_ isEnabled: Bool) {
        loginItemError = nil

        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemError = "Launch at login could not be updated. A signed app bundle is required."
            NSLog("DailyMuse login item update failed: \(error.localizedDescription)")
        }

        refreshLoginItemStatus()
    }

    private func refreshLoginItemStatus() {
        loginItemStatus = SMAppService.mainApp.status
    }

    private func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
