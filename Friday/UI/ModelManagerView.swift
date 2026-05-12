import SwiftUI

/// Model manager view for downloading, deleting, and selecting models
struct ModelManagerView: View {
    @EnvironmentObject var appState: AppState
    @State private var downloadedModels: [DownloadedModel] = []
    @State private var isLoading = true
    @State private var showDownloadSheet = false
    @State private var downloadURL = ""
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadStatus = ""
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: DownloadedModel?
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Model Manager")
                    .font(.headline)
                Spacer()
                Button(action: { showDownloadSheet = true }) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDownloading)
                
                Button(action: loadModels) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 8)
            
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
                    
                    Text("Download a model from HuggingFace to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Download Model") {
                        showDownloadSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(downloadedModels) { model in
                        ModelRowView(
                            model: model,
                            isSelected: appState.currentModel.path == model.path,
                            onSelect: { selectModel(model) },
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
        .sheet(isPresented: $showDownloadSheet) {
            DownloadModelSheet(
                url: $downloadURL,
                isDownloading: $isDownloading,
                onDownload: startDownload,
                onCancel: { showDownloadSheet = false }
            )
        }
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
        }
    }
    
    private func selectModel(_ model: DownloadedModel) {
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
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func confirmDelete(_ model: DownloadedModel) {
        modelToDelete = model
        showDeleteConfirmation = true
    }
    
    private func deleteModel() {
        guard let model = modelToDelete else { return }
        
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
    
    private func startDownload() {
        guard let url = URL(string: downloadURL), !downloadURL.isEmpty else {
            errorMessage = "Please enter a valid HuggingFace URL"
            showError = true
            return
        }
        
        isDownloading = true
        showDownloadSheet = false
        
        Task {
            do {
                let model = try await LLMEngine.shared.downloadModel(from: url) { progress, status in
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

/// Row view for a downloaded model
struct ModelRowView: View {
    let model: DownloadedModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.headline)
                
                HStack(spacing: 12) {
                    Label("\(model.contextLength)k ctx", systemImage: "text.alignleft")
                    Label(model.formattedSize, systemImage: "doc")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            
            if isHovering || isSelected {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

/// Sheet for downloading a new model
struct DownloadModelSheet: View {
    @Binding var url: String
    @Binding var isDownloading: Bool
    let onDownload: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Download Model")
                    .font(.headline)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            
            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                Text("Enter a HuggingFace mlx-community URL")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Label("Text instruct models (Llama, Mistral, Phi, Qwen, Gemma...)", systemImage: "doc.text")
                    Label("Vision instruct models (for image understanding)", systemImage: "photo")
                    Label("Any MLX-compatible model from HuggingFace", systemImage: "cpu")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            
            // URL Input
            VStack(alignment: .leading, spacing: 8) {
                Text("Model URL")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("https://huggingface.co/mlx-community/...", text: $url)
                    .textFieldStyle(.roundedBorder)
                
                Text("Use mlx-community variants for Apple Silicon optimization")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Download button
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Download", action: onDownload)
                    .buttonStyle(.borderedProminent)
                    .disabled(url.isEmpty || isDownloading)
            }
        }
        .padding()
        .frame(width: 450, height: 300)
    }
}
