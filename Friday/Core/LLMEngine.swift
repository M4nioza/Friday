import Foundation

/// LLM Engine that handles model loading and inference using MLX Swift
actor LLMEngine {
    static let shared = LLMEngine()
    
    private var currentModel: LLMModel?
    private var isLoaded: Bool = false
    private var modelProcess: Process?
    
    // HuggingFace API base URL
    private let hfAPIURL = "https://huggingface.co/api"
    
    // Streaming callback type
    typealias TokenHandler = (String) async -> Void
    
    private init() {}
    
    // MARK: - Model Discovery
    
    /// Fetch available MLX models from HuggingFace
    func fetchAvailableModels() async throws -> [HuggingFaceModel] {
        // Query HuggingFace API for mlx-community models
        let url = URL(string: "\(hfAPIURL)/models?filter=mlx&sort=downloads&direction=-1&limit=100")!
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LLMError.downloadFailed("Failed to fetch models from HuggingFace")
        }
        
        let decoder = JSONDecoder()
        let rawModels = try decoder.decode([HFModelInfo].self, from: data)
        
        // Get available memory
        let availableMemory = Foundation.ProcessInfo.processInfo.physicalMemory
        
        // Filter and transform models
        let models = rawModels.compactMap { info -> HuggingFaceModel? in
            // Skip if no downloads (probably not real models)
            guard info.downloads > 0 else { return nil }
            
            // Calculate estimated size (in bytes)
            let estimatedSize = estimateModelSize(info)
            
            // Skip models that are too large (> 70% of available memory)
            guard estimatedSize < Int64(Double(availableMemory) * 0.7) else { return nil }
            
            let isVision = info.pipeline_tag == "vision-text-to-image" || 
                          info.config?.vision_enabled == true ||
                          (info.tags?.contains("vision") ?? false) ||
                          (info.id?.contains("vision") ?? false)
            
            let isInstruct = info.pipeline_tag == "text-generation" ||
                            (info.tags?.contains("instruct") ?? false) ||
                            (info.id?.contains("instruct") ?? false)
            
            // Include text generation and vision models
            let category: HuggingFaceModel.ModelCategory
            if isVision {
                category = .vision
            } else if isInstruct {
                category = .instruct
            } else {
                // Include others but mark as general
                category = .text
            }
            
            guard let modelId = info.id else { return nil }
            
            return HuggingFaceModel(
                id: modelId,
                name: formatModelName(modelId),
                downloads: info.downloads,
                size: estimatedSize,
                category: category,
                tags: info.tags ?? [],
                lastModified: info.lastModified ?? ""
            )
        }
        
        // Sort by downloads
        return models.sorted { $0.downloads > $1.downloads }
    }
    
    private func formatModelName(_ id: String?) -> String {
        guard let id = id else { return "Unknown Model" }
        // Convert "mlx-community/llama-3.2-1b-instruct" to "Llama 3.2 1B Instruct"
        let cleanId = id.replacingOccurrences(of: "mlx-community/", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        
        return cleanId.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
    
    private func estimateModelSize(_ info: HFModelInfo) -> Int64 {
        // Try to get size from safetensors if available
        if let siblings = info.siblings {
            let totalSize = siblings.compactMap { $0.size }.reduce(0, +)
            if totalSize > 0 {
                return totalSize
            }
        }
        
        // Estimate based on parameter count (rough approximation)
        // Most mlx models are 4-bit quantized, ~0.5 bytes per parameter
        let paramCount = info.config?.embedding_size ?? 
                        info.config?.hidden_size ?? 
                        info.config?.vocab_size ?? 
                        4096
        
        // Assume 4-bit quantization = 0.5 bytes per parameter
        return Int64(paramCount * 1000) / 2
    }
    
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
    
    /// Get download URL for a model
    func getModelDownloadURL(modelId: String) -> URL {
        return URL(string: "https://huggingface.co/\(modelId)/resolve/main")!
    }
    
    /// Download a model by its HuggingFace ID
    func downloadModel(
        modelId: String,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> LLMModel {
        let modelName = modelId.components(separatedBy: "/").last ?? modelId
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
        let downloadURL = getModelDownloadURL(modelId: modelId)
        let request = URLRequest(url: downloadURL)
        
        let (tempURL, response) = try await URLSession.shared.download(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.downloadFailed("Invalid response")
        }
        
        if httpResponse.statusCode == 404 {
            throw LLMError.downloadFailed("Model not found. Check if it's available in mlx-community.")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw LLMError.downloadFailed("Server returned status \(httpResponse.statusCode)")
        }
        
        // Handle redirect - get final URL
        if let finalURL = httpResponse.url {
            // Move to final destination
            if FileManager.default.fileExists(atPath: destinationPath) {
                try FileManager.default.removeItem(atPath: destinationPath)
            }
            
            // If it's a file, move directly
            if !finalURL.path.hasSuffix("/") {
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            }
        }
        
        progressHandler(1.0, "Download complete")
        
        // Create model entry
        return LLMModel(
            name: modelName,
            displayName: formatModelName(modelId),
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
    
    /// Get available system memory
    func getAvailableMemory() -> UInt64 {
        return Foundation.ProcessInfo.processInfo.physicalMemory
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

// MARK: - HuggingFace API Models

struct HuggingFaceModel: Identifiable {
    let id: String
    let name: String
    let downloads: Int
    let size: Int64
    let category: ModelCategory
    let tags: [String]
    let lastModified: String
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    var formattedDownloads: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: downloads)) ?? "\(downloads)"
    }
    
    enum ModelCategory: String {
        case vision = "Vision"
        case instruct = "Instruct"
        case text = "Text"
        
        var icon: String {
            switch self {
            case .vision: return "photo"
            case .instruct: return "doc.text"
            case .text: return "text.alignleft"
            }
        }
    }
}

struct HFModelInfo: Codable {
    let id: String?
    let downloads: Int
    let pipeline_tag: String?
    let tags: [String]?
    let lastModified: String?
    let config: HFModelConfig?
    let siblings: [HFFileInfo]?
    
    enum CodingKeys: String, CodingKey {
        case id, downloads, pipeline_tag, tags, config, siblings
        case lastModified = "lastModified"
    }
}

struct HFModelConfig: Codable {
    let vocab_size: Int?
    let hidden_size: Int?
    let embedding_size: Int?
    let vision_enabled: Bool?
}

struct HFFileInfo: Codable {
    let size: Int64?
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
