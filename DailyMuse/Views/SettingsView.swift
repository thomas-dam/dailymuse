import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            EndpointSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Endpoints", systemImage: "network")
                }

            GenerationSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Generation", systemImage: "paintbrush")
                }

            ScheduleSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Schedule", systemImage: "clock")
                }
        }
        .frame(width: 520, height: 400)
    }
}

// MARK: - Endpoint Settings

struct EndpointSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var llmTestStatus: TestStatus = .idle
    @State private var imageTestStatus: TestStatus = .idle

    enum TestStatus {
        case idle, testing, success, failure(String)
    }

    var body: some View {
        Form {
            Section("LLM Endpoint (Prompt Generation)") {
                TextField("Base URL", text: $appState.llmBaseURL)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text("e.g. http://localhost:1234/v1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("LM Studio · Ollama · oMLX · OpenAI")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                TextField("Model name", text: $appState.llmModelName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    testStatusIndicator(llmTestStatus)
                    Spacer()
                    Button("Test Connection") {
                        Task { await testLLM() }
                    }
                    .disabled(isTestingLLM)
                }
            }

            Section("Image Generation Endpoint") {
                TextField("Base URL", text: $appState.imageBaseURL)
                    .textFieldStyle(.roundedBorder)

                Picker("Endpoint Type", selection: Binding(
                    get: { ImageEndpointType(rawValue: appState.imageEndpointType) ?? .openAICompatible },
                    set: { appState.imageEndpointType = $0.rawValue }
                )) {
                    ForEach(ImageEndpointType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                HStack {
                    testStatusIndicator(imageTestStatus)
                    Spacer()
                    Button("Test Connection") {
                        Task { await testImage() }
                    }
                    .disabled(isTestingImage)
                }
            }
        }
        .padding()
    }

    private var isTestingLLM: Bool {
        if case .testing = llmTestStatus { return true }
        return false
    }

    private var isTestingImage: Bool {
        if case .testing = imageTestStatus { return true }
        return false
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
            let service = PromptService(baseURL: appState.llmBaseURL, model: appState.llmModelName)
            _ = try await service.generateImagePrompt(
                headlines: ["Test headline: technology advances"],
                style: .editorial
            )
            llmTestStatus = .success
        } catch {
            llmTestStatus = .failure(error.localizedDescription)
        }
    }

    private func testImage() async {
        imageTestStatus = .testing
        // For image endpoints, just try to reach the server
        let url = URL(string: appState.imageBaseURL)
        guard let url else {
            imageTestStatus = .failure("Invalid URL")
            return
        }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, (200...499).contains(http.statusCode) {
                imageTestStatus = .success
            } else {
                imageTestStatus = .failure("Unexpected response")
            }
        } catch {
            imageTestStatus = .failure(error.localizedDescription)
        }
    }
}

// MARK: - Generation Settings

struct GenerationSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Content Source") {
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
                }
            }

            Section("Style") {
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

            Section("Output") {
                HStack {
                    TextField("Width", value: $appState.imageWidth, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("×")
                    TextField("Height", value: $appState.imageHeight, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("px")
                }

                Toggle("E-ink post-processing", isOn: $appState.einkMode)
                Toggle("Set wallpaper automatically", isOn: $appState.setWallpaperAutomatically)
            }

            Section("Output Folder") {
                HStack {
                    Text(appState.outputDirectory.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Open") {
                        NSWorkspace.shared.open(appState.outputDirectory)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Schedule Settings

struct ScheduleSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Daily Schedule") {
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

                    Text("DailyMuse must be running for the schedule to work. Add it to Login Items for automatic startup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Launch at login", isOn: .constant(false))
                        .disabled(true)
                        // TODO: SMAppService.mainApp.register() for login item
                }
            }
        }
        .padding()
    }
}
