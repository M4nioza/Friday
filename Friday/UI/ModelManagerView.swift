import SwiftUI

/// Model manager view for downloading, deleting, and selecting models
struct ModelManagerView: View {
    @EnvironmentObject var appState: AppState
    @State private var downloadedModels: [DownloadedModel] = []
    @State private var isLoading = true
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadStatus = ""
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: DownloadedModel?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isModelLoaded = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Model Manager")
                    .font(.headline)
                Spacer()
                Button(action: loadModels) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 8)
            
            // Current model status
            if let model = appState.currentModel as? LLMModel {
                HStack {
                    Image(systemName: isModelLoaded ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(isModelLoaded ? .green : .gray)
                    Text("Current: \(model.displayName)")
                        .font(.subheadline)
                    Spacer()
                    if isModelLoaded {
                        Button("Unload Model") {
                            unloadModel()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
            
            // Download section
            DownloadModelSection(
                isDownloading: $isDownloading,
                downloadProgress: $downloadProgress,
                downloadStatus: $downloadStatus,
                onDownload: downloadModel,
                onError: { msg in
                    errorMessage = msg
                    showError = true
                }
            )
            
            // Error banner
            if showError, let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button(action: { showError = false }) {
                        Image(systemName: "xmark")
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Download progress
            if isDownloading {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Downloading...")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(.linear)
                    
                    Text(downloadStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            Divider()
            
            // Downloaded models label
            HStack {
                Text("Downloaded Models")
                    .font(.headline)
                Spacer()
            }
            .padding(.top, 8)
            
            // Downloaded models list
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Loading models...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if downloadedModels.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "cpu")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No Models Downloaded")
                        .font(.headline)
                    
                    Text("Enter a model name above to download")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(downloadedModels) { model in
                        DownloadedModelRowView(
                            model: model,
                            isLoaded: appState.currentModel.path == model.path && isModelLoaded,
                            onLoad: { loadModel(model) },
                            onUnload: { unloadModel() },
                            onDelete: { confirmDelete(model) }
                        )
                    }
                }
                .listStyle(.inset)
            }
            
            // Storage info
            HStack {
                Image(systemName: "internaldrive")
                    .foregroundColor(.secondary)
                Text("Storage: \(totalStorageUsed)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("~/.cache/mlx-model/models")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
        .padding()
        .alert("Delete Model?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteModel()
            }
        } message: {
            if let model = modelToDelete {
                Text("Are you sure you want to delete '\(model.name)'? This will free \(model.formattedSize) of storage.")
            }
        }
        .task {
            loadModels()
            await checkModelLoaded()
        }
    }
    
    private var totalStorageUsed: String {
        let total = downloadedModels.reduce(0) { $0 + $1.sizeInBytes }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: total)
    }
    
    private func loadModels() {
        isLoading = true
        Task {
            downloadedModels = await LLMEngine.shared.getDownloadedModels()
            isLoading = false
            await checkModelLoaded()
        }
    }
    
    private func checkModelLoaded() async {
        isModelLoaded = await LLMEngine.shared.isModelLoaded()
    }
    
    private func loadModel(_ model: DownloadedModel) {
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
    
    private func unloadModel() {
        Task {
            await LLMEngine.shared.unloadModel()
            isModelLoaded = false
        }
    }
    
    private func confirmDelete(_ model: DownloadedModel) {
        modelToDelete = model
        showDeleteConfirmation = true
    }
    
    private func deleteModel() {
        guard let model = modelToDelete else { return }
        
        // Unload if this is the current model
        if appState.currentModel.path == model.path && isModelLoaded {
            unloadModel()
        }
        
        Task {
            do {
                try await LLMEngine.shared.deleteModel(at: model.path)
                loadModels()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            modelToDelete = nil
        }
    }
    
    private func downloadModel(_ modelName: String) {
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
                
                // Auto-select the newly downloaded model
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

/// Download model section with text input
struct DownloadModelSection: View {
    @Binding var isDownloading: Bool
    @Binding var downloadProgress: Double
    @Binding var downloadStatus: String
    let onDownload: (String) -> Void
    let onError: (String) -> Void
    
    @State private var modelName: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Download Model")
                .font(.headline)
            
            HStack(spacing: 12) {
                TextField("e.g., Llama-3.2-1B-Instruct or mlx-community/Llama-3.2-1B-Instruct", text: $modelName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
                    .disabled(isDownloading)
                    .onSubmit {
                        if !modelName.isEmpty {
                            onDownload(modelName)
                        }
                    }
                
                Button(action: {
                    onDownload(modelName)
                }) {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(modelName.isEmpty || isDownloading)
            }
            
            Text("Enter the model name from HuggingFace mlx-community. Examples: Llama-3.2-1B-Instruct, Phi-3.5-mini-instruct, Mistral-7B-Instruct-v0.2")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

/// Row view for a downloaded model
struct DownloadedModelRowView: View {
    let model: DownloadedModel
    let isLoaded: Bool
    let onLoad: () -> Void
    let onUnload: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.headline)
                
                HStack(spacing: 12) {
                    Label("\(model.contextLength / 1024)k ctx", systemImage: "text.alignleft")
                    Label(model.formattedSize, systemImage: "doc")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isLoaded {
                HStack(spacing: 8) {
                    Label("Loaded", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    Button(action: onUnload) {
                        Image(systemName: "stop.circle")
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Unload model")
                }
            } else {
                Button(action: onLoad) {
                    Label("Load", systemImage: "play.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }
            
            if isHovering || !isLoaded {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
