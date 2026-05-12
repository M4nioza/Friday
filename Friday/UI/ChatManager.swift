import Foundation
import Combine

/// Manages chat conversations and LLM interactions
@MainActor
final class ChatManager: ObservableObject {
    static let shared = ChatManager()
    
    @Published var messages: [ChatMessage] = []
    @Published var currentConversation: Conversation?
    @Published var isProcessing: Bool = false
    @Published var error: String?
    
    private var conversations: [Conversation] = []
    
    struct Conversation: Identifiable, Codable {
        let id: UUID
        var title: String
        var messages: [ChatMessage]
        var createdAt: Date
        var updatedAt: Date
        
        init(
            id: UUID = UUID(),
            title: String = "New Conversation",
            messages: [ChatMessage] = [],
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.messages = messages
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
    
    private init() {
        loadConversations()
    }
    
    // MARK: - Message Handling
    
    /// Send a message and get response
    func sendMessage(_ content: String) async {
        guard !isProcessing else { return }
        
        isProcessing = true
        error = nil
        
        print("[ChatManager] User message: \(content)")
        
        // Check if model is loaded
        let modelLoaded = await LLMEngine.shared.isModelLoaded()
        let currentModel = await LLMEngine.shared.getCurrentModel()
        print("[ChatManager] Model status - Loaded: \(modelLoaded), Model: \(currentModel?.displayName ?? "None")")
        
        // Add user message
        let userMessage = ChatMessage(role: .user, content: content)
        messages.append(userMessage)
        
        do {
            // Build context
            print("[ChatManager] Building context...")
            let context = await ContextManager.shared.buildContext(
                messages: messages,
                brainQuery: content
            )
            print("[ChatManager] Context built, length: \(context.count) chars")
            
            // Create system message with context
            let systemMessage = ChatMessage(
                role: .system,
                content: context
            )
            
            // Generate response
            print("[ChatManager] Calling LLMEngine.generate()...")
            let fullMessages = [systemMessage] + messages
            let response = try await LLMEngine.shared.generate(
                messages: fullMessages,
                temperature: AppState.shared.temperature,
                maxTokens: AppState.shared.maxTokens
            )
            
            print("[ChatManager] Response received, length: \(response.count) chars")
            
            // Add assistant response
            let assistantMessage = ChatMessage(
                role: .assistant,
                content: response,
                modelUsed: currentModel?.displayName ?? "Unknown"
            )
            messages.append(assistantMessage)
            
            // Update current conversation
            if currentConversation == nil {
                currentConversation = Conversation(title: String(content.prefix(50)), messages: messages)
            } else {
                currentConversation?.messages = messages
                currentConversation?.updatedAt = Date()
            }
            
            // Save conversations
            saveConversations()
            
        } catch {
            print("[ChatManager] Error: \(error.localizedDescription)")
            self.error = error.localizedDescription
            
            // Add error message
            let errorMessage = ChatMessage(
                role: .assistant,
                content: "I encountered an error: \(error.localizedDescription). Please try again."
            )
            messages.append(errorMessage)
        }
        
        isProcessing = false
    }
    
    /// Execute a complex task with planning
    func executeTask(_ task: String) async {
        guard !isProcessing else { return }
        
        isProcessing = true
        error = nil
        
        // Add planning message
        let planningMessage = ChatMessage(
            role: .assistant,
            content: "I'm analyzing this task and creating a plan..."
        )
        messages.append(planningMessage)
        
        do {
            // Build planning context
            let planningContext = await ContextManager.shared.buildPlanningContext(
                task: task,
                userHistory: messages
            )
            
            // Create plan
            let context = PlanningContext(
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            
            var plan = try await TaskPlanner.shared.createPlan(from: task, context: context)
            
            // Update message with plan
            var planMessage = planningMessage
            planMessage.content = "Here's my plan:\n\n"
            for (index, step) in plan.steps.enumerated() {
                planMessage.content += "\(index + 1). \(step.description)\n"
            }
            planMessage.content += "\nExecuting now..."
            
            if let msgIndex = messages.firstIndex(where: { $0.id == planningMessage.id }) {
                messages[msgIndex] = planMessage
            }
            
            // Execute plan step by step
            for stepIndex in plan.steps.indices {
                var step = plan.steps[stepIndex]
                step.status = .inProgress
                plan.steps[stepIndex] = step
                
                // Update message with progress
                planMessage.content = "Executing step \(stepIndex + 1)/\(plan.steps.count): \(step.description)"
                if let msgIndex = messages.firstIndex(where: { $0.id == planningMessage.id }) {
                    messages[msgIndex] = planMessage
                }
                
                do {
                    let result = try await TaskPlanner.shared.executeStep(step, in: SystemIntegration.shared)
                    
                    var completedStep = step
                    completedStep.status = .completed
                    completedStep.result = result
                    plan.steps[stepIndex] = completedStep
                    
                } catch {
                    var failedStep = step
                    failedStep.status = .failed
                    failedStep.error = error.localizedDescription
                    plan.steps[stepIndex] = failedStep
                    
                    planMessage.content += "\n\n⚠️ Step failed: \(error.localizedDescription)"
                    if let msgIndex = messages.firstIndex(where: { $0.id == planningMessage.id }) {
                        messages[msgIndex] = planMessage
                    }
                    
                    break
                }
            }
            
            // Final message
            planMessage.content = "Task completed! I executed \(plan.steps.filter { $0.status == .completed }.count) out of \(plan.steps.count) steps successfully."
            if let msgIndex = messages.firstIndex(where: { $0.id == planningMessage.id }) {
                messages[msgIndex] = planMessage
            }
            
        } catch {
            self.error = error.localizedDescription
            
            let errorResponse = ChatMessage(
                role: .assistant,
                content: "I couldn't plan this task: \(error.localizedDescription)"
            )
            messages.append(errorResponse)
        }
        
        isProcessing = false
    }
    
    /// Start a new chat
    func startNewChat() {
        // Save current conversation if exists
        if !messages.isEmpty, var conv = currentConversation {
            conv.messages = messages
            if let index = conversations.firstIndex(where: { $0.id == conv.id }) {
                conversations[index] = conv
            } else {
                conversations.append(conv)
            }
            saveConversations()
        }
        
        // Reset for new conversation
        messages = []
        currentConversation = nil
        error = nil
    }
    
    /// Load a previous conversation
    func loadConversation(_ conversation: Conversation) {
        if var currentConv = currentConversation, !messages.isEmpty {
            currentConv.messages = messages
            if let index = conversations.firstIndex(where: { $0.id == currentConv.id }) {
                conversations[index] = currentConv
            }
        }
        
        currentConversation = conversation
        messages = conversation.messages
    }
    
    /// Export conversation to file
    func exportConversation(to url: URL) async {
        var export = "# Conversation Export\n\n"
        export += "**Date:** \(Date().formatted())\n\n"
        export += "---\n\n"
        
        for message in messages {
            let role = message.role == .user ? "User" : "Friday"
            export += "## \(role)\n"
            export += "\(message.content)\n\n"
            export += "---\n\n"
        }
        
        try? export.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Persistence
    
    private func loadConversations() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let conversationsFile = documentsPath.appendingPathComponent("Friday/conversations.json")
        
        guard let data = try? Data(contentsOf: conversationsFile),
              let loaded = try? JSONDecoder().decode([Conversation].self, from: data) else {
            return
        }
        
        conversations = loaded
    }
    
    private func saveConversations() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fridayDir = documentsPath.appendingPathComponent("Friday")
        try? FileManager.default.createDirectory(at: fridayDir, withIntermediateDirectories: true)
        
        let conversationsFile = fridayDir.appendingPathComponent("conversations.json")
        
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: conversationsFile)
    }
    
    /// Get all saved conversations
    func getConversations() -> [Conversation] {
        return conversations.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    /// Delete a conversation
    func deleteConversation(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        saveConversations()
    }
}
