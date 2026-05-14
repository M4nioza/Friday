import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            TabView {
                SystemStatusView()
                    .tabItem { Label("System", systemImage: "desktopcomputer") }

                GenerationSettingsView()
                    .tabItem { Label("Generation", systemImage: "slider.horizontal.3") }

                BrainSettingsView()
                    .tabItem { Label("Memory", systemImage: "brain") }

                AboutView()
                    .tabItem { Label("About", systemImage: "info.circle") }
            }
            .frame(minWidth: 480, minHeight: 420)
        }
        .frame(width: 540, height: 520)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Configure Friday to your liking")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.08), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

// MARK: - Model Manager Panel

struct ModelManagerPanelView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model Manager")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Download and manage MLX models")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.green.opacity(0.08), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            ModelSettingsView()
                .frame(minWidth: 480, minHeight: 420)
        }
        .frame(width: 540, height: 520)
    }
}

// MARK: - Model Settings

struct ModelSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var downloadedModels: [DownloadedModelInfo] = []
    @State private var isLoading = true
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadStatus = ""
    @State private var modelName: String = ""
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isModelLoaded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                currentModelCard

                downloadCard

                downloadedModelsCard
            }
            .padding()
        }
        .task {
            loadModels()
            isModelLoaded = await LLMEngine.shared.isModelLoaded()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var currentModelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: isModelLoaded ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundColor(isModelLoaded ? .green : .gray)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isModelLoaded ? "Model Loaded" : "No Model Loaded")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(appState.currentModel.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isModelLoaded {
                    Button("Unload") {
                        Task {
                            await LLMEngine.shared.unloadModel()
                            isModelLoaded = false
                            await appState.updateModelState()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .padding()
        .cardBackground()
    }

    private var downloadCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Download Model", systemImage: "arrow.down.circle")
                .font(.headline)

            HStack {
                TextField("e.g., Llama-3.2-1B-Instruct", text: $modelName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isDownloading)

                Button(action: downloadModel) {
                    if isDownloading {
                        ProgressView()
                    } else {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(modelName.isEmpty || isDownloading)
            }

            if isDownloading {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(.linear)

                    HStack {
                        Text(downloadStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("\(Int(downloadProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Text("Enter a model name from HuggingFace mlx-community")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .cardBackground()
    }

    private var downloadedModelsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Downloaded Models", systemImage: "folder")
                    .font(.headline)

                Spacer()

                Button(action: loadModels) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Refresh")
            }

            if isLoading {
                HStack {
                    ProgressView()
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if downloadedModels.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)

                    Text("No models downloaded yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(downloadedModels) { model in
                    modelRow(model)
                }
            }
        }
        .padding()
        .cardBackground()
    }

    private func modelRow(_ model: DownloadedModelInfo) -> some View {
        let isLoaded = appState.currentModel.path == model.path && isModelLoaded

        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Label("\(model.contextLength / 1024)k ctx", systemImage: "text.alignleft")
                    Label(model.formattedSize, systemImage: "doc")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            if isLoaded {
                Label("Loaded", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)

                Button(action: {
                    Task {
                        await LLMEngine.shared.unloadModel()
                        isModelLoaded = false
                        await appState.updateModelState()
                    }
                }) {
                    Image(systemName: "stop.circle")
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
            } else {
                Button("Load") {
                    loadModel(model)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }

            Button(action: {
                deleteModel(model)
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func loadModels() {
        isLoading = true
        Task {
            downloadedModels = await LLMEngine.shared.getDownloadedModels()
            isLoading = false
        }
    }

    private func loadModel(_ model: DownloadedModelInfo) {
        Task {
            do {
                let llmModel = LLMModel(
                    name: model.name,
                    displayName: model.name.replacingOccurrences(of: "-", with: " ").capitalized,
                    path: model.path,
                    contextLength: model.contextLength,
                    description: "Downloaded model"
                )
                try await LLMEngine.shared.loadModel(llmModel)
                appState.currentModel = llmModel
                appState.saveSettings()
                isModelLoaded = true
                await appState.updateModelState()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func deleteModel(_ model: DownloadedModelInfo) {
        Task {
            if appState.currentModel.path == model.path && isModelLoaded {
                await LLMEngine.shared.unloadModel()
                isModelLoaded = false
            }
            try? await LLMEngine.shared.deleteModel(at: model.path)
            loadModels()
        }
    }

    private func downloadModel() {
        guard !modelName.isEmpty else { return }
        isDownloading = true

        Task {
            do {
                let model = try await LLMEngine.shared.downloadModel(modelName: modelName) { progress, status in
                    Task { @MainActor in
                        downloadProgress = progress
                        downloadStatus = status
                    }
                }
                isDownloading = false
                loadModels()
                appState.currentModel = model
                appState.saveSettings()
            } catch {
                isDownloading = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Generation Settings

struct GenerationSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                temperatureCard

                maxTokensCard

                presetsCard
            }
            .padding()
        }
    }

    private var temperatureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Temperature", systemImage: "thermometer.medium")
                .font(.headline)

            VStack(spacing: 8) {
                HStack {
                    Text("Precise")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $appState.temperature, in: 0.0...1.5, step: 0.1)
                    Text("Creative")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Current:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(appState.temperature, specifier: "%.1f")")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()

                    if appState.temperature < 0.4 {
                        Text("precise")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(Capsule())
                    } else if appState.temperature > 1.0 {
                        Text("creative")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    } else {
                        Text("balanced")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding()
        .cardBackground()
        .onChange(of: appState.temperature) { _, _ in appState.saveSettings() }
    }

    private var maxTokensCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Max Tokens", systemImage: "text.alignleft")
                .font(.headline)

            Stepper(value: $appState.maxTokens, in: 256...8192, step: 256) {
                HStack {
                    Text("Max Tokens:")
                    Text("\(appState.maxTokens)")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
            }
        }
        .padding()
        .cardBackground()
        .onChange(of: appState.maxTokens) { _, _ in appState.saveSettings() }
    }

    private var presetsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Quick Presets", systemImage: "bolt")
                    .font(.headline)

                HStack(spacing: 12) {
                    presetButton(title: "Precise", icon: "arrow.down.right", temp: 0.3, tokens: 1024)
                    presetButton(title: "Balanced", icon: "scale.3d", temp: 0.7, tokens: 2048)
                    presetButton(title: "Creative", icon: "sparkles", temp: 1.2, tokens: 4096)
                }
            }
            .padding()
            .cardBackground()

            displayOptionsCard
        }
    }

    private var displayOptionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Display Options", systemImage: "eye")
                .font(.headline)

            Toggle(isOn: $appState.showMessageMetadata) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show message metadata on hover")
                        .font(.subheadline)
                    Text("Displays timestamp and model name when hovering over messages")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)

            Toggle(isOn: $appState.showPerformanceMetrics) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show performance metrics")
                        .font(.subheadline)
                    Text("Displays token count and generation speed after model replies")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
        .padding()
        .cardBackground()
        .onChange(of: appState.showMessageMetadata) { _, _ in
            appState.saveSettings()
        }
        .onChange(of: appState.showPerformanceMetrics) { _, _ in
            appState.saveSettings()
        }
    }

    private func presetButton(title: String, icon: String, temp: Double, tokens: Int) -> some View {
        let isActive = abs(appState.temperature - temp) < 0.05 && appState.maxTokens == tokens

        return Button(action: {
            appState.temperature = temp
            appState.maxTokens = tokens
        }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundColor(isActive ? .accentColor : .primary)
    }
}

// MARK: - Brain Settings

struct BrainSettingsView: View {
    @State private var brainPath: String = "Loading..."
    @State private var memoryStats: BrainSystem.MemoryStats?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                storageCard

                statsCard

                contextCard
            }
            .padding()
        }
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Storage Location", systemImage: "folder")
                .font(.headline)

            HStack {
                Image(systemName: "path")
                    .foregroundColor(.secondary)

                Text(brainPath)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Open Folder") {
                    Task {
                        if let path = await BrainSystem.shared.brainDirectory {
                            await MainActor.run {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path)
                            }
                        }
                    }
                }
                .buttonStyle(.bordered)
                .help("Open the brain storage folder")
            }
        }
        .padding()
        .cardBackground()
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Memory Statistics", systemImage: "chart.bar")
                .font(.headline)

            if let stats = memoryStats {
                HStack(spacing: 20) {
                    statItem(value: "\(stats.totalMemories)", label: "Total", icon: "brain")
                    statItem(value: String(format: "%.1f", stats.averageImportance), label: "Avg Importance", icon: "star")
                }

                Divider()

                ForEach(Array(stats.byCategory.keys.sorted()), id: \.self) { category in
                    HStack {
                        Text(category.capitalized)
                            .font(.caption)
                        Spacer()
                        Text("\(stats.byCategory[category] ?? 0)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                HStack {
                    ProgressView()
                    Text("Loading statistics...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .cardBackground()
        .task {
            await loadStats()
        }
    }

    private func statItem(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Context Settings", systemImage: "slider.horizontal.3")
                .font(.headline)

            Toggle("Include memory in all conversations", isOn: .constant(true))
            Toggle("Build deep context links", isOn: .constant(true))
            Stepper("Max memories in context: 10", value: .constant(10), in: 5...50)
        }
        .padding()
        .cardBackground()
    }

    private func loadStats() async {
        brainPath = await BrainSystem.shared.brainDirectory?.path ?? "Not initialized"
        memoryStats = await BrainSystem.shared.getStatistics()
    }
}

// MARK: - About View

struct AboutView: View {
    @State private var iconPulse = false
    @State private var rotation: Double = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                iconSection

                identitySection

                Divider()

                builtWithSection

                Spacer()

                privacyNote
            }
            .padding()
        }
    }

    private var iconSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(FridayTheme.accentGradient)
                    .frame(width: 90, height: 90)
                    .scaleEffect(iconPulse ? 1.08 : 1.0)
                    .animation(
                        .easeInOut(duration: 2.5).repeatForever(autoreverses: true),
                        value: iconPulse
                    )

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundColor(.white)
            }
            .shadow(color: Color.accentColor.opacity(0.3), radius: 20, x: 0, y: 8)

            VStack(spacing: 4) {
                Text("Friday")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Local AI Assistant")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Version 1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .onAppear { iconPulse = true }
    }

    private var identitySection: some View {
        VStack(spacing: 8) {
            Text("Your AI assistant that runs entirely on your machine.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                featurePill(icon: "lock.shield", text: "Private")
                featurePill(icon: "cpu", text: "Local MLX")
                featurePill(icon: "brain", text: "Persistent Memory")
            }
        }
    }

    private func featurePill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundColor(.accentColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private var builtWithSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Built with")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                techRow(icon: "swift", name: "Swift", desc: "Native macOS framework")
                techRow(icon: "cpu", name: "MLX", desc: "Apple's ML framework")
                techRow(icon: "memorychip", name: "Apple Silicon", desc: "Optimized for M-series chips")
            }
        }
    }

    private func techRow(icon: String, name: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var privacyNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield")
                .font(.caption)
            Text("All data stays on your machine. Always.")
                .font(.caption)
        }
        .foregroundColor(.secondary)
    }
}

