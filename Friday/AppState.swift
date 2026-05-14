import Foundation
import Combine

/// Global application state managed by ObservableObject
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var showSettings: Bool = false
    @Published var showModelManager: Bool = false
    @Published var showMemoryBrowser: Bool = false
    @Published var showCommandPalette: Bool = false
    @Published var isProcessing: Bool = false
    @Published var currentModel: LLMModel = .defaultModel
    @Published var temperature: Double = 0.7
    @Published var maxTokens: Int = 150000
    @Published var showMessageMetadata: Bool = false
    @Published var showPerformanceMetrics: Bool = false
    @Published var pendingExtractedData: String?
    
    /// Activity log for tracking app events
    @Published var activityLog: [ActivityLogEntry] = []
    
    /// Current loaded model state
    @Published var isModelLoaded: Bool = false
    @Published var loadedModelName: String = "No model"
    
    private init() {
        loadSettings()
        log("Friday started", category: .system)
    }
    
    /// Update model loaded state
    func updateModelState() async {
        isModelLoaded = await LLMEngine.shared.isModelLoaded()
        if let model = await LLMEngine.shared.getCurrentModel() {
            loadedModelName = model.displayName
        } else {
            loadedModelName = "No model"
        }
    }
    
    /// Log an activity event
    func log(_ message: String, category: ActivityCategory = .system) {
        let entry = ActivityLogEntry(
            timestamp: Date(),
            message: message,
            category: category
        )
        activityLog.insert(entry, at: 0)
        
        // Keep only last 500 entries
        if activityLog.count > 500 {
            activityLog.removeLast()
        }
        
        // Also print for debugging
        print("[\(category.rawValue.uppercased())] \(message)")
    }
    
    /// Clear all activity logs
    func clearLog() {
        activityLog.removeAll()
    }
    
    /// Get formatted log messages for display
    func getLogMessages() -> [String] {
        return activityLog.map { entry in
            let timeStr = DateFormatter.localizedString(from: entry.timestamp, dateStyle: .none, timeStyle: .medium)
            return "[\(timeStr)] [\(entry.category.rawValue.uppercased())] \(entry.message)"
        }
    }
    
    func loadSettings() {
        let defaults = UserDefaults.standard
        
        if let modelName = defaults.string(forKey: "selectedModel") {
            currentModel = LLMModel.allModels.first { $0.name == modelName } ?? .defaultModel
        }
        
        if defaults.object(forKey: "temperature") != nil {
            temperature = defaults.double(forKey: "temperature")
        }
        
        if defaults.object(forKey: "maxTokens") != nil {
            maxTokens = defaults.integer(forKey: "maxTokens")
        }

        if defaults.object(forKey: "showMessageMetadata") != nil {
            showMessageMetadata = defaults.bool(forKey: "showMessageMetadata")
        }

        if defaults.object(forKey: "showPerformanceMetrics") != nil {
            showPerformanceMetrics = defaults.bool(forKey: "showPerformanceMetrics")
        }
    }
    
    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(currentModel.name, forKey: "selectedModel")
        defaults.set(temperature, forKey: "temperature")
        defaults.set(maxTokens, forKey: "maxTokens")
        defaults.set(showMessageMetadata, forKey: "showMessageMetadata")
        defaults.set(showPerformanceMetrics, forKey: "showPerformanceMetrics")
    }
}

enum ActivityCategory: String {
    case chat = "chat"
    case model = "model"
    case memory = "memory"
    case system = "system"
    case task = "task"
}

struct ActivityLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let category: ActivityCategory
}