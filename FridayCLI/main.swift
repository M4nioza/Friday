import Foundation

// MARK: - ANSI Color Codes
struct ANSIColors {
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let italic = "\u{001B}[3m"
    static let cyan = "\u{001B}[36m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let magenta = "\u{001B}[35m"
    static let white = "\u{001B}[37m"
    static let gray = "\u{001B}[90m"
    static let brightBlue = "\u{001B}[94m"
}

// MARK: - CLI Runner
@MainActor
final class CLIRunner {
    static let shared = CLIRunner()

    private var conversationHistory: [ChatMessage] = []

    private init() {}

    func run() async {
        printBanner()

        // Initialize brain system
        await BrainSystem.shared.initialize()

        // Check if model is loaded
        var isLoaded = await LLMEngine.shared.isModelLoaded()
        if !isLoaded {
            print("\(ANSIColors.yellow)Loading model...\n\(ANSIColors.reset)")
            do {
                try await LLMEngine.shared.loadModel(AppState.shared.currentModel)
                isLoaded = true
                print("\(ANSIColors.green)Model loaded.\(ANSIColors.reset)\n")
            } catch {
                print("\(ANSIColors.yellow)Warning: \(error.localizedDescription)\(ANSIColors.reset)")
            }
        }

        printHelp()

        while true {
            print("\n\(ANSIColors.cyan)❯\(ANSIColors.reset) ", terminator: "")
            fflush(stdout)

            guard let input = readLine(strippingNewline: true), !input.isEmpty else { continue }

            let trimmed = input.trimmingCharacters(in: .whitespaces)

            if isCommand(trimmed) {
                await handleCommand(trimmed)
            } else {
                await chat(trimmed)
            }
        }
    }

    private func isCommand(_ input: String) -> Bool {
        let commands = ["help", "ask", "task", "open", "memory", "model", "clear", "context", "tokens", "ls", "pwd", "read", "write", "delete", "exec", "exit"]
        let first = input.split(separator: " ").first.map(String.init)?.lowercased()
        return first.map { commands.contains($0) } ?? false
    }

    func printBanner() {
        let modelName = AppState.shared.currentModel.displayName
        print("""
        \(ANSIColors.cyan)╔═══════════════════════════════════════════════════════════╗
        ║\(ANSIColors.reset)  \(ANSIColors.bold)Friday CLI\(ANSIColors.reset) - Your AI Assistant                      \(ANSIColors.cyan)║
        ║                                                                   ║
        ║  Model: \(modelName)                                         ║
        ╚═══════════════════════════════════════════════════════════╝\(ANSIColors.reset)
        """)
    }

    func printHelp() {
        print("""
        \(ANSIColors.bold)Commands:\(ANSIColors.reset)
          \(ANSIColors.green)ask <question>\(ANSIColors.reset)    - Ask a question (shorthand: just type)
          \(ANSIColors.green)task <instruction>\(ANSIColors.reset) - Execute a task with planning
          \(ANSIColors.green)open <url>\(ANSIColors.reset)        - Open URL in Safari
          \(ANSIColors.green)memory <query>\(ANSIColors.reset)     - Search memories
          \(ANSIColors.green)model\(ANSIColors.reset)              - Show current model
          \(ANSIColors.green)context\(ANSIColors.reset)            - Show context settings
          \(ANSIColors.green)tokens <n>\(ANSIColors.reset)         - Set max tokens
          \(ANSIColors.green)clear\(ANSIColors.reset)              - Clear conversation
          \(ANSIColors.green)help\(ANSIColors.reset)               - Show this help

        \(ANSIColors.dim)File Operations:\(ANSIColors.reset)
          $ls <path>           - List directory
          $pwd                 - Print working directory
          $read <path>         - Read file
          $write <path> <text> - Write file
          $delete <path>       - Delete file/directory
          $exec <cmd>          - Execute shell command

        $exit or Ctrl+C to quit
        """)
    }

