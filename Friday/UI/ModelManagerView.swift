import SwiftUI

/// Model manager view for downloading, deleting, and selecting models
struct ModelManagerView: View {
    @EnvironmentObject var appState: AppState
    @State private var downloadedModels: [DownloadedModel] = []
    @State private var availableModels: [HuggingFaceModel] = []
    @State private var isLoading = true
    @State private var isLoadingOnline = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadStatus = ""
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: DownloadedModel?
    @State private var searchText = ""
    @State private var selectedCategory: HuggingFaceModel.ModelCategory?
    @State private var showOnlineModels = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Model Manager")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { showOnlineModels = true }) {
                    Label("Browse Online", systemImage: "globe")
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: loadModels) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 8)
            
            // System memory info
            HStack {
                Image(systemName: "memorychip")
                    .foregroundColor(.secondary)
                Text("Available Memory: \(formatMemory(availableMemory))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.bottom, 8)
            
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
                    
                    Text("Browse online models to download one")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Browse Models") {
                        showOnlineModels = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(downloadedModels) { model in
                        DownloadedModelRowView(
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
        .sheet(isPresented: $showOnlineModels) {
            OnlineModelsSheet(
                models: availableModels,
                isLoading: isLoadingOnline,
                searchText: $searchText,
                selectedCategory: $selectedCategory,
                onDownload: downloadModel,
                onRefresh: loadOnlineModels,
                onClose: { showOnlineModels = false }
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
            await loadAll()
        }
    }
    
    private var availableMemory: UInt64 {
        Foundation.ProcessInfo.processInfo.physicalMemory
    }
    
    private var totalStorageUsed: String {
        let total = downloadedModels.reduce(0) { $0 + $1.sizeInBytes }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: total)
    }
    
    private func loadAll() async {
        isLoading = true
        downloadedModels = await LLMEngine.shared.getDownloadedModels()
        isLoading = false
        await loadOnlineModels()
    }
    
    private func loadModels() {
        isLoading = true
        Task {
            downloadedModels = await LLMEngine.shared.getDownloadedModels()
            isLoading = false
        }
    }
    
    private func loadOnlineModels() async {
        isLoadingOnline = true
        do {
            availableModels = try await LLMEngine.shared.fetchAvailableModels()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoadingOnline = false
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
    
    private func downloadModel(_ hfModel: HuggingFaceModel) {
        isDownloading = true
        showOnlineModels = false
        
        Task {
            do {
                let model = try await LLMEngine.shared.downloadModel(modelId: hfModel.id) { progress, status in
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
    
    private func formatMemory(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// Row view for a downloaded model
struct DownloadedModelRowView: View {
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
                    Label("\(model.contextLength / 1024)k ctx", systemImage: "text.alignleft")
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

/// Sheet for browsing and downloading online models
struct OnlineModelsSheet: View {
    let models: [HuggingFaceModel]
    let isLoading: Bool
    @Binding var searchText: String
    @Binding var selectedCategory: HuggingFaceModel.ModelCategory?
    let onDownload: (HuggingFaceModel) -> Void
    let onRefresh: () async -> Void
    let onClose: () -> Void
    
    var filteredModels: [HuggingFaceModel] {
        var result = models
        
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }
        
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.id.lowercased().contains(query)
            }
        }
        
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Browse Models")
                    .font(.headline)
                Spacer()
                Button(action: {
                    Task { await onRefresh() }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
            }
            .padding()
            
            // Search and filter
            VStack(spacing: 12) {
                TextField("Search models...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                
                // Category filter
                HStack {
                    FilterButton(
                        title: "All",
                        isSelected: selectedCategory == nil,
                        action: { selectedCategory = nil }
                    )
                    
                    FilterButton(
                        title: "Vision",
                        isSelected: selectedCategory == .vision,
                        action: { selectedCategory = .vision }
                    )
                    
                    FilterButton(
                        title: "Instruct",
                        isSelected: selectedCategory == .instruct,
                        action: { selectedCategory = .instruct }
                    )
                    
                    FilterButton(
                        title: "Text",
                        isSelected: selectedCategory == .text,
                        action: { selectedCategory = .text }
                    )
                    
                    Spacer()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
            
            Divider()
            
            // Model list
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Loading models from HuggingFace...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredModels.isEmpty {
                VStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No models found")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredModels) { model in
                            OnlineModelRowView(model: model, onDownload: onDownload)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 600, height: 500)
    }
}

/// Filter button
struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .task {
            // No-op to make it compatible
        }
    }
}

/// Row view for an online model
struct OnlineModelRowView: View {
    let model: HuggingFaceModel
    let onDownload: (HuggingFaceModel) -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: model.category.icon)
                        .foregroundColor(.blue)
                        .font(.caption)
                    
                    Text(model.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(model.category.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }
                
                Text(model.id)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 16) {
                    Label(model.formattedDownloads, systemImage: "arrow.down.circle")
                    Label(model.formattedSize, systemImage: "doc")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { onDownload(model) }) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}
