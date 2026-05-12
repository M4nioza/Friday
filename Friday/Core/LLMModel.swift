import Foundation

/// Represents a local LLM model configuration
struct LLMModel: Identifiable, Hashable {
    let id: UUID
    let name: String
    let displayName: String
    let path: String
    let contextLength: Int
    let description: String
    let recommendedFor: [String]
    
    // HuggingFace model ID for MLX
    var hfModelId: String {
        return "mlx-community/\(name)"
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        displayName: String,
        path: String,
        contextLength: Int = 4096,
        description: String = "",
        recommendedFor: [String] = []
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.path = path
        self.contextLength = contextLength
        self.description = description
        self.recommendedFor = recommendedFor
    }
    
    // Default model - Llama 3.2 1B (tested working with MLX)
    static let defaultModel = LLMModel(
        name: "Llama-3.2-1B-Instruct-4bit",
        displayName: "Llama 3.2 1B Instruct",
        path: "~/.cache/mlx-model/models/Llama-3.2-1B-Instruct-4bit",
        contextLength: 4096,
        description: "Fast and efficient model for general tasks (tested with MLX)",
        recommendedFor: ["general", "coding", "reasoning", "fast"]
    )
    
    // Available models compatible with MLX
    static let allModels: [LLMModel] = [
        defaultModel,
        LLMModel(
            name: "Llama-3.2-3B-Instruct-4bit",
            displayName: "Llama 3.2 3B Instruct",
            path: "~/.cache/mlx-model/models/Llama-3.2-3B-Instruct-4bit",
            contextLength: 4096,
            description: "Balanced model with more capacity",
            recommendedFor: ["complex", "reasoning"]
        ),
        LLMModel(
            name: "Mistral-7B-Instruct-4bit",
            displayName: "Mistral 7B Instruct",
            path: "~/.cache/mlx-model/models/Mistral-7B-Instruct-4bit",
            contextLength: 8192,
            description: "Strong reasoning capabilities",
            recommendedFor: ["reasoning", "analysis"]
        ),
        LLMModel(
            name: "Qwen2.5-1.5B-Instruct-4bit",
            displayName: "Qwen 2.5 1.5B",
            path: "~/.cache/mlx-model/models/Qwen2.5-1.5B-Instruct-4bit",
            contextLength: 8192,
            description: "Fast and lightweight",
            recommendedFor: ["fast", "simple"]
        )
    ]
}

/// Chat message structure
struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date
    var modelUsed: String?
    var actions: [ExecutedAction]?
    
    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        modelUsed: String? = nil,
        actions: [ExecutedAction]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.modelUsed = modelUsed
        self.actions = actions
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

/// Action executed by the assistant
struct ExecutedAction: Identifiable, Codable, Hashable {
    let id: UUID
    let type: ActionType
    let description: String
    let success: Bool
    let timestamp: Date
    let details: String?
    
    init(
        id: UUID = UUID(),
        type: ActionType,
        description: String,
        success: Bool,
        timestamp: Date = Date(),
        details: String? = nil
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.success = success
        self.timestamp = timestamp
        self.details = details
    }
}

enum ActionType: String, Codable {
    case launchApp
    case closeApp
    case createFile
    case readFile
    case writeFile
    case deleteFile
    case createDirectory
    case deleteDirectory
    case executeCommand
    case uiInteraction
    case memoryRead
    case memoryWrite
    case planning
}