    func handleCommand(_ input: String) async {
        let parts = input.split(separator: " ", maxSplits: 1).map(String.init)
        let cmd = parts[0].lowercased()
        let args = parts.count > 1 ? parts[1] : ""

        switch cmd {
        case "help":
            printHelp()

        case "exit":
            print("\(ANSIColors.cyan)Goodbye!\(ANSIColors.reset)")
            exit(0)

        case "model":
            if let model = await LLMEngine.shared.getCurrentModel() {
                print("\(ANSIColors.green)Current model: \(model.displayName)\(ANSIColors.reset)")
            } else {
                print("\(ANSIColors.yellow)No model loaded\(ANSIColors.reset)")
            }

        case "clear":
            conversationHistory.removeAll()
            print("\(ANSIColors.green)Conversation cleared.\(ANSIColors.reset)")

        case "context":
            print("""
            \(ANSIColors.bold)Context Settings:\(ANSIColors.reset)
              Max tokens: \(AppState.shared.maxTokens)
              Temperature: \(String(format: "%.2f", AppState.shared.temperature))
            """)

        case "tokens":
            if let tokens = Int(args), tokens > 0 {
                AppState.shared.maxTokens = tokens
                print("\(ANSIColors.green)Max tokens set to \(tokens)\(ANSIColors.reset)")
            } else {
                print("\(ANSIColors.yellow)Usage: tokens <number>\(ANSIColors.reset)")
            }

        case "memory":
            let memories = await BrainSystem.shared.searchMemories(query: args)
            if memories.isEmpty {
                print("\(ANSIColors.dim)No memories found.\(ANSIColors.reset)")
            } else {
                print("\(ANSIColors.bold)Memories:\(ANSIColors.reset)")
                for mem in memories.prefix(10) {
                    print("  \(ANSIColors.cyan)[\(mem.category)]\(ANSIColors.reset) \(mem.title)")
                    print("  \(ANSIColors.dim)\(mem.content.prefix(100))...\n\(ANSIColors.reset)")
                }
            }

        case "ask":
            if args.isEmpty {
                print("\(ANSIColors.yellow)Usage: ask <question>\(ANSIColors.reset)")
            } else {
                await chat(args)
            }

        case "task":
            if args.isEmpty {
                print("\(ANSIColors.yellow)Usage: task <instruction>\(ANSIColors.reset)")
            } else {
                await executeTask(args)
            }

        case "open":
            if args.isEmpty {
                print("\(ANSIColors.yellow)Usage: open <url>\(ANSIColors.reset)")
            } else {
                do {
                    try await SystemIntegration.shared.openWebURL(url: args)
                    print("\(ANSIColors.green)Opened: \(args)\(ANSIColors.reset)")
                } catch {
                    print("\(ANSIColors.yellow)Failed to open: \(error.localizedDescription)\(ANSIColors.reset)")
                }
            }

        case "ls":
            let path = args.isEmpty ? FileManager.default.currentDirectoryPath : args
            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: path)
                for item in contents.sorted() {
                    print("  \(item)")
                }
            } catch {
                print("\(ANSIColors.yellow)Failed to list: \(error.localizedDescription)\(ANSIColors.reset)")
            }

        case "pwd":
            print("  \(FileManager.default.currentDirectoryPath)")

        case "read":
            if args.isEmpty {
                print("\(ANSIColors.yellow)Usage: read <path>\(ANSIColors.reset)")
            } else {
                do {
                    let content = try String(contentsOfFile: args, encoding: .utf8)
                    print("\(ANSIColors.dim)\(content.prefix(500))\(ANSIColors.reset)")
                    if content.count > 500 {
                        print("\(ANSIColors.dim)... (truncated)\(ANSIColors.reset)")
                    }
                } catch {
                    print("\(ANSIColors.yellow)Failed to read: \(error.localizedDescription)\(ANSIColors.reset)")
                }
            }

        case "write":
            let writeParts = args.split(separator: " ", maxSplits: 1).map(String.init)
            if writeParts.count < 2 {
                print("\(ANSIColors.yellow)Usage: write <path> <content>\(ANSIColors.reset)")
            } else {
                do {
                    try writeParts[1].write(toFile: writeParts[0], atomically: true, encoding: .utf8)
                    print("\(ANSIColors.green)Written to \(writeParts[0])\(ANSIColors.reset)")
                } catch {
                    print("\(ANSIColors.yellow)Failed to write: \(error.localizedDescription)\(ANSIColors.reset)")
                }
            }

