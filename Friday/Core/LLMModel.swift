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
    
    static let defaultModel = LLMModel(
        name: "llama3.2-3b",
        displayName: "Llama 3.2 3B",
        path: "~/.cache/mlx-model/models/llama3.2-3b",
        contextLength: 4096,
        description: "Fast and efficient model for general tasks",
        recommendedFor: ["general", "coding", "reasoning"]
    )
    
    static let allModels: [LLMModel] = [
        defaultModel,
        LLMModel(
            name: "llama3.2-1b",
            displayName: "Llama 3.2 1B",
            path: "~/.cache/mlx-model/models/llama3.2-1b",
            contextLength: 4096,
            description: "Ultra-fast model for simple tasks",
            recommendedFor: ["simple", "fast"]
        ),
        LLMModel(
            name: "llama3.1-8b",
            displayName: "Llama 3.1 8B",
            path: "~/.cache/mlx-model/models/llama3.1-8b",
            contextLength: 8192,
            description: "Balanced model with longer context",
            recommendedFor: ["complex", "long-context"]
        ),
        LLMModel(
            name: "mistral-7b",
            displayName: "Mistral 7B",
            path: "~/.cache/mlx-model/models/mistral-7b",
            contextLength: 8192,
            description: "Strong reasoning capabilities",
            recommendedFor: ["reasoning", "analysis"]
        ),
        LLMModel(
            name: "phi-3.5-mini",
            displayName: "Phi-3.5 Mini",
            path: "~/.cache/mlx-model/models/phi-3.5-mini",
            contextLength: 4096,
            description: "Compact model with good quality",
            recommendedFor: ["fast", "efficient"]
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
