import Foundation

@MainActor
func runCLI() async {
    print("Friday CLI - Initializing...")

    // Initialize brain system
    await BrainSystem.shared.initialize()

    // Check if model is loaded
    var isLoaded = await LLMEngine.shared.isModelLoaded()
    if !isLoaded {
        print("Loading model...")
        do {
            try await LLMEngine.shared.loadModel(AppState.shared.currentModel)
            isLoaded = true
            print("Model loaded.")
        } catch {
            print("Failed to load model: \(error)")
        }
    }

    print("\nFriday CLI v1.0")
    print("Model: \(AppState.shared.currentModel.displayName)")
    print("Type /help for commands, or just chat!\n")

    var conversationHistory: [ChatMessage] = []

    while true {
        print("\n> ", terminator: "")
        fflush(stdout)

        guard let input = readLine(strippingNewline: true), !input.isEmpty else { continue }

        if input.hasPrefix("/") {
            await handleCommand(input, history: &conversationHistory)
        } else {
            await chat(input, history: &conversationHistory)
        }
    }
}

@MainActor
func handleCommand(_ input: String, history: inout [ChatMessage]) async {
    let parts = input.dropFirst().split(separator: " ", maxSplits: 1).map(String.init)
    guard let cmd = parts.first?.lowercased() else { return }

    switch cmd {
    case "help":
        print("""
        Friday CLI Commands:
        /help       - Show this help
        /exit       - Exit the CLI
        /quit       - Exit the CLI
        /clear      - Clear conversation history
        /model      - Show current model
        /memory     - Search and show memories
        /context    - Show context size settings
        /tokens     - Set max tokens (e.g. /tokens 4096)
        """)

    case "exit", "quit":
        print("Goodbye!")
        exit(0)

    case "model":
        if let model = await LLMEngine.shared.getCurrentModel() {
            print("Current model: \(model.displayName)")
        } else {
            print("No model loaded")
        }

    case "clear":
        history.removeAll()
        print("Conversation cleared.")

    case "context":
        print("Max tokens: \(AppState.shared.maxTokens)")
        print("Temperature: \(AppState.shared.temperature)")

    case "tokens":
        if let tokensStr = parts.dropFirst().first, let tokens = Int(tokensStr) {
            AppState.shared.maxTokens = tokens
            print("Max tokens set to \(tokens)")
        } else {
            print("Usage: /tokens <number>")
        }

    case "memory":
        let query = parts.dropFirst().joined(separator: " ")
        let memories = await BrainSystem.shared.searchMemories(query: query.isEmpty ? "recent" : query)
        if memories.isEmpty {
            print("No memories found.")
        } else {
            for mem in memories.prefix(10) {
                print("[\(mem.category)] \(mem.title)")
                print("  \(mem.content.prefix(150))...")
                print()
            }
        }

    default:
        print("Unknown command: \(cmd). Type /help for available commands.")
    }
}

@MainActor
func chat(_ input: String, history: inout [ChatMessage]) async {
    let userMsg = ChatMessage(role: .user, content: input)
    history.append(userMsg)

    print("\nThinking...")

    do {
        let (response, _) = try await LLMEngine.shared.generate(
            messages: history,
            temperature: AppState.shared.temperature,
            maxTokens: AppState.shared.maxTokens
        )

        let assistantMsg = ChatMessage(role: .assistant, content: response)
        history.append(assistantMsg)

        print("\nFriday: \(response)")

        // Keep history manageable
        if history.count > 50 {
            history = Array(history.suffix(40))
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

// Start the CLI
Task { @MainActor in
    await runCLI()
}

RunLoop.main.run()