// MARK: - System Status View

struct SystemStatusView: View {
    @State private var systemInfo: SystemInfo?
    @State private var modelLoaded: Bool = false
    @State private var currentModel: LLMModel?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                systemCard

                pathsCard

                memoryCard

                modelCard
            }
            .padding()
        }
    }

    private var systemCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("System", systemImage: "desktopcomputer")
                .font(.headline)

            if let info = systemInfo {
                gridLayout([
                    ("Computer", info.computerName),
                    ("User", info.currentUser),
                    ("CPU Cores", "\(info.cpuCount)")
                ])
            } else {
                Text("Loading...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .cardBackground()
    }

    private var pathsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Paths", systemImage: "folder")
                .font(.headline)

            if let info = systemInfo {
                gridLayout([
                    ("Home", info.homeDirectory),
                    ("Working", info.workingDirectory)
                ])
            }
        }
        .padding()
        .cardBackground()
    }

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Memory", systemImage: "memorychip")
                .font(.headline)

            if let info = systemInfo {
                gridLayout([
                    ("Available", formatBytes(info.availableMemory)),
                    ("Total", formatBytes(ProcessInfo.processInfo.physicalMemory))
                ])

                memoryBar(available: info.availableMemory, total: ProcessInfo.processInfo.physicalMemory)
            }
        }
        .padding()
        .cardBackground()
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Model Status", systemImage: "cpu")
                .font(.headline)

            HStack {
                Circle()
                    .fill(modelLoaded ? Color.green : Color.red)
                    .frame(width: 10, height: 10)

                Text(modelLoaded ? "Model Loaded" : "No Model Loaded")
                    .font(.subheadline)

                Spacer()

                Text(currentModel?.displayName ?? "None")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .cardBackground()
        .task {
            systemInfo = await SystemIntegration.shared.getSystemInfo()
            modelLoaded = await LLMEngine.shared.isModelLoaded()
            currentModel = await LLMEngine.shared.getCurrentModel()
        }
    }

    private func gridLayout(_ items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.0) { label, value in
                HStack {
                    Text(label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(value)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
    }

    private func memoryBar(available: UInt64, total: UInt64) -> some View {
        let used = total - available
        let fraction = Double(used) / Double(total)

        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.green, .yellow, .red].prefix(1 + Int(fraction * 2)).map { $0 },
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)

            HStack {
                Text("Used: \(formatBytes(used))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Total: \(formatBytes(total))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}