import SwiftUI

struct ModelManagerView: View {
    @EnvironmentObject var appState: AppState
    @State private var downloadedModels: [DownloadedModelInfo] = []
    @State private var isLoading = true
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadStatus = ""
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: DownloadedModelInfo?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isModelLoaded = false
    @State private var modelName: String = ""

    var body: some View {
        VStack(spacing: 16) {
            header

            ScrollView {
                VStack(spacing: 16) {
                    currentModelSection

                    downloadSection

                    if showError, let error = errorMessage {
                        errorBanner(error)
                    }

                    if isDownloading {
                        downloadProgressSection
                    }

                    downloadedModelsSection
                }
                .padding()
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .alert("Delete Model?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteModel() }
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

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Model Manager")
                    .font(.headline)

                Text("Download and manage MLX models")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: loadModels) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("Refresh")
        }
    }

    private var currentModelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(isModelLoaded ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Model")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(appState.currentModel.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Spacer()

                if isModelLoaded {
                    Label("Loaded", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)

                    Button(action: unloadModel) {
                        Image(systemName: "stop.circle")
                            .font(.title3)
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Unload model")
                }
            }
        }
        .padding()
        .cardBackground()
    }

    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Download Model", systemImage: "arrow.down.circle")
                .font(.headline)

            HStack(spacing: 12) {
                TextField("e.g., Llama-3.2-1B-Instruct", text: $modelName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isDownloading)

                Button(action: { downloadModel(modelName) }) {
                    if isDownloading {
                        ProgressView()
                    } else {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(modelName.isEmpty || isDownloading)
            }

            Text("Enter the model name from HuggingFace mlx-community. Examples: Llama-3.2-1B-Instruct, Phi-3.5-mini-instruct, Mistral-7B-Instruct-v0.2")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .cardBackground()
    }

    private func errorBanner(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text(error)
                .font(.caption)

            Spacer()

            Button(action: { showError = false }) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var downloadProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Downloading...")
                    .font(.subheadline)

                Spacer()

                Text("\(Int(downloadProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            animatedProgressBar

            Text(downloadStatus)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var animatedProgressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))

                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * downloadProgress)
                    .animation(.easeInOut(duration: 0.3), value: downloadProgress)
            }
        }
        .frame(height: 8)
    }

    private var downloadedModelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Downloaded Models", systemImage: "folder")
                    .font(.headline)

                Spacer()

                Text(totalStorageUsed)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if isLoading {
                HStack {
                    ProgressView()
                    Text("Loading models...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else if downloadedModels.isEmpty {
                emptyModelsState
            } else {
                ForEach(downloadedModels) { model in
                    modelCard(model)
                }
            }
        }
        .padding()
        .cardBackground()
    }

    private var emptyModelsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 36))
                .foregroundColor(.secondary)

            Text("No Models Downloaded")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("Enter a model name above to download")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func modelCard(_ model: DownloadedModelInfo) -> some View {
        let isLoaded = appState.currentModel.path == model.path && isModelLoaded
        @State var isHovered = false

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    HStack(spacing: 12) {
                        Label("\(model.contextLength / 1024)k ctx", systemImage: "text.alignleft")
                        Label(model.formattedSize, systemImage: "doc")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    if isLoaded {
                        Label("Loaded", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)

                        Button(action: unloadModel) {
                            Image(systemName: "stop.circle")
                                .font(.title3)
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: { loadModel(model) }) {
                            Label("Load", systemImage: "play.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }

                    Button(action: { confirmDelete(model) }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered || !isLoaded ? 1 : 0)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var totalStorageUsed: String {
        let total = downloadedModels.reduce(0) { $0 + $1.sizeInBytes }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "Total: \(formatter.string(fromByteCount: total))"
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
                await appState.updateModelState()
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
            await appState.updateModelState()
            isModelLoaded = false
        }
    }

    private func confirmDelete(_ model: DownloadedModelInfo) {
        modelToDelete = model
        showDeleteConfirmation = true
    }

    private func deleteModel() {
        guard let model = modelToDelete else { return }

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

// MARK: - Download Model Section (Standalone)

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

                Button(action: { onDownload(modelName) }) {
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
        .cardBackground()
    }
}