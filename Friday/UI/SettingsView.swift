import SwiftUI

/// Settings panel
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        TabView {
            // Model Settings
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
        .frame(width: 500, height: 400)
        .padding()
    }
}

/// Model selection and configuration
struct ModelSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ModelManagerView()
    }
}

/// Available models list
struct AvailableModelsView: View {
    @State private var availableModels: [URL] = []
    
    var body: some View {
        Group {
            if availableModels.isEmpty {
                Text("No models found in ~/.cache/mlx-model/models")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(availableModels, id: \.self) { url in
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            Task {
                availableModels = await LLMEngine.shared.getAvailableModels()
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
                }
                
                Section("Model Status") {
                    LabeledContent("Model Loaded", value: modelLoaded ? "Yes" : "No")
                    LabeledContent("Current Model", value: currentModel?.displayName ?? "None")
                }
                
                Section("Running Apps") {
                    let apps = SystemIntegration.shared.getRunningApplications()
                    ForEach(apps.prefix(10)) { app in
                        Text(app.name)
                            .font(.caption)
                    }
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
