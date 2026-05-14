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
            "/opt/miniconda3/bin/mlx_lm",
            "/opt/homebrew/bin/mlx_lm",
            "/opt/homebrew/opt/mlx-lm/bin/mlx_lm",
            "/usr/local/bin/mlx_lm"
        ]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "/opt/miniconda3/bin/mlx_lm"
    }

    private init() {
        print("[LLMEngine] Friday LLM Engine initialized with mlx_lm CLI")
    }

    // MARK: - Model Management

    func getDownloadedModels() async -> [DownloadedModelInfo] {
        var models: [DownloadedModelInfo] = []

        let mlxCache = NSString(string: "~/.cache/mlx-model/models").expandingTildeInPath
        if let mlxContents = try? FileManager.default.contentsOfDirectory(atPath: mlxCache) {
            for folder in mlxContents {
                var isDir: ObjCBool = false
                let fullPath = (mlxCache as NSString).appendingPathComponent(folder)
                guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { continue }
                let size = folderSize(at: URL(fileURLWithPath: fullPath))
                guard size > 1024 else { continue }
                models.append(DownloadedModelInfo(name: folder, path: fullPath, contextLength: 4096, sizeInBytes: size))
            }
        }

        let hubDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache")
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")

        if let contents = try? FileManager.default.contentsOfDirectory(atPath: hubDir.path) {
            for folder in contents {
                let folderName = (folder as NSString).lastPathComponent
                guard folderName.hasPrefix("models--") else { continue }
                let modelName = folderName.replacingOccurrences(of: "models--", with: "").replacingOccurrences(of: "--", with: "/")
                guard modelName.contains("mlx-community") else { continue }
                let fullPath = (hubDir.path as NSString).appendingPathComponent(folder)
                let size = folderSize(at: URL(fileURLWithPath: fullPath))
                guard size > 1024 else { continue }
                models.append(DownloadedModelInfo(name: modelName, path: fullPath, contextLength: 4096, sizeInBytes: size))
            }
        }

        return models
    }

    private func folderSize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
            }
        }
        return totalSize
    }

    func deleteModel(at path: String) async throws {
        try FileManager.default.removeItem(atPath: path)
    }

    func loadModel(_ modelInfo: LLMModel) async throws {
        print("[LLMEngine] Loading model: \(modelInfo.name)")

        let modelId = modelInfo.name.hasPrefix("mlx-community/") ? modelInfo.name : "mlx-community/\(modelInfo.name)"
        let models = await getDownloadedModels()
        let exists = models.contains { $0.name == modelId }

        if !exists {
            throw LLMEngineError.modelNotFound(modelInfo.name, "Model not found in cache. Please download it first.")
        }

        self.currentModelId = modelId
        self.isLoaded = true
        print("[LLMEngine] Model ready: \(modelId)")
        await AppState.shared.updateModelState()
    }

    func unloadModel() async {
        currentModelId = nil
        isLoaded = false
        print("[LLMEngine] Model unloaded")
        await AppState.shared.updateModelState()
    }

    func getCurrentModel() -> LLMModel? {
        guard let id = currentModelId else { return nil }
        return LLMModel(name: id, displayName: id.split(separator: "/").last.map(String.init) ?? id, path: id, contextLength: 4096, description: "MLX model")
    }

    func isModelLoaded() -> Bool {
        return isLoaded && currentModelId != nil
    }

    // MARK: - Inference

    func generate(
        messages: [ChatMessage],
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> (response: String, metrics: String?) {
        guard let modelId = currentModelId else {
            throw LLMEngineError.modelNotLoaded
        }

        print("[LLMEngine] Generating with model: \(modelId)")

        let prompt = buildChatPrompt(from: messages)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: mlxBinary)
        process.arguments = [
            "generate",
            "--model", modelId,
            "--prompt", prompt,
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
            throw LLMEngineError.inferenceFailed(error.localizedDescription)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        print("[LLMEngine] Raw output: \(output.prefix(200))")
        if !errorOutput.isEmpty {
            print("[LLMEngine] stderr: \(errorOutput.prefix(200))")
        }

        var response = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if let promptEnd = response.range(of: prompt.trimmingCharacters(in: .whitespacesAndNewlines)) {
            response = String(response[promptEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let answerIndex = response.range(of: "Answer:", options: .caseInsensitive) {
            response = String(response[answerIndex.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Strip separator lines and metrics
        let lines = response.components(separatedBy: "\n")
        var cleanLines: [String] = []
        var metricsLines: [String] = []
        var separatorCount = 0

        for line in lines {
            if line.contains("==========") {
                separatorCount += 1
                continue
            }
            if separatorCount >= 2 {
                if line.hasPrefix("Prompt:") || line.hasPrefix("Generation:") || line.hasPrefix("Peak memory:") {
                    metricsLines.append(line)
                }
            } else {
                cleanLines.append(line)
            }
        }

        let cleanResponse = cleanLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let metrics = metricsLines.isEmpty ? nil : metricsLines.joined(separator: "\n")

        print("[LLMEngine] Generated response (\(cleanResponse.count) chars)")
        return (cleanResponse, metrics)
    }

    // MARK: - Prompt Building

    private func buildChatPrompt(from messages: [ChatMessage]) -> String {
        let modelId = (currentModelId ?? "").lowercased()
        if modelId.contains("mistral") || modelId.contains("mixtral") {
            return buildMistralPrompt(from: messages)
        } else if modelId.contains("qwen") {
            return buildQwenPrompt(from: messages)
        }
        return buildLlama3Prompt(from: messages)
    }

    private func buildLlama3Prompt(from messages: [ChatMessage]) -> String {
        var prompt = "<|begin_of_text|>"
        for message in messages {
            switch message.role {
            case .system:
                prompt += "<|start_header_id|>system<|end_header_id|>\n\n\(message.content)<|eot_id|>"
            case .user:
                prompt += "<|start_header_id|>user<|end_header_id|>\n\n\(message.content)<|eot_id|>"
            case .assistant:
                prompt += "<|start_header_id|>assistant<|end_header_id|>\n\n\(message.content)<|eot_id|>"
            }
        }
        prompt += "<|start_header_id|>assistant<|end_header_id|>\n\n"
        return prompt
    }

    private func buildMistralPrompt(from messages: [ChatMessage]) -> String {
        var prompt = "<s>"
        var pendingSystem = ""
        for message in messages {
            switch message.role {
            case .system:
                pendingSystem = message.content + "\n\n"
            case .user:
                prompt += "[INST] \(pendingSystem)\(message.content) [/INST]"
                pendingSystem = ""
            case .assistant:
                prompt += "\(message.content)</s> "
            }
        }
        return prompt
    }

    private func buildQwenPrompt(from messages: [ChatMessage]) -> String {
        var prompt = ""
        for message in messages {
            switch message.role {
            case .system:
                prompt += "<|im_start|>system\n\(message.content)<|im_end|>\n"
            case .user:
                prompt += "<|im_start|>user\n\(message.content)<|im_end|>\n"
            case .assistant:
                prompt += "<|im_start|>assistant\n\(message.content)<|im_end|>\n"
            }
        }
        prompt += "<|im_start|>assistant\n"
        return prompt
    }

    // MARK: - Model Download

    func downloadModel(modelName: String, progressHandler: @escaping (Double, String) -> Void) async throws -> LLMModel {
        let cleanName = modelName.replacingOccurrences(of: "mlx-community/", with: "")
        let displayName = cleanName.replacingOccurrences(of: "-", with: " ").capitalized

        progressHandler(0.05, "Starting download...")

        let script = """
from huggingface_hub import snapshot_download
import os

model_name = '\(modelName)'
cache_dir = os.path.expanduser('~/.cache/huggingface/hub')

def progress_callback(download_size, total_size):
    if total_size > 0:
        progress = download_size / total_size
        print(f'PROGRESS:{progress}', flush=True)
    print(f'STATUS:Downloaded {download_size / (1024*1024):.1f} MB', flush=True)

try:
    path = snapshot_download(
        repo_id=model_name,
        cache_dir=cache_dir,
        resume_download=True,
        progress_callback=progress_callback
    )
    print(f'SUCCESS:{path}', flush=True)
except Exception as e:
    print(f'ERROR:{e}', flush=True)
"""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/miniconda3/bin/python3")
        process.arguments = ["-c", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // Wait for process on background thread
        let output = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            Thread {
                var result = ""
                let outputHandle = outputPipe.fileHandleForReading
                let errorHandle = errorPipe.fileHandleForReading

                while process.isRunning {
                    let data = outputHandle.readData(ofLength: 4096)
                    if data.isEmpty { break }
                    if let s = String(data: data, encoding: .utf8) {
                        result += s
                        // Parse progress
                        if let range = s.range(of: "PROGRESS:") {
                            let numStr = String(s[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines).prefix(while: { $0.isNumber || $0 == "." })
                            if let p = Double(numStr) {
                                Task { @MainActor in
                                    progressHandler(p * 0.9, "Downloading...")
                                }
                            }
                        }
                    }
                    Thread.sleep(forTimeInterval: 0.2)
                }

                process.waitUntilExit()
                let remainingData = outputHandle.readDataToEndOfFile()
                if let s = String(data: remainingData, encoding: .utf8) { result += s }

                if process.terminationStatus != 0 {
                    let errData = errorHandle.readDataToEndOfFile()
                    let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: LLMEngineError.downloadFailed(errMsg))
                } else {
                    continuation.resume(returning: result)
                }
            }.start()
        }

        if output.contains("ERROR:") {
            let lines = output.components(separatedBy: "\n")
            let errorLines = lines.filter { $0.hasPrefix("ERROR:") }
            throw LLMEngineError.downloadFailed(errorLines.joined(separator: "\n"))
        }

        progressHandler(1.0, "Download complete")
        return LLMModel(name: cleanName, displayName: displayName, path: "huggingface://\(modelName)", contextLength: 4096, description: "MLX model from HuggingFace")
    }
}

// MARK: - Downloaded Model Info

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

// MARK: - Errors

enum LLMEngineError: LocalizedError {
    case modelNotLoaded
    case modelNotFound(String, String)
    case modelAlreadyExists(String)
    case modelInUse
    case downloadFailed(String)
    case inferenceFailed(String)
    case serverFailed(String)

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
        case .serverFailed(let reason):
            return "Server failed: \(reason)"
        }
    }
}