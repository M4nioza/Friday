import Foundation

/// Context Manager for building rich context for LLM interactions
actor ContextManager {
    static let shared = ContextManager()
    
    /// Maximum tokens to use for context (leaving room for response)
    private let maxContextTokens = 6000
    
    /// Context pieces that are always included
    private var persistentContext: [ContextPiece] = []
    
    private init() {}
    
    /// Add a persistent context piece
    func addPersistentContext(_ piece: ContextPiece) {
        persistentContext.append(piece)
    }
    
    /// Remove a persistent context piece by ID
    func removePersistentContext(_ id: UUID) {
        persistentContext.removeAll { $0.id == id }
    }
    
    /// Build complete context for a conversation
    func buildContext(
        messages: [ChatMessage],
        includeBrainContext: Bool = true,
        brainQuery: String? = nil,
        systemPrompt: String? = nil
    ) async -> String {
        var contextParts: [String] = []
        
        // 1. System prompt
        if let systemPrompt = systemPrompt {
            contextParts.append("=== SYSTEM ===\n\(systemPrompt)")
        } else {
            contextParts.append(getDefaultSystemPrompt())
        }
        
        // 2. Persistent context
        for piece in persistentContext {
            contextParts.append("=== \(piece.label.uppercased()) ===\n\(piece.content)")
        }
        
        // 3. Brain context
        if includeBrainContext {
            let query = brainQuery ?? extractTopicFromMessages(messages)
            let brainContext = await BrainSystem.shared.buildContext(for: query)
            if !brainContext.isEmpty {
                contextParts.append("=== MEMORY CONTEXT ===\n\(brainContext)")
            }
        }
        
        // 4. Deep memory links if relevant
        if let brainQuery = brainQuery {
            let deepContext = await BrainSystem.shared.getDeepContext(for: brainQuery)
            if !deepContext.isEmpty {
                contextParts.append(deepContext)
            }
        }
        
        // 5. Recent conversation history (limited)
        let recentMessages = getRecentMessages(messages, maxTokens: 2000)
        if !recentMessages.isEmpty {
            contextParts.append("=== RECENT CONVERSATION ===")
            for msg in recentMessages {
                let role = msg.role == .user ? "USER" : "ASSISTANT"
                contextParts.append("[\(role)]: \(msg.content)")
            }
        }
        
        return contextParts.joined(separator: "\n\n")
    }
    
    /// Get recent messages within token limit
    private func getRecentMessages(_ messages: [ChatMessage], maxTokens: Int) -> [ChatMessage] {
        var result: [ChatMessage] = []
        var currentTokens = 0
        
        // Start from most recent and go backwards
        for message in messages.reversed() {
            let messageTokens = estimateTokens(in: message.content)
            if currentTokens + messageTokens > maxTokens {
                break
            }
            result.insert(message, at: 0)
            currentTokens += messageTokens
        }
        
        return result
    }
    
    /// Estimate token count (rough approximation)
    private func estimateTokens(in text: String) -> Int {
        // Rough estimate: ~4 characters per token
        return text.count / 4
    }
    
    /// Extract topic from messages for brain query
    private func extractTopicFromMessages(_ messages: [ChatMessage]) -> String {
        guard let lastMessage = messages.last else {
            return "general"
        }
        
        // Use last user message as the topic
        if lastMessage.role == .user {
            return String(lastMessage.content.prefix(200))
        }
        
        return "general conversation"
    }
    
    /// Get default system prompt
    private func getDefaultSystemPrompt() -> String {
        return """
        You are Friday, a helpful AI assistant running locally on a Mac.
        
        You have access to:
        - Application control (launch/close apps)
        - File system operations (read, write, create, delete files and folders)
        - A persistent memory system where you store important information
        - Task planning capabilities to break down complex requests
        
        Guidelines:
        1. Be helpful, concise, and practical
        2. When executing actions, explain what you're doing
        3. Use your memory to remember important details across conversations
        4. If a task requires multiple steps, plan it out before executing
        5. Ask for clarification when needed
        6. All processing happens locally - your conversations are private
        
        When you learn something important about the user or their preferences, 
        consider storing it in your memory for future reference.
        """
    }
    
    /// Build context for planning a task
    func buildPlanningContext(task: String, userHistory: [ChatMessage]) async -> String {
        var context = "=== TASK PLANNING CONTEXT ===\n\n"
        
        // System capabilities
        context += """
        Available Actions:
        - launchApp(bundleId: String) - Launch an application by its bundle ID
        - closeApp(bundleId: String) - Close an application
        - readFile(path: String) - Read file contents
        - writeFile(path: String, content: String) - Write content to a file
        - createDirectory(path: String) - Create a directory
        - deleteItem(path: String) - Delete a file or directory
        - runAppleScript(script: String) - Execute AppleScript
        - clickAt(x: Int, y: Int) - Simulate mouse click
        - typeText(text: String) - Type text
        - wait(seconds: Double) - Wait before next action
        - rememberToBrain(fact: String) - Store important information
        
        """
        
        // Current system state
        let systemInfo = await SystemIntegration.shared.getSystemInfo()
        context += "Current System State:\n"
        context += "- User: \(systemInfo.currentUser)\n"
        context += "- Working Directory: \(systemInfo.workingDirectory)\n"
        context += "- Home: \(systemInfo.homeDirectory)\n\n"
        
        // Recent relevant memories
        let relevantMemories = await BrainSystem.shared.searchMemories(query: task)
        if !relevantMemories.isEmpty {
            context += "Relevant Memories:\n"
            for memory in relevantMemories.prefix(5) {
                context += "- [\(memory.title)]: \(memory.content.prefix(100))...\n"
            }
            context += "\n"
        }
        
        // The task
        context += "=== TASK ===\n\(task)\n"
        
        return context
    }
}

/// A piece of context information
struct ContextPiece: Identifiable {
    let id: UUID
    let label: String
    let content: String
    let priority: Priority
    
    init(
        id: UUID = UUID(),
        label: String,
        content: String,
        priority: Priority = .normal
    ) {
        self.id = id
        self.label = label
        self.content = content
        self.priority = priority
    }
    
    enum Priority {
        case low
        case normal
        case high
    }
}
