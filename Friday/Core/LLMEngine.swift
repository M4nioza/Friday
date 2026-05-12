import Foundation

/// LLM Engine that handles model loading and inference using the mlx_lm CLI
actor LLMEngine {
    static let shared = LLMEngine()
    
    // Model state
    private var currentModelId: String?
    private var isLoaded: Bool = false
    
    // MLX CLI path
    private var mlxBinary: String {
        let paths = [
            "/opt/homebrew/bin/mlx_lm",
            "/opt/homebrew/opt/mlx-lm/bin/mlx_lm",
            "/usr/local/bin/mlx_lm"
        ]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "/opt/homebrew/bin/mlx_lm"
    }
    
    private init() {
        print("[LLMEngine] Friday LLM Engine initialized with mlx_lm CLI")
    }
    
    // MARK: - Model Management
    
    /// Get list of downloaded models in cache
    func getDownloadedModels() async -> [DownloadedModelInfo] {
        var models: [DownloadedModelInfo] = []
        
        // Check mlx-model cache (converted MLX models)
        let mlxCache = NSString(string: "~/.cache/mlx-model/models").expandingTildeInPath
        if let mlxContents = try? FileManager.default.contentsOfDirectory(atPath: mlxCache) {
            for folder in mlxContents {
                var isDir: ObjCBool = false
                let fullPath = (mlxCache as NSString).appendingPathComponent(folder)
                guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { continue }
                
                let size = folderSize(at: URL(fileURLWithPath: fullPath))
                guard size > 1024 else { continue }
                
                let modelInfo = DownloadedModelInfo(
                    name: folder,
                    path: fullPath,
                    contextLength: 4096,
                    sizeInBytes: size
                )
                models.append(modelInfo)
            }
        }
        
        // Also check HuggingFace hub for mlx-community models
        let hubDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache")
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")
        
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: hubDir.path) {
            for folder in contents {
                let folderName = (folder as NSString).lastPathComponent
                guard folderName.hasPrefix("models--") else { continue }
                let modelName = folderName.replacingOccurrences(of: "models--", with: "").replacingOccurrences(of: "--", with: "/")
                
                // Only include mlx-community models
                guard modelName.contains("mlx-community") else { continue }
                
                let fullPath = (hubDir.path as NSString).appendingPathComponent(folder)
                let size = folderSize(at: URL(fileURLWithPath: fullPath))
                guard size > 1024 else { continue }
                
                let modelInfo = DownloadedModelInfo(
                    name: modelName,
                    path: fullPath,
                    contextLength: 4096,
                    sizeInBytes: size
                )
                models.append(modelInfo)
            }
        }
        
        return models
    }
    
    private func folderSize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }
    
    /// Delete a model at the given path
    func deleteModel(at path: String) async throws {
        try FileManager.default.removeItem(atPath: path)
    }
    
    /// Load a model for inference
    func loadModel(_ modelInfo: LLMModel) async throws {
        print("[LLMEngine] Loading model: \(modelInfo.name)")
        
        let modelId = modelInfo.name.hasPrefix("mlx-community/") ? modelInfo.name : "mlx-community/\(modelInfo.name)"
        
        // Verify model exists
        let models = await getDownloadedModels()
        let exists = models.contains { $0.name == modelId }
        
        if !exists {
            throw LLMEngineError.modelNotFound(modelInfo.name, "Model not found in cache. Please download it first.")
        }
        
        self.currentModelId = modelId
        self.isLoaded = true
        print("[LLMEngine] Model ready: \(modelId)")
    }
    
    /// Unload the current model
    func unloadModel() {
        currentModelId = nil
        isLoaded = false
        print("[LLMEngine] Model unloaded")
    }
    
    /// Get current model info
    func getCurrentModel() -> LLMModel? {
        guard let id = currentModelId else { return nil }
        return LLMModel(
            name: id,
            displayName: id.split(separator: "/").last.map(String.init) ?? id,
            path: id,
            contextLength: 4096,
            description: "MLX model"
        )
    }
    
    /// Check if model is loaded
    func isModelLoaded() -> Bool {
        return isLoaded && currentModelId != nil
    }
    
    // MARK: - Inference
    
    /// Generate a response using mlx_lm chat
    func generate(
        messages: [ChatMessage],
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        onToken: ((String) -> Void)? = nil
    ) async throws -> String {
        guard let modelId = currentModelId else {
            throw LLMEngineError.modelNotLoaded
        }
        
        print("[LLMEngine] Generating with model: \(modelId)")
        
        // Build prompt from messages
        let prompt = buildPrompt(from: messages)
        
        // Create temp file for prompt
        let tempDir = FileManager.default.temporaryDirectory
        let promptFile = tempDir.appendingPathComponent("friday_prompt.txt")
        
        // Write prompt to file
        try prompt.write(to: promptFile, atomically: true, encoding: .utf8)
        
        // Run mlx_lm generate with file input
        let process = Process()
        process.executableURL = URL(fileURLWithPath: mlxBinary)
        process.arguments = [
            "generate",
            "--model", modelId,
            "--prompt", "@\(promptFile.path)",
            "--max-tokens", "\(maxTokens)",
            "--temp", "\(temperature)"
        ]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            try? FileManager.default.removeItem(at: promptFile)
            throw LLMEngineError.inferenceFailed(error.localizedDescription)
        }
        
        // Read output
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        
        // Read error for debugging
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        
        // Clean up
        try? FileManager.default.removeItem(at: promptFile)
        
        print("[LLMEngine] Raw output: \(output.prefix(200))")
        if !errorOutput.isEmpty {
            print("[LLMEngine] Error output: \(errorOutput.prefix(200))")
        }
        
        // Parse response - mlx_lm outputs "Answer: ..." or just the text
        var response = output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove the prompt echo if present
        if let promptEnd = response.range(of: prompt.trimmingCharacters(in: .whitespacesAndNewlines)) {
            response = String(response[promptEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Remove "Answer:" prefix if present
        if let answerIndex = response.range(of: "Answer:", options: .caseInsensitive) {
            response = String(response[answerIndex.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        print("[LLMEngine] Generated response (\(response.count) chars)")
        return response
    }
    
    private func buildPrompt(from messages: [ChatMessage]) -> String {
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
    
    /// Download a model from HuggingFace
    func downloadModel(
        modelName: String,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> LLMModel {
        let cleanName = modelName.replacingOccurrences(of: "mlx-community/", with: "")
        let displayName = cleanName.replacingOccurrences(of: "-", with: " ").capitalized
        
        progressHandler(0.1, "Downloading model...")
        
        // Run mlx_lm download
        let process = Process()
        process.executableURL = URL(fileURLWithPath: mlxBinary)
        process.arguments = ["download", "--model", modelName]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? error.localizedDescription
            throw LLMEngineError.downloadFailed(errorMessage)
        }
        
        progressHandler(1.0, "Download complete")
        
        return LLMModel(
            name: cleanName,
            displayName: displayName,
            path: "huggingface://\(modelName)",
            contextLength: 4096,
            description: "MLX model from HuggingFace"
        )
    }
}

/// Downloaded model info
struct DownloadedModelInfo: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let contextLength: Int
    let sizeInBytes: Int64
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
    }
}

/// LLM Engine Errors
enum LLMEngineError: LocalizedError {
    case modelNotLoaded
    case modelNotFound(String, String)
    case modelAlreadyExists(String)
    case modelInUse
    case downloadFailed(String)
    case inferenceFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "No model is currently loaded. Please load a model first."
        case .modelNotFound(let name, let reason):
            return "Model '\(name)' not found: \(reason)"
        case .modelAlreadyExists(let name):
            return "Model '\(name)' is already downloaded."
        case .modelInUse:
            return "Cannot delete the currently loaded model."
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .inferenceFailed(let reason):
            return "Inference failed: \(reason)"
        }
    }
}
