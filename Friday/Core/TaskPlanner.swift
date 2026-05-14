import Foundation

/// Temporary cache for extracted web data across task execution
actor ExtractedDataCache {
    static let shared = ExtractedDataCache()
    private var webData: String?

    func store(_ data: String) {
        webData = data
    }

    func retrieve() -> String? {
        return webData
    }

    func clear() {
        webData = nil
    }

    private init() {}
}

/// Task Planner for complex multi-step operations
actor TaskPlanner {
    static let shared = TaskPlanner()
    
    private init() {}
    
    /// Represents a planned task
    struct PlannedTask: Identifiable {
        let id: UUID
        let description: String
        var steps: [TaskStep]
        var currentStepIndex: Int
        var status: TaskStatus
        let createdAt: Date
        
        init(
            id: UUID = UUID(),
            description: String,
            steps: [TaskStep],
            createdAt: Date = Date()
        ) {
            self.id = id
            self.description = description
            self.steps = steps
            self.currentStepIndex = 0
            self.status = .pending
            self.createdAt = createdAt
        }
        
        var currentStep: TaskStep? {
            guard currentStepIndex < steps.count else { return nil }
            return steps[currentStepIndex]
        }
        
        var isComplete: Bool {
            return currentStepIndex >= steps.count
        }
        
        var progress: Double {
            guard !steps.isEmpty else { return 0 }
            return Double(currentStepIndex) / Double(steps.count)
        }
    }
    
    /// Individual step in a task
    struct TaskStep: Identifiable {
        let id: UUID
        let description: String
        let action: StepAction
        var status: StepStatus
        var result: String?
        var error: String?
        
        init(
            id: UUID = UUID(),
            description: String,
            action: StepAction,
            status: StepStatus = .pending
        ) {
            self.id = id
            self.description = description
            self.action = action
            self.status = status
        }
    }
    
    enum TaskStatus {
        case pending
        case inProgress
        case completed
        case failed
        case cancelled
    }
    
    enum StepStatus {
        case pending
        case inProgress
        case completed
        case failed
        case skipped
    }
    
    enum StepAction {
        case launchApp(bundleId: String)
        case closeApp(bundleId: String)
        case readFile(path: String)
        case writeFile(path: String, content: String)
        case createDirectory(path: String)
        case deleteItem(path: String)
        case executeAppleScript(script: String)
        case uiClick(x: Int, y: Int)
        case uiType(text: String)
        case wait(seconds: Double)
        case think(reasoning: String)
        case askUser(question: String)
        case callLLM(prompt: String)
        case rememberToBrain(fact: String)
        case openURL(url: String)
        case extractWebData
        case saveToFile(filename: String)
        case storeInMemory(name: String)
        case analyzeData
    }
    
    /// Parse a user request into a structured plan
    func createPlan(from request: String, context: PlanningContext) async throws -> PlannedTask {
        // Direct command handling for slash commands
        if request.hasPrefix("/") {
            if let task = try await handleSlashCommand(request) {
                return task
            }
        }

        // Use the LLM to break down the request into steps
        let planPrompt = """
        Analyze the following user request and break it down into clear, executable steps.

        Request: \(request)

        Available capabilities:
        - Launch applications by bundle ID
        - Close applications
        - Read files and directories
        - Create, modify, and delete files
        - Execute AppleScript
        - UI automation (click, type)
        - Open URLs in Safari browser
        - Extract text data from the current web page
        - Save extracted data to a file
        - Store extracted data in memory
        - Analyze or summarize extracted data

        Context:
        - Working directory: \(context.workingDirectory)
        - Recent apps used: \(context.recentApps.joined(separator: ", "))
        - Current date: \(context.currentDate)

        Return a SINGLE valid JSON object with this exact structure:
        {
          "description": "Brief summary of the task",
          "steps": [
            {
              "description": "What this step does",
              "action": { "type": "actionTypeName", "param1": "value1", "param2": "value2" }
            },
            {
              "description": "Next step description",
              "action": { "type": "anotherActionType", "param": "value" }
            }
          ]
        }

        IMPORTANT: Return EXACTLY one JSON object with "description" (string) and "steps" (array of objects). The "steps" array MUST contain objects with "description" and "action" keys. Do NOT return multiple separate JSON objects.
        """
        
        // Get the plan from the LLM
        let (llmResponse, _) = try await LLMEngine.shared.generate(
            messages: [
                ChatMessage(role: .system, content: "You are a task planning assistant. Always respond with valid JSON only. Never include conversational text."),
                ChatMessage(role: .user, content: planPrompt)
            ],
            temperature: 0.3,
            maxTokens: 1024
        )
        
        // Clean the response from markdown blocks if they exist
        var cleanJSON = llmResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        if let startRange = cleanJSON.range(of: "```json") {
            let afterBlock = cleanJSON[startRange.upperBound...]
            if let blockEnd = afterBlock.range(of: "```") {
                cleanJSON = String(afterBlock[..<blockEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if let startRange = cleanJSON.range(of: "{"),
                  let endRange = findMatchingBrace(json: cleanJSON, from: startRange.lowerBound) {
            cleanJSON = String(cleanJSON[startRange.lowerBound...endRange.upperBound])
        }
        
        // Parse the JSON response
        guard let jsonData = cleanJSON.data(using: .utf8) else {
            throw PlanningError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        let parsedPlan: ParsedPlan
        do {
            parsedPlan = try decoder.decode(ParsedPlan.self, from: jsonData)
        } catch {
            print("[TaskPlanner] JSON Decoding error: \(error)\nRaw LLM output: \(llmResponse)")
            throw PlanningError.stepFailed("Decoder error: \(error). Clean JSON: \(cleanJSON.prefix(300))...")
        }
        
        // Convert to PlannedTask
        var steps: [TaskStep] = []
        for stepData in parsedPlan.steps {
            let action = try parseAction(from: stepData.action)
            steps.append(TaskStep(
                description: stepData.description,
                action: action
            ))
        }
        
        return PlannedTask(
            description: parsedPlan.description,
            steps: steps
        )
    }

    private func handleSlashCommand(_ command: String) async throws -> PlannedTask? {
        let parts = command.dropFirst().split(separator: " ", maxSplits: 1).map(String.init)
        guard let cmdName = parts.first else { return nil }

        var steps: [TaskStep] = []

        switch cmdName {
        case "saveToFile":
            guard parts.count > 1 else {
                throw PlanningError.stepFailed("Usage: /saveToFile filename")
            }
            steps.append(TaskStep(
                description: "Save extracted data to file: \(parts[1])",
                action: .saveToFile(filename: parts[1])
            ))

        case "storeInMemory":
            guard parts.count > 1 else {
                throw PlanningError.stepFailed("Usage: /storeInMemory name")
            }
            steps.append(TaskStep(
                description: "Store extracted data in memory as: \(parts[1])",
                action: .storeInMemory(name: parts[1])
            ))

        case "analyzeData":
            steps.append(TaskStep(
                description: "Analyze extracted data",
                action: .analyzeData
            ))

        case "openURL":
            guard parts.count > 1 else {
                throw PlanningError.stepFailed("Usage: /openURL url")
            }
            let url = parts.dropFirst().joined(separator: " ").removingPercentEncoding ?? parts.dropFirst().joined(separator: " ")
            steps.append(TaskStep(
                description: "Open URL in Safari: \(url)",
                action: .openURL(url: url)
            ))

        default:
            return nil
        }

        return PlannedTask(
            description: command,
            steps: steps
        )
    }
    
    private func parseAction(from actionData: [String: AnyCodable]) throws -> StepAction {
        guard let type = actionData["type"]?.value as? String else {
            throw PlanningError.invalidAction
        }
        
        switch type {
        case "launchApp":
            guard let bundleId = actionData["bundleId"]?.value as? String else {
                throw PlanningError.invalidAction
            }
            return .launchApp(bundleId: bundleId)
            
        case "closeApp":
            guard let bundleId = actionData["bundleId"]?.value as? String else {
                throw PlanningError.invalidAction
            }
            return .closeApp(bundleId: bundleId)
            
        case "readFile":
            guard let path = actionData["path"]?.value as? String else {
                throw PlanningError.invalidAction
            }
            return .readFile(path: path)
            
        case "writeFile":
            guard let path = actionData["path"]?.value as? String,
                  let content = actionData["content"]?.value as? String else {
                throw PlanningError.invalidAction
            }
            return .writeFile(path: path, content: content)
            
        case "createDirectory":
            guard let path = actionData["path"]?.value as? String else {
                throw PlanningError.invalidAction
            }
            return .createDirectory(path: path)
            
        case "deleteItem":
            guard let path = actionData["path"]?.value as? String else {
                throw PlanningError.invalidAction
            }
            return .deleteItem(path: path)
            
        case "executeAppleScript":
            guard let script = actionData["script"]?.value as? String else {
                throw PlanningError.invalidAction
            }
            return .executeAppleScript(script: script)
            
        case "uiClick":
            let x = actionData["x"]?.value as? Int ?? 0
            let y = actionData["y"]?.value as? Int ?? 0
            return .uiClick(x: x, y: y)
            
        case "uiType":
            guard let text = actionData["text"]?.value as? String else {
                throw PlanningError.invalidAction
            }
            return .uiType(text: text)
            
        case "wait":
            let seconds = actionData["seconds"]?.value as? Double ?? 1.0
            return .wait(seconds: seconds)
            
        case "think":
            let reasoning = actionData["reasoning"]?.value as? String ?? ""
            return .think(reasoning: reasoning)
            
        case "askUser":
            let question = actionData["question"]?.value as? String ?? ""
            return .askUser(question: question)
            
        case "callLLM":
            let prompt = actionData["prompt"]?.value as? String ?? ""
            return .callLLM(prompt: prompt)
            
        case "rememberToBrain":
            let fact = actionData["fact"]?.value as? String ?? ""
            return .rememberToBrain(fact: fact)
            
        case "openURL":
            guard let url = actionData["url"]?.value as? String else {
                throw PlanningError.invalidAction
            }
            return .openURL(url: url)
            
        case "extractWebData":
            return .extractWebData

        case "saveToFile":
            guard let filename = actionData["filename"]?.value as? String else {
                throw PlanningError.invalidAction
            }
            return .saveToFile(filename: filename)

        case "storeInMemory":
            guard let name = actionData["name"]?.value as? String else {
                throw PlanningError.invalidAction
            }
            return .storeInMemory(name: name)

        case "analyzeData":
            return .analyzeData

        default:
            throw PlanningError.unknownAction(type)
        }
    }
    
    /// Execute a single step
    func executeStep(_ step: TaskStep, in planner: SystemIntegration) async throws -> String {
        switch step.action {
        case .launchApp(let bundleId):
            try await planner.launchApplication(bundleId: bundleId)
            return "Launched \(bundleId)"
            
        case .closeApp(let bundleId):
            try await planner.closeApplication(bundleId: bundleId)
            return "Closed \(bundleId)"
            
        case .readFile(let path):
            let content = try await planner.readFile(at: path)
            return "Read file: \(path) (\(content.count) bytes)"
            
        case .writeFile(let path, let content):
            try await planner.writeFile(content: content, to: path)
            return "Wrote to file: \(path)"
            
        case .createDirectory(let path):
            try await planner.createDirectory(at: path)
            return "Created directory: \(path)"
            
        case .deleteItem(let path):
            try await planner.deleteItem(at: path)
            return "Deleted: \(path)"
            
        case .executeAppleScript(let script):
            let result = try await planner.runAppleScript(script)
            return "AppleScript result: \(result ?? "completed")"
            
        case .uiClick(let x, let y):
            try await planner.clickAt(x: x, y: y)
            return "Clicked at (\(x), \(y))"
            
        case .uiType(let text):
            try await planner.typeText(text)
            return "Typed: \(text.prefix(50))..."
            
        case .wait(let seconds):
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return "Waited \(seconds) seconds"
            
        case .think(let reasoning):
            return "Thinking: \(reasoning)"
            
        case .askUser(let question):
            return "Waiting for user input: \(question)"
            
        case .callLLM(let prompt):
            let (result, _) = try await LLMEngine.shared.generate(
                messages: [ChatMessage(role: .user, content: prompt)],
                temperature: 0.7,
                maxTokens: 1024
            )
            return "LLM response: \(result.prefix(200))..."
            
        case .rememberToBrain(let fact):
            await BrainSystem.shared.addMemory(fact: fact, category: .learned)
            return "Remembered: \(fact.prefix(50))..."
            
        case .openURL(let url):
            try await planner.openWebURL(url: url)
            return "Opened URL: \(url)"
            
        case .extractWebData:
            let data = try await planner.extractWebPageText()
            await ExtractedDataCache.shared.store(data)
            let preview = String(data.prefix(500))
            return "EXTRACTED_DATA:\(data.count) bytes extracted. DATA_PREVIEW:\(preview)"

        case .saveToFile(let filename):
            guard let data = await ExtractedDataCache.shared.retrieve() else {
                return "ERROR: No extracted data to save"
            }
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fridayDir = documentsPath.appendingPathComponent("Friday")
            try? FileManager.default.createDirectory(at: fridayDir, withIntermediateDirectories: true)
            let fileURL = fridayDir.appendingPathComponent(filename)
            try data.write(to: fileURL, atomically: true, encoding: .utf8)
            await ExtractedDataCache.shared.clear()
            return "Saved \(data.count) bytes to \(filename)"

        case .storeInMemory(let name):
            guard let data = await ExtractedDataCache.shared.retrieve() else {
                return "ERROR: No extracted data to store"
            }
            await BrainSystem.shared.addMemory(fact: "[\(name)]\n\(data)", category: .learned)
            await ExtractedDataCache.shared.clear()
            return "Stored \(data.count) bytes in memory as '\(name)'"

        case .analyzeData:
            guard let data = await ExtractedDataCache.shared.retrieve() else {
                return "ERROR: No extracted data to analyze"
            }
            let (summary, _) = try await LLMEngine.shared.generate(
                messages: [
                    ChatMessage(role: .system, content: "You are a data analysis assistant. Summarize the provided data concisely."),
                    ChatMessage(role: .user, content: "Please summarize this data:\n\n\(data.prefix(2000))")
                ],
                temperature: 0.5,
                maxTokens: 1500
            )
            return "ANALYSIS:\n\(summary)"
        }
    }

    private func findMatchingBrace(json: String, from startIndex: String.Index) -> ClosedRange<String.Index>? {
        var depth = 0
        var inString = false
        var escaped = false
        var i = startIndex

        while i < json.endIndex {
            let char = json[i]
            if escaped {
                escaped = false
                i = json.index(after: i)
                continue
            }
            if char == "\\" {
                escaped = true
                i = json.index(after: i)
                continue
            }
            if char == "\"" {
                inString.toggle()
                i = json.index(after: i)
                continue
            }
            if inString {
                i = json.index(after: i)
                continue
            }

            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    return startIndex...i
                }
            }
            i = json.index(after: i)
        }
        return nil
    }
}

/// Planning context for better task understanding
struct PlanningContext {
    let workingDirectory: String
    let recentApps: [String]
    let currentDate: Date
    let userPreferences: [String: String]
    
    init(
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        recentApps: [String] = [],
        currentDate: Date = Date(),
        userPreferences: [String: String] = [:]
    ) {
        self.workingDirectory = workingDirectory
        self.recentApps = recentApps
        self.currentDate = currentDate
        self.userPreferences = userPreferences
    }
}

// MARK: - Parsed Plan Types

struct ParsedPlan: Codable {
    let description: String
    let steps: [ParsedStep]
}

struct ParsedStep: Codable {
    let description: String
    let action: [String: AnyCodable]
}

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = ""
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        }
    }
}

/// Planning errors
enum PlanningError: LocalizedError {
    case invalidResponse
    case invalidAction
    case unknownAction(String)
    case stepFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Failed to parse the planning response"
        case .invalidAction:
            return "Invalid action format in plan"
        case .unknownAction(let type):
            return "Unknown action type: \(type)"
        case .stepFailed(let reason):
            return "Step execution failed: \(reason)"
        }
    }
}
