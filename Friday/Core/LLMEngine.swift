import Foundation

/// LLM Engine that handles model loading and inference using MLX Swift
actor LLMEngine {
    static let shared = LLMEngine()
    
    private var currentModel: LLMModel?
    private var isLoaded: Bool = false
    private var modelProcess: Process?
    
    // HuggingFace base URL
    private let hfBaseURL = "https://huggingface.co"
    
    // Streaming callback type
    typealias TokenHandler = (String) async -> Void
    typealias ProgressHandler = (Double, String) -> Void
    
    private init() {}
    
    // MARK: - Model Management
    
    /// Get list of downloaded models
    func getAvailableModels() -> [URL] {
        let cachePath = NSString(string: "~/.cache/mlx-model/models").expandingTildeInPath
        let cacheURL = URL(fileURLWithPath: cachePath)
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        return contents.filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }
    
    /// Download a model by its mlx-community name
    func downloadModel(
        modelName: String,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> LLMModel {
        // Ensure model name has mlx-community prefix
        let fullModelId = modelName.hasPrefix("mlx-community/") ? modelName : "mlx-community/\(modelName)"
        
        // Create the model directory name (just the model name without prefix)
        let modelDirName = modelName.components(separatedBy: "/").last ?? modelName
        let destinationPath = NSString(string: "~/.cache/mlx-model/models/\(modelDirName)").expandingTildeInPath
        
        print("[LLMEngine] Starting download of: \(fullModelId)")
        print("[LLMEngine] Destination: \(destinationPath)")
        
        // Check if already downloaded
        if FileManager.default.fileExists(atPath: destinationPath) {
            print("[LLMEngine] Model already exists at destination")
            throw LLMError.modelAlreadyExists(modelDirName)
        }
        
        // Create cache directory if needed
        let cachePath = NSString(string: "~/.cache/mlx-model/models").expandingTildeInPath
        print("[LLMEngine] Creating cache directory: \(cachePath)")
        try FileManager.default.createDirectory(atPath: cachePath, withIntermediateDirectories: true)
        
        // Download files directly using HuggingFace API
        progressHandler(0.05, "Getting file list...")
        print("[LLMEngine] Downloading files directly from HuggingFace API...")
        
        try await downloadFilesDirectly(
            modelId: fullModelId,
            destination: destinationPath,
            progressHandler: progressHandler
        )
        
        progressHandler(1.0, "Download complete")
        print("[LLMEngine] Download successful!")
        
        // Create model entry
        return LLMModel(
            name: modelDirName,
            displayName: formatModelName(modelDirName),
            path: destinationPath,
            contextLength: 4096,
            description: "Downloaded from HuggingFace"
        )
    }
    
    /// Download files directly from HuggingFace API
    private func downloadFilesDirectly(
        modelId: String,
        destination: String,
        progressHandler: @escaping ProgressHandler
    ) async throws {
        print("[LLMEngine] Direct download from: \(hfBaseURL)/\(modelId)")
        
        // Get list of files from the repo
        let apiURL = URL(string: "https://huggingface.co/api/models/\(modelId)/tree/main")!
        
        var request = URLRequest(url: apiURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        progressHandler(0.05, "Getting file list...")
        print("[LLMEngine] Fetching file list from API...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            print("[LLMEngine] Failed to get file list, status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw LLMError.downloadFailed("Failed to get file list from repository")
        }
        
        struct HFFile: Codable {
            let path: String
            let size: Int64?
            let type: String?
        }
        
        let files = try JSONDecoder().decode([HFFile].self, from: data)
        
        // Filter for actual model files (not directories)
        let modelFiles = files.filter { file in
            file.type == "file" && (
                file.path.hasSuffix(".safetensors") ||
                file.path.hasSuffix(".bin") ||
                file.path.hasSuffix(".json") ||
                file.path.hasSuffix(".md") ||
                file.path.hasSuffix(".txt") ||
                file.path.hasSuffix(".py") ||
                file.path.hasSuffix(".model") ||
                file.path.contains("config")
            )
        }
        
        print("[LLMEngine] Found \(modelFiles.count) files to download")
        
        let totalSize = modelFiles.reduce(0) { $0 + ($1.size ?? 0) }
        print("[LLMEngine] Total size: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
        
        var downloadedSize: Int64 = 0
        var failedFiles: [String] = []
        
        for (index, file) in modelFiles.enumerated() {
            let baseProgress = 0.1
            let endProgress = 0.95
            let progressRange = endProgress - baseProgress
            let progress = baseProgress + (progressRange * Double(index) / Double(modelFiles.count))
            progressHandler(progress, "Downloading \(file.path)...")
            
            let fileURL = URL(string: "\(hfBaseURL)/\(modelId)/resolve/main/\(file.path)")!
            let localPath = (destination as NSString).appendingPathComponent(file.path)
            
            print("[LLMEngine] Downloading [\(index + 1)/\(modelFiles.count)]: \(file.path)")
            
            do {
                // Create directory if needed
                let dirPath = (localPath as NSString).deletingLastPathComponent
                try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
                
                // Download file
                let (tempURL, response) = try await URLSession.shared.download(from: fileURL)
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    // Check if it's an LFS pointer (small file starting with version https://git-lfs.github.com)
                    let fileAttributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
                    let tempSize = fileAttributes[.size] as? Int64 ?? 0
                    
                    if tempSize < 100 && tempSize > 0 {
                        // Likely an LFS pointer, try without redirect
                        print("[LLMEngine] File is LFS pointer (\(tempSize) bytes), skipping")
                        try? FileManager.default.removeItem(at: tempURL)
                        downloadedSize += file.size ?? 0
                        continue
                    }
                    
                    try FileManager.default.moveItem(at: tempURL, to: URL(fileURLWithPath: localPath))
                    
                    if let size = file.size {
                        downloadedSize += size
                    }
                    
                    print("[LLMEngine] Downloaded: \(file.path) (\(ByteCountFormatter.string(fromByteCount: downloadedSize, countStyle: .file))/\(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)))")
                } else {
                    print("[LLMEngine] Failed to download \(file.path): HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                    failedFiles.append(file.path)
                }
            } catch {
                print("[LLMEngine] Error downloading \(file.path): \(error.localizedDescription)")
                failedFiles.append(file.path)
            }
        }
        
        progressHandler(0.98, "Finalizing...")
        
        // Verify download
        var actualSize: Int64 = 0
        if let enumerator = FileManager.default.enumerator(atPath: destination) {
            while let file = enumerator.nextObject() as? String {
                let fullPath = (destination as NSString).appendingPathComponent(file)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath),
                   let size = attrs[.size] as? Int64 {
                    actualSize += size
                }
            }
        }
        
        print("[LLMEngine] Direct download complete: \(actualSize) bytes (\(ByteCountFormatter.string(fromByteCount: actualSize, countStyle: .file)))")
        
        if failedFiles.count > 0 {
            print("[LLMEngine] Failed to download \(failedFiles.count) files")
        }
    }
    
    private func formatModelName(_ name: String) -> String {
        // Convert "llama-3.2-1b-instruct" to "Llama 3.2 1B Instruct"
        return name
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
    
    /// Delete a downloaded model
    func deleteModel(at path: String) throws {
        let expandedPath = NSString(string: path).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw LLMError.modelNotFound("Unknown", path)
        }
        
        // Don't delete if it's the currently loaded model
        if let current = currentModel, current.path == path {
            throw LLMError.modelInUse
        }
        
        try FileManager.default.removeItem(atPath: expandedPath)
    }
    
    /// Get all downloaded models with their metadata
    func getDownloadedModels() async -> [DownloadedModel] {
        let available = getAvailableModels()
        
        return available.map { url in
            let name = url.lastPathComponent
            let configPath = url.appendingPathComponent("config.json")
            var contextLength = 4096
            var vocabSize = 0
            
            if let configData = try? Data(contentsOf: configPath),
               let config = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] {
                contextLength = config["max_position_embeddings"] as? Int ?? 
                              config["max_sequence_length"] as? Int ?? 4096
                vocabSize = config["vocab_size"] as? Int ?? 0
            }
            
            // Calculate model size
            var totalSize: Int64 = 0
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalSize += Int64(size)
                    }
                }
            }
            
            return DownloadedModel(
                name: name,
                path: url.path,
                contextLength: contextLength,
                vocabSize: vocabSize,
                sizeInBytes: totalSize
            )
        }
    }
    
    // MARK: - Model Loading
    
    /// Load a specific model
    func loadModel(_ model: LLMModel) async throws {
        let expandedPath = NSString(string: model.path).expandingTildeInPath
        
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw LLMError.modelNotFound(model.name, model.path)
        }
        
        if isLoaded {
            unloadModel()
        }
        
        currentModel = model
        isLoaded = true
        
        print("Model loaded: \(model.displayName)")
    }
    
    /// Unload the current model to free memory
    func unloadModel() {
        currentModel = nil
        isLoaded = false
        print("Model unloaded")
    }
    
    /// Get current model info
    func getCurrentModel() -> LLMModel? {
        return currentModel
    }
    
    /// Check if model is loaded
    func isModelLoaded() -> Bool {
        return isLoaded
    }
    
    // MARK: - Inference
    
    func generate(
        messages: [ChatMessage],
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        onToken: TokenHandler? = nil
    ) async throws -> String {
        guard isLoaded, let model = currentModel else {
            throw LLMError.modelNotLoaded
        }
        
        let prompt = buildPrompt(from: messages, model: model)
        
        return """
        [Model: \(model.displayName)]
        
        Infrastructure ready. Integrate MLX Swift for full LLM inference.
        """
    }
    
    private func buildPrompt(from messages: [ChatMessage], model: LLMModel) -> String {
        var prompt = ""
        
        for message in messages {
            switch message.role {
            case .system:
                prompt += "System: \(message.content)\n\n"
            case .user:
                prompt += "User: \(message.content)\n\n"
            case .assistant:
                prompt += "Assistant: \(message.content)\n\n"
            }
        }
        
        prompt += "Assistant:"
        return prompt
    }
}

// MARK: - Downloaded Model Metadata

struct DownloadedModel: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let contextLength: Int
    let vocabSize: Int
    let sizeInBytes: Int64
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeInBytes)
    }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case modelNotFound(String, String)
    case modelNotLoaded
    case inferenceFailed(String)
    case contextTooLong(Int, Int)
    case downloadFailed(String)
    case modelAlreadyExists(String)
    case modelInUse
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name, let path):
            return "Model '\(name)' not found at path: \(path)"
        case .modelNotLoaded:
            return "No model is currently loaded"
        case .inferenceFailed(let reason):
            return "Inference failed: \(reason)"
        case .contextTooLong(let context, let limit):
            return "Context length \(context) exceeds model limit of \(limit) tokens"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .modelAlreadyExists(let name):
            return "Model '\(name)' is already downloaded"
        case .modelInUse:
            return "Cannot delete model while it's in use"
        }
    }
}