        case "delete":
            if args.isEmpty {
                print("\(ANSIColors.yellow)Usage: delete <path>\(ANSIColors.reset)")
            } else {
                do {
                    try FileManager.default.removeItem(atPath: args)
                    print("\(ANSIColors.green)Deleted: \(args)\(ANSIColors.reset)")
                } catch {
                    print("\(ANSIColors.yellow)Failed to delete: \(error.localizedDescription)\(ANSIColors.reset)")
                }
            }

        case "exec":
            if args.isEmpty {
                print("\(ANSIColors.yellow)Usage: exec <command>\(ANSIColors.reset)")
            } else {
                let task = Process()
                task.launchPath = "/bin/zsh"
                task.arguments = ["-c", args]

                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = pipe

                do {
                    try task.run()
                    task.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    print("\(ANSIColors.dim)\(output)\(ANSIColors.reset)")
                } catch {
                    print("\(ANSIColors.yellow)Failed to execute: \(error.localizedDescription)\(ANSIColors.reset)")
                }
            }

        default:
            print("\(ANSIColors.yellow)Unknown command: \(cmd)\(ANSIColors.reset)")
            print("Type \(ANSIColors.green)help\(ANSIColors.reset) for available commands.")
        }
    }

    func chat(_ input: String) async {
        let userMsg = ChatMessage(role: .user, content: input)
        conversationHistory.append(userMsg)

        print("", terminator: "")

        do {
            let (response, _) = try await LLMEngine.shared.generate(
                messages: conversationHistory,
                temperature: AppState.shared.temperature,
                maxTokens: AppState.shared.maxTokens
            )

            let assistantMsg = ChatMessage(role: .assistant, content: response)
            conversationHistory.append(assistantMsg)

            print("\(ANSIColors.white)\(response)\(ANSIColors.reset)")
            print("")

            // Keep history manageable
            if conversationHistory.count > 50 {
                conversationHistory = Array(conversationHistory.suffix(40))
            }
        } catch {
            print("\(ANSIColors.yellow)Error: \(error.localizedDescription)\(ANSIColors.reset)")
        }
    }

    func executeTask(_ task: String) async {
        print("\n\(ANSIColors.magenta)Planning task...\n\(ANSIColors.reset)")

        do {
            let context = PlanningContext(
                workingDirectory: FileManager.default.currentDirectoryPath
            )

            let plan = try await TaskPlanner.shared.createPlan(from: task, context: context)

            print("\(ANSIColors.bold)Plan:\(ANSIColors.reset)")
            for (i, step) in plan.steps.enumerated() {
                print("  \(ANSIColors.cyan)\(i + 1).\(ANSIColors.reset) \(step.description)")
            }
            print("")

            print("\(ANSIColors.magenta)Executing...\n\(ANSIColors.reset)")

            for (i, step) in plan.steps.enumerated() {
                print("\(ANSIColors.cyan)[\(i + 1)/\(plan.steps.count)]\(ANSIColors.reset) \(step.description)")

                do {
                    let result = try await TaskPlanner.shared.executeStep(step, in: SystemIntegration.shared)
                    print("\(ANSIColors.green)  ✓ \(result.prefix(150))\(ANSIColors.reset)\n")
                } catch {
                    print("\(ANSIColors.yellow)  ✗ \(error.localizedDescription)\(ANSIColors.reset)\n")
                    break
                }
            }

            print("\(ANSIColors.green)Task completed.\(ANSIColors.reset)")

            // Clear extracted data cache after task
            await ExtractedDataCache.shared.clear()

        } catch {
            print("\(ANSIColors.yellow)Planning failed: \(error.localizedDescription)\(ANSIColors.reset)")
        }
    }
}

// Start the CLI
Task { @MainActor in
    await CLIRunner.shared.run()
}

RunLoop.main.run()