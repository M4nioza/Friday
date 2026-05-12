import Foundation
import MLX

/// LLM Engine that handles model loading and inference using Apple MLX
/// Optimized for Apple Silicon with Metal acceleration
/// Uses mlx_lm CLI for inference
actor LLMEngine {
    static let shared = LLMEngine()
    
    private var currentModel: LLMModel?
    private var isLoaded: Bool = false
    private var mlxModelName: String = "mlx-community/Llama-3.2-1B-Instruct-4bit"
    
    // MLX CLI path
    private let mlxBinary = "/opt/homebrew/opt/mlx-lm/bin/mlx_lm"
    
    private init() {
        print("[LLMEngine] Friday LLM Engine initialized with MLX")
        print("[LLMEngine] MLX binary: \(mlxBinary)")
    }
    
    // MARK: - Type Definitions
    
    typealias TokenHandler = (String) async -> Void
    typealias ProgressHandler = (Double, String) -> Void
    
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
    
    /// Download a model from HuggingFace mlx-community
    func downloadModel(
        modelName: String,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> LLMModel {
        let modelDirName = modelName.components(separatedBy: "/").last ?? modelName
        let destinationPath = NSString(string: "~/.cache/mlx-model/models/\(modelDirName)").expandingTildeInPath
        
        print("[LLMEngine] Starting download of: \(modelName)")
        progressHandler(0.1, "Downloading model from HuggingFace...")
        
        // Use mlx_lm to download (through the generate command which auto-downloads)
        let fullModelId = modelName.hasPrefix("mlx-community/") ? modelName : "mlx-community/\(modelName)"
        
        // Run mlx_lm generate to trigger download
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "\(mlxBinary) generate --model '\(fullModelId)' --prompt 'test' --max-tokens 1 2>&1 | head -5"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = nil
        
        try process.run()
        process.waitUntilExit()
        
        progressHandler(1.0, "Download complete")
        print("[LLMEngine] Download successful!")
        
        return LLMModel(
            name: modelDirName,
            displayName: formatModelName(modelDirName),
            path: destinationPath,
            contextLength: 4096,
            description: "Downloaded from HuggingFace mlx-community"
        )
    }
    
    private func formatModelName(_ name: String) -> String {
        return name.replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
    
    /// Delete a downloaded model
    func deleteModel(at path: String) throws {
        let expandedPath = NSString(string: path).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw LLMEngineError.modelNotFound("Unknown", path)
        }
        
        if let current = currentModel, current.path == expandedPath {
            throw LLMEngineError.modelInUse
        }
        
        try FileManager.default.removeItem(atPath: expandedPath)
    }
    
    /// Get all downloaded models
    func getDownloadedModels() async -> [DownloadedModelInfo] {
        let available = getAvailableModels()
        
        return available.map { url in
            let name = url.lastPathComponent
            let configPath = url.appendingPathComponent("config.json")
            var contextLength = 4096
            
            if let configData = try? Data(contentsOf: configPath),
               let config = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] {
                contextLength = config["max_position_embeddings"] as? Int ?? 
                              config["max_sequence_length"] as? Int ?? 4096
            }
            
            var totalSize: Int64 = 0
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalSize += Int64(size)
                    }
                }
            }
            
            return DownloadedModelInfo(
                name: name,
                path: url.path,
                contextLength: contextLength,
                sizeInBytes: totalSize
            )
        }
    }
    
    // MARK: - Model Loading
    
    /// Load a model for inference
    func loadModel(_ modelInfo: LLMModel) async throws {
        let expandedPath = NSString(string: modelInfo.path).expandingTildeInPath
        
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw LLMEngineError.modelNotFound(modelInfo.name, modelInfo.path)
        }
        
        if isLoaded {
            unloadModel()
        }
        
        print("[LLMEngine] Loading model: \(modelInfo.name)")
        
        self.currentModel = modelInfo
        self.mlxModelName = "mlx-community/\(modelInfo.name)"
        self.isLoaded = true
        
        print("[LLMEngine] Model loaded: \(modelInfo.displayName)")
    }
    
    /// Unload the current model
    func unloadModel() {
        currentModel = nil
        isLoaded = false
        print("[LLMEngine] Model unloaded")
    }
    
    /// Get current model info
    func getCurrentModel() -> LLMModel? {
        return currentModel
    }
    
    /// Check if model is loaded
    func isModelLoaded() -> Bool {
        return isLoaded
    }
    
    // MARK: - Inference using MLX
    
    func generate(
        messages: [ChatMessage],
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        onToken: TokenHandler? = nil
    ) async throws -> String {
        let modelName = currentModel?.name ?? "Llama-3.2-1B-Instruct-4bit"
        print("[LLMEngine] Generating with MLX model: \(modelName)")
        
        // Build prompt from messages
        let prompt = buildPrompt(from: messages)
        print("[LLMEngine] Prompt length: \(prompt.count) chars")
        
        // Use MLX for inference
        return try await generateWithMLX(
            model: "mlx-community/\(modelName)",
            prompt: prompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }
    
    /// Generate using MLX CLI
    private func generateWithMLX(model: String, prompt: String, temperature: Double, maxTokens: Int) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            // Create temp file for prompt
            let tempDir = FileManager.default.temporaryDirectory
            let promptFile = tempDir.appendingPathComponent("friday_prompt_\(UUID().uuidString).txt")
            
            do {
                try prompt.write(to: promptFile, atomically: true, encoding: .utf8)
            } catch {
                continuation.resume(throwing: LLMEngineError.inferenceFailed("Failed to write prompt: \(error)"))
                return
            }
            
            // Build mlx_lm command
            let escapedPrompt = prompt
                .replacingOccurrences(of: "'", with: "'\\''")
                .replacingOccurrences(of: "\n", with: "\\n")
            
            let mlxPath = mlxBinary.replacingOccurrences(of: " ", with: "\\ ")
            let cmd = "\(mlxPath) generate --model '\(model)' --prompt '\(escapedPrompt)' --max-tokens \(maxTokens) --temp \(temperature) 2>&1"
            
            print("[LLMEngine] Running MLX command...")
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", cmd]
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            process.terminationHandler = { proc in
                // Clean up temp file
                try? FileManager.default.removeItem(at: promptFile)
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                
                if proc.terminationStatus == 0 {
                    // Parse output - extract the generated text
                    let response = self.parseMLXOutput(output)
                    print("[LLMEngine] MLX generated \(response.count) chars")
                    continuation.resume(returning: response)
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorStr = String(data: errorData, encoding: .utf8) ?? ""
                    print("[LLMEngine] MLX error: \(errorStr)")
                    continuation.resume(throwing: LLMEngineError.inferenceFailed(errorStr))
                }
            }
            
            do {
                try process.run()
            } catch {
                try? FileManager.default.removeItem(at: promptFile)
                continuation.resume(throwing: LLMEngineError.inferenceFailed("Failed to run MLX: \(error)"))
            }
        }
    }
    
    /// Parse MLX output to extract just the generated response
    nonisolated private func parseMLXOutput(_ output: String) -> String {
        // MLX output format:
        // ==========
        // Generated text
        // ==========
        // Prompt: X tokens, Y tokens-per-sec
        // Generation: Z tokens, W tokens-per-sec
        
        let lines = output.components(separatedBy: "\n")
        var inResponse = false
        var responseLines: [String] = []
        var isFirstLine = true
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("==========") {
                inResponse = !inResponse
                isFirstLine = true
                continue
            }
            
            if inResponse && !trimmed.isEmpty && !trimmed.hasPrefix("Prompt:") && !trimmed.hasPrefix("Generation:") && !trimmed.hasPrefix("Peak memory:") {
                if isFirstLine {
                    isFirstLine = false
                } else {
                    responseLines.append(line)
                }
            }
        }
        
        let response = responseLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return response.isEmpty ? output : response
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
        case .modelNotFound(let name, let path):
            return "Model '\(name)' not found at path: \(path)"
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
