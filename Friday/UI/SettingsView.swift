import SwiftUI

/// Settings panel
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        TabView {
            // System Information
            SystemStatusView()
                .tabItem {
                    Label("System", systemImage: "desktopcomputer")
                }
            
            // Model Settings - separate tab with model management
            ModelSettingsView()
                .tabItem {
                    Label("Model", systemImage: "cpu")
                }
            
            // Generation Settings
            GenerationSettingsView()
                .tabItem {
                    Label("Generation", systemImage: "slider.horizontal.3")
                }
            
            // Brain Settings
            BrainSettingsView()
                .tabItem {
                    Label("Memory", systemImage: "brain")
                }
            
            // About
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 550, height: 500)
        .padding()
    }
}

/// Model selection and configuration - separate view for the tab
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
                // Current model status
                HStack {
                    Image(systemName: isModelLoaded ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(isModelLoaded ? .green : .gray)
                    if let model = appState.currentModel as? LLMModel {
                        Text("Current: \(model.displayName)")
                            .font(.subheadline)
                    } else {
                        Text("No model selected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if isModelLoaded {
                        Button("Unload") {
                            Task {
                                await LLMEngine.shared.unloadModel()
                                isModelLoaded = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                
                // Download section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Download Model")
                        .font(.headline)
                    
                    HStack {
                        TextField("Model name (e.g., Llama-3.2-1B-Instruct)", text: $modelName)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isDownloading)
                        
                        Button(action: downloadModel) {
                            if isDownloading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Label("Download", systemImage: "arrow.down.circle.fill")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(modelName.isEmpty || isDownloading)
                    }
                    
                    if isDownloading {
                        ProgressView(value: downloadProgress)
                        Text(downloadStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Enter model name from HuggingFace mlx-community")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                
                // Downloaded models
                HStack {
                    Text("Downloaded Models")
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
                        Text("Loading models...")
                    }
                } else if downloadedModels.isEmpty {
                    Text("No models downloaded yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(downloadedModels) { model in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name)
                                    .font(.subheadline)
                                Text(model.formattedSize)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            let isLoaded = appState.currentModel.path == model.path && isModelLoaded
                            
                            if isLoaded {
                                Label("Loaded", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                
                                Button(action: {
                                    Task {
                                        await LLMEngine.shared.unloadModel()
                                        isModelLoaded = false
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
                }
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

/// Generation parameters
struct GenerationSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Form {
            Section("Temperature") {
                VStack(alignment: .leading) {
                    Slider(value: $appState.temperature, in: 0.0...1.5, step: 0.1) {
                        Text("Temperature")
                    }
                    Text("\(appState.temperature, specifier: "%.1f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("Precise")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Creative")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section("Max Tokens") {
                Stepper(value: $appState.maxTokens, in: 256...8192, step: 256) {
                    HStack {
                        Text("Max Tokens:")
                        Text("\(appState.maxTokens)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section("Presets") {
                HStack {
                    Button("Precise") {
                        appState.temperature = 0.3
                        appState.maxTokens = 1024
                    }
                    Button("Balanced") {
                        appState.temperature = 0.7
                        appState.maxTokens = 2048
                    }
                    Button("Creative") {
                        appState.temperature = 1.2
                        appState.maxTokens = 4096
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: appState.temperature) { _, _ in
            appState.saveSettings()
        }
        .onChange(of: appState.maxTokens) { _, _ in
            appState.saveSettings()
        }
    }
}

/// Brain/memory settings
struct BrainSettingsView: View {
    @State private var brainPath: String = "Loading..."
    @State private var memoryStats: BrainSystem.MemoryStats?
    
    var body: some View {
        Form {
            Section("Storage Location") {
                Text(brainPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Open Brain Folder") {
                    Task {
                        if let path = await BrainSystem.shared.brainDirectory {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path)
                        }
                    }
                }
            }
            
            Section("Memory Statistics") {
                if let stats = memoryStats {
                    LabeledContent("Total Memories", value: "\(stats.totalMemories)")
                    LabeledContent("Average Importance", value: String(format: "%.1f", stats.averageImportance))
                    
                    ForEach(Array(stats.byCategory.keys.sorted()), id: \.self) { category in
                        LabeledContent(category.capitalized, value: "\(stats.byCategory[category] ?? 0)")
                    }
                } else {
                    Text("Loading statistics...")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Context Settings") {
                Toggle("Include memory in all conversations", isOn: .constant(true))
                Toggle("Build deep context links", isOn: .constant(true))
                Stepper("Max memories in context: 10", value: .constant(10), in: 5...50)
            }
        }
        .formStyle(.grouped)
        .task {
            await loadStats()
        }
    }
    
    private func loadStats() async {
        brainPath = await BrainSystem.shared.brainDirectory?.path ?? "Not initialized"
        memoryStats = await BrainSystem.shared.getStatistics()
    }
}

/// About section
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue.gradient)
                
                Text("Friday")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Local AI Assistant")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("Version 1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Built with:")
                        .font(.headline)
                    
                    HStack {
                        Image(systemName: "swift")
                        Text("Swift")
                        Spacer()
                        Text("UI Framework")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "cpu")
                        Text("MLX")
                        Spacer()
                        Text("Local LLM Inference")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "memorychip")
                        Text("Apple Silicon")
                        Spacer()
                        Text("M-Series Optimization")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.caption)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                
                Spacer()
                
                Text("All data stays on your machine.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }
}

/// System status view
struct SystemStatusView: View {
    @State private var systemInfo: SystemInfo?
    @State private var modelLoaded: Bool = false
    @State private var currentModel: LLMModel?
    
    var body: some View {
        Form {
            if let info = systemInfo {
                Section("System") {
                    LabeledContent("Computer Name", value: info.computerName)
                    LabeledContent("User", value: info.currentUser)
                    LabeledContent("CPU Cores", value: "\(info.cpuCount)")
                }
                
                Section("Paths") {
                    LabeledContent("Home", value: info.homeDirectory)
                    LabeledContent("Working Directory", value: info.workingDirectory)
                }
                
                Section("Memory") {
                    LabeledContent("Available", value: formatBytes(info.availableMemory))
                    LabeledContent("Total", value: formatBytes(ProcessInfo.processInfo.physicalMemory))
                }
                
                Section("Model Status") {
                    LabeledContent("Model Loaded", value: modelLoaded ? "Yes" : "No")
                    LabeledContent("Current Model", value: currentModel?.displayName ?? "None")
                }
            } else {
                Text("Loading system information...")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            systemInfo = await SystemIntegration.shared.getSystemInfo()
            modelLoaded = await LLMEngine.shared.isModelLoaded()
            currentModel = await LLMEngine.shared.getCurrentModel()
        }
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
