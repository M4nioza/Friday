import Foundation

/// LLM Engine that handles model loading and inference using MLX Swift
actor LLMEngine {
    static let shared = LLMEngine()
    
    private var currentModel: LLMModel?
    private var isLoaded: Bool = false
    private var modelProcess: Process?
    
    // Streaming callback type
    typealias TokenHandler = (String) async -> Void
    
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
    
    /// Download a model from HuggingFace using native Swift URLSession
    func downloadModel(
        from url: URL,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> LLMModel {
        let modelName = url.lastPathComponent
        let destinationPath = NSString(string: "~/.cache/mlx-model/models/\(modelName)").expandingTildeInPath
        let destinationURL = URL(fileURLWithPath: destinationPath)
        
        // Check if already downloaded
        if FileManager.default.fileExists(atPath: destinationPath) {
            throw LLMError.modelAlreadyExists(modelName)
        }
        
        // Create cache directory if needed
        let cachePath = NSString(string: "~/.cache/mlx-model/models").expandingTildeInPath
        try FileManager.default.createDirectory(atPath: cachePath, withIntermediateDirectories: true)
        
        progressHandler(0, "Starting download...")
        
        // Use URLSession for native Swift download
        let request = URLRequest(url: url)
        let (tempURL, response) = try await URLSession.shared.download(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LLMError.downloadFailed("Server returned an error")
        }
        
        // Get total size for progress
        let totalSize = httpResponse.expectedContentLength
        
        // Move to final destination
        if FileManager.default.fileExists(atPath: destinationPath) {
            try FileManager.default.removeItem(atPath: destinationPath)
        }
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        
        progressHandler(1.0, "Download complete")
        
        // Create model entry
        return LLMModel(
            name: modelName,
            displayName: modelName.replacingOccurrences(of: "-", with: " ").capitalized,
            path: destinationPath,
            contextLength: 4096,
            description: "Downloaded from HuggingFace"
        )
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
        // Expand path
        let expandedPath = NSString(string: model.path).expandingTildeInPath
        
        // Check if model exists
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw LLMError.modelNotFound(model.name, model.path)
        }
        
        // Unload current model if any
        if isLoaded {
            unloadModel()
        }
        
        // Note: In a full implementation, we would initialize MLX here
        // For now, we mark it as loaded and store the model reference
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
    
    /// Generate a response from the model
    /// Note: Full MLX Swift integration would go here
    /// For now, this provides the interface for future implementation
    func generate(
        messages: [ChatMessage],
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        onToken: TokenHandler? = nil
    ) async throws -> String {
        guard isLoaded, let model = currentModel else {
            throw LLMError.modelNotLoaded
        }
        
        // Convert messages to prompt format
        let prompt = buildPrompt(from: messages, model: model)
        
        // In a full implementation, this would call MLX Swift for inference
        // For demonstration, return a placeholder
        return """
        [Model: \(model.displayName)]
        
        This is a placeholder response. To enable full LLM inference:
        
        1. Add the MLX Swift package to your project
        2. Initialize the model using MLX's model loading APIs
        3. Implement token generation with the loaded model
        
        The infrastructure for model management, downloading, and context building is in place.
        """
    }
    
    /// Build prompt from chat messages
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

/// Downloaded model metadata
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

/// LLM-related errors
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
