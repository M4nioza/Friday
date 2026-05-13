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
        // Start with system prompt only
        var context = ""
        
        if let systemPrompt = systemPrompt {
            context = systemPrompt
        } else {
            context = getDefaultSystemPrompt()
        }
        
        // Add memory context only if relevant memories exist
        if includeBrainContext {
            let query = brainQuery ?? extractTopicFromMessages(messages)
            let memories = await BrainSystem.shared.searchMemories(query: query)
            
            // Only add memory context if there are relevant results
            if !memories.isEmpty {
                context += "\n\nThings I remember about this:\n"
                for memory in memories.prefix(3) {
                    context += "- \(memory.content)\n"
                }
            }
            // If no memories found, the model should just answer based on its training
        }
        
        return context
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
You are Friday, a helpful AI assistant on this Mac.

CHATTING: Just talk normally. If the user says hello, say hello back and ask how you can help.

LEARNING: If you don't know something the user tells you, remember it by saying "I'll remember that" and then summarize the key point in your response.

MEMORY CATEGORIES (for storing new info):
- identity: Who you are, your purpose
- facts: General facts about the user or world
- learned: Things the user told you about themselves
- preferences: User likes/dislikes, settings
- projects: Ongoing work or tasks
- conversations: Important conversation summaries

Keep responses conversational and concise. No code or lists unless asked.
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
