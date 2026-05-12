import Foundation

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
    }
    
    /// Parse a user request into a structured plan
    func createPlan(from request: String, context: PlanningContext) async throws -> PlannedTask {
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
        
        Context:
        - Working directory: \(context.workingDirectory)
        - Recent apps used: \(context.recentApps.joined(separator: ", "))
        - Current date: \(context.currentDate)
        
        Return a JSON plan with:
        - description: Summary of the task
        - steps: Array of steps, each with:
          - description: What this step does
          - action: The action type and parameters
        
        Be specific and break down complex tasks into atomic steps.
        Format the response as valid JSON only.
        """
        
        // Get the plan from the LLM
        let llmResponse = try await LLMEngine.shared.generate(
            messages: [
                ChatMessage(role: .system, content: "You are a task planning assistant. Always respond with valid JSON only."),
                ChatMessage(role: .user, content: planPrompt)
            ],
            temperature: 0.3,
            maxTokens: 1024
        )
        
        // Parse the JSON response
        guard let jsonData = llmResponse.data(using: .utf8) else {
            throw PlanningError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        let parsedPlan = try decoder.decode(ParsedPlan.self, from: jsonData)
        
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
    
    private func parseAction(from actionData: [String: Any]) throws -> StepAction {
        guard let type = actionData["type"] as? String else {
            throw PlanningError.invalidAction
        }
        
        switch type {
        case "launchApp":
            guard let bundleId = actionData["bundleId"] as? String else {
                throw PlanningError.invalidAction
            }
            return .launchApp(bundleId: bundleId)
            
        case "closeApp":
            guard let bundleId = actionData["bundleId"] as? String else {
                throw PlanningError.invalidAction
            }
            return .closeApp(bundleId: bundleId)
            
        case "readFile":
            guard let path = actionData["path"] as? String else {
                throw PlanningError.invalidAction
            }
            return .readFile(path: path)
            
        case "writeFile":
            guard let path = actionData["path"] as? String,
                  let content = actionData["content"] as? String else {
                throw PlanningError.invalidAction
            }
            return .writeFile(path: path, content: content)
            
        case "createDirectory":
            guard let path = actionData["path"] as? String else {
                throw PlanningError.invalidAction
            }
            return .createDirectory(path: path)
            
        case "deleteItem":
            guard let path = actionData["path"] as? String else {
                throw PlanningError.invalidAction
            }
            return .deleteItem(path: path)
            
        case "executeAppleScript":
            guard let script = actionData["script"] as? String else {
                throw PlanningError.invalidAction
            }
            return .executeAppleScript(script: script)
            
        case "uiClick":
            let x = actionData["x"] as? Int ?? 0
            let y = actionData["y"] as? Int ?? 0
            return .uiClick(x: x, y: y)
            
        case "uiType":
            guard let text = actionData["text"] as? String else {
                throw PlanningError.invalidAction
            }
            return .uiType(text: text)
            
        case "wait":
            let seconds = actionData["seconds"] as? Double ?? 1.0
            return .wait(seconds: seconds)
            
        case "think":
            let reasoning = actionData["reasoning"] as? String ?? ""
            return .think(reasoning: reasoning)
            
        case "askUser":
            let question = actionData["question"] as? String ?? ""
            return .askUser(question: question)
            
        case "callLLM":
            let prompt = actionData["prompt"] as? String ?? ""
            return .callLLM(prompt: prompt)
            
        case "rememberToBrain":
            let fact = actionData["fact"] as? String ?? ""
            return .rememberToBrain(fact: fact)
            
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
            let result = try await LLMEngine.shared.generate(
                messages: [ChatMessage(role: .user, content: prompt)],
                temperature: 0.7,
                maxTokens: 1024
            )
            return "LLM response: \(result.prefix(200))..."
            
        case .rememberToBrain(let fact):
            await BrainSystem.shared.addMemory(fact: fact, category: .learned)
            return "Remembered: \(fact.prefix(50))..."
        }
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
