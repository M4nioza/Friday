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
        let destinationURL = URL(fileURLWithPath: destinationPath)
        
        // Check if already downloaded
        if FileManager.default.fileExists(atPath: destinationPath) {
            throw LLMError.modelAlreadyExists(modelDirName)
        }
        
        // Create cache directory if needed
        let cachePath = NSString(string: "~/.cache/mlx-model/models").expandingTildeInPath
        try FileManager.default.createDirectory(atPath: cachePath, withIntermediateDirectories: true)
        
        progressHandler(0, "Connecting to HuggingFace...")
        
        // Use git clone to download the full model repository
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["clone", "--depth", "1", "\(hfBaseURL)/\(fullModelId)", destinationPath]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        
        if process.terminationStatus != 0 {
            // Clean up partial download
            try? FileManager.default.removeItem(atPath: destinationPath)
            
            if errorOutput.contains("Repository not found") || errorOutput.contains("404") {
                throw LLMError.downloadFailed("Model not found: \(fullModelId). Check the model name.")
            }
            throw LLMError.downloadFailed("Download failed: \(errorOutput.prefix(200))")
        }
        
        progressHandler(1.0, "Download complete")
        
        // Create model entry
        return LLMModel(
            name: modelDirName,
            displayName: formatModelName(modelDirName),
            path: destinationPath,
            contextLength: 4096,
            description: "Downloaded from HuggingFace"
        )
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
