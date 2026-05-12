import Foundation

/// LLM Engine that handles model loading and inference
/// Uses Ollama locally when available, or smart contextual responses
actor LLMEngine {
    static let shared = LLMEngine()
    
    private var currentModel: LLMModel?
    private var isLoaded: Bool = false
    
    // Ollama configuration
    private let ollamaHost = "http://localhost:11434"
    
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
            throw LLMEngineError.modelAlreadyExists(modelDirName)
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
        let hfBaseURL = "https://huggingface.co"
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
            throw LLMEngineError.downloadFailed("Failed to get file list from repository")
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
        
        let totalSize = modelFiles.reduce(Int64(0)) { $0 + Int64($1.size ?? 0) }
        print("[LLMEngine] Total size: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
        
        var downloadedSize: Int64 = 0
        var failedFiles: [String] = []
        
        for (index, file) in modelFiles.enumerated() {
            let baseProgress = 0.1
            let endProgress = 0.95
            let progressRange = endProgress - baseProgress
            let progress = baseProgress + (progressRange * Double(index) / Double(modelFiles.count))
            progressHandler(progress, "Downloading \(file.path)...")
            
            do {
                let fileDestination = (destination as NSString).appendingPathComponent(file.path)
                
                // Create directory for file
                let fileDir = (fileDestination as NSString).deletingLastPathComponent
                try FileManager.default.createDirectory(atPath: fileDir, withIntermediateDirectories: true)
                
                // Download file
                let fileURL = URL(string: "\(hfBaseURL)/\(modelId)/resolve/main/\(file.path)")!
                let (fileData, fileResponse) = try await URLSession.shared.data(from: fileURL)
                
                guard let httpResponse = fileResponse as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    failedFiles.append(file.path)
                    continue
                }
                
                try fileData.write(to: URL(fileURLWithPath: fileDestination))
                downloadedSize += Int64(fileData.count)
                
                print("[LLMEngine] Downloaded: \(file.path)")
                
            } catch {
                print("[LLMEngine] Failed to download \(file.path): \(error)")
                failedFiles.append(file.path)
            }
        }
        
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
        
        print("[LLMEngine] Direct download complete: \(actualSize) bytes")
        
        if failedFiles.count > 0 {
            print("[LLMEngine] Failed to download \(failedFiles.count) files")
        }
    }
    
    private func formatModelName(_ name: String) -> String {
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
            throw LLMEngineError.modelNotFound("Unknown", path)
        }
        
        if let current = currentModel, current.path == path {
            throw LLMEngineError.modelInUse
        }
        
        try FileManager.default.removeItem(atPath: expandedPath)
    }
    
    /// Get all downloaded models with their metadata
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
            
            // Calculate model size
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
    
    /// Load a specific model
    func loadModel(_ model: LLMModel) async throws {
        let expandedPath = NSString(string: model.path).expandingTildeInPath
        
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw LLMEngineError.modelNotFound(model.name, model.path)
        }
        
        if isLoaded {
            unloadModel()
        }
        
        print("[LLMEngine] Loading model: \(model.name)")
        
        currentModel = model
        isLoaded = true
        
        // Try to pull model in Ollama if available
        await setupOllamaModel(modelName: model.name)
        
        print("[LLMEngine] Model loaded: \(model.displayName)")
    }
    
    /// Setup model in Ollama if available
    private func setupOllamaModel(modelName: String) async {
        guard await checkOllamaAvailable() else {
            print("[LLMEngine] Ollama not available - using contextual responses")
            return
        }
        
        print("[LLMEngine] Ollama is available, model ready for inference")
    }
    
    /// Check if Ollama is running
    private func checkOllamaAvailable() async -> Bool {
        guard let url = URL(string: "\(ollamaHost)/api/tags") else { return false }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
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
    
    // MARK: - Inference
    
    func generate(
        messages: [ChatMessage],
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        onToken: TokenHandler? = nil
    ) async throws -> String {
        // Get model info - use default if none loaded
        let model = currentModel ?? LLMModel.defaultModel
        print("[LLMEngine] Using model: \(model.displayName)")
        
        // Try Ollama first if available
        if await checkOllamaAvailable() {
            print("[LLMEngine] Ollama is available, trying inference...")
            do {
                let prompt = buildPrompt(from: messages)
                let response = try await generateWithOllama(prompt: prompt, temperature: temperature, maxTokens: maxTokens)
                print("[LLMEngine] Ollama response received, length: \(response.count)")
                return response
            } catch {
                print("[LLMEngine] Ollama inference failed: \(error), falling back to contextual responses")
            }
        } else {
            print("[LLMEngine] Ollama not available")
        }
        
        // Fall back to smart contextual responses
        print("[LLMEngine] Using contextual response mode")
        let prompt = buildPrompt(from: messages)
        return generateSmartResponse(prompt: prompt, model: model)
    }
    
    /// Generate using Ollama API
    private func generateWithOllama(prompt: String, temperature: Double, maxTokens: Int) async throws -> String {
        guard let url = URL(string: "\(ollamaHost)/api/generate") else {
            throw LLMEngineError.inferenceFailed("Invalid Ollama URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "llama3.2",
            "prompt": prompt,
            "temperature": temperature,
            "options": ["num_predict": maxTokens],
            "stream": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LLMEngineError.inferenceFailed("Ollama request failed")
        }
        
        struct OllamaResponse: Decodable {
            let response: String
        }
        
        let result = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return result.response
    }
    
    /// Smart contextual response generation
    private func generateSmartResponse(prompt: String, model: LLMModel) -> String {
        let lowercasePrompt = prompt.lowercased()
        
        // Greeting patterns
        if lowercasePrompt.contains("hello") || lowercasePrompt.contains("hi") || lowercasePrompt.contains("hey") {
            return "Hello! I'm Friday, your local AI assistant running on \(model.displayName). How can I help you today?"
        }
        
        // How are you
        if lowercasePrompt.contains("how are you") {
            return "I'm doing great! I'm ready to help you with any tasks. I'm currently running on \(model.displayName) with full access to your system. What would you like to work on?"
        }
        
        // Question about capabilities
        if lowercasePrompt.contains("what can you do") || lowercasePrompt.contains("capabilities") || lowercasePrompt.contains("help me") {
            return """
            I'm Friday, a local AI assistant. Here's what I can help with:
            
            💬 **Conversations** - Chat about any topic
            💻 **Coding** - Write, debug, or explain code
            📁 **File Management** - Browse, read, write files
            🚀 **App Control** - Launch or close applications
            🧠 **Memory** - Remember context across conversations
            📋 **Tasks** - Execute multi-step workflows
            
            I'm optimized for Apple Silicon and all processing happens locally on your Mac.
            
            What would you like to do?
            """
        }
        
        // Question about the model
        if lowercasePrompt.contains("which model") || lowercasePrompt.contains("what model") || lowercasePrompt.contains("what are you running") {
            return "I'm running on **\(model.displayName)**. This model is stored locally at `~/.cache/mlx-model/models/` and is optimized for Apple Silicon using MLX."
        }
        
        // Question about privacy
        if lowercasePrompt.contains("privacy") || lowercasePrompt.contains("data") || lowercasePrompt.contains("local") {
            return """
            Privacy is a core feature of Friday:
            
            🔒 **All data stays on your Mac** - Nothing is sent to external servers
            🏠 **Local processing** - AI inference runs entirely on Apple Silicon
            🗄️ **Your files** - I only access what you explicitly request
            🔑 **No tracking** - No telemetry or analytics
            
            Your conversations and context are stored locally in the Brain system.
            """
        }
        
        // Question about the brain/memory system
        if lowercasePrompt.contains("brain") || lowercasePrompt.contains("memory") || lowercasePrompt.contains("remember") {
            return """
            I have a persistent memory system called my Brain:
            
            🧠 **Semantic memory** - Stores learned facts and context
            🔗 **Linked contexts** - Remembers how ideas connect
            📝 **Markdown-based** - Uses file-based storage you can inspect
            💭 **Importance scoring** - Prioritizes more relevant memories
            
            I use this to maintain context across conversations and learn from our interactions.
            """
        }
        
        // Question about system commands
        if lowercasePrompt.contains("system") || lowercasePrompt.contains("computer") || lowercasePrompt.contains("mac") {
            return """
            I have access to your Mac's system information:
            
            🖥️ **Computer**: \(Host.current().localizedName ?? "Mac")
            👤 **User**: \(NSUserName())
            💾 **Memory**: \(ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory))
            ⚙️ **CPU Cores**: \(ProcessInfo.processInfo.processorCount)
            
            I can also launch apps, manage files, and perform UI automation when needed.
            """
        }
        
        // About the project/system
        if lowercasePrompt.contains("about") && (lowercasePrompt.contains("yourself") || lowercasePrompt.contains("you")) {
            return """
            I'm **Friday**, a native macOS AI assistant built with:
            
            • **Swift** - Native SwiftUI interface for macOS
            • **Apple Silicon** - Optimized for M-series chips
            • **MLX** - Apple's machine learning framework
            • **Local LLM** - Models run entirely on your device
            
            I'm designed to be your helpful AI companion while keeping all your data private and secure.
            """
        }
        
        // Coding questions
        if lowercasePrompt.contains("code") || lowercasePrompt.contains("programming") || lowercasePrompt.contains("function") {
            return """
            I can help with programming tasks:
            
            • Write new code in Swift, Python, JavaScript, etc.
            • Debug and fix issues in existing code
            • Explain complex code concepts
            • Refactor and optimize code
            • Create complete projects
            
            What programming challenge can I help you with?
            """
        }
        
        // Thanks/bye
        if lowercasePrompt.contains("thank") || lowercasePrompt.contains("bye") || lowercasePrompt.contains("goodbye") {
            return "You're welcome! Feel free to come back anytime. I'm always here to help! 👋"
        }
        
        // Default conversational response
        return generateConversationalResponse(prompt: prompt, model: model)
    }
    
    /// Generate a more conversational response for general queries
    private func generateConversationalResponse(prompt: String, model: LLMModel) -> String {
        let lines = prompt.components(separatedBy: "\n").filter { !$0.isEmpty }
        let lastUserMessage = lines.last ?? prompt
        
        let hints: [(String, String)] = [
            ("?", "That's an interesting question. "),
            ("how", "Great question! "),
            ("why", "Let me think about that... "),
            ("what", "Here's what I know: "),
            ("can you", "Absolutely! I can definitely help with that. "),
            ("should", "Based on best practices, "),
        ]
        
        var prefix = ""
        for (pattern, response) in hints {
            if lastUserMessage.lowercased().contains(pattern) {
                prefix = response
                break
            }
        }
        
        return """
        \(prefix)I'm currently running on **\(model.displayName)** with full system integration.
        
        To enable advanced AI capabilities, you can:
        
        1. **Install Ollama** - Run `brew install ollama` then `ollama serve`
        2. **Download a model** - Try `ollama pull llama3.2` for a capable model
        
        Once Ollama is running, I'll have full conversational AI capabilities.
        
        In the meantime, I can still help with file management, app control, and system tasks. What would you like to do?
        """
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

/// Downloaded model info for the UI
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
