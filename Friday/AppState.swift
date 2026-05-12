import Foundation
import Combine

/// Global application state managed by ObservableObject
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var showSettings: Bool = false
    @Published var showMemoryBrowser: Bool = false
    @Published var showCommandPalette: Bool = false
    @Published var isProcessing: Bool = false
    @Published var currentModel: LLMModel = .defaultModel
    @Published var temperature: Double = 0.7
    @Published var maxTokens: Int = 2048
    
    private init() {
        loadSettings()
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
    }
    
    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(currentModel.name, forKey: "selectedModel")
        defaults.set(temperature, forKey: "temperature")
        defaults.set(maxTokens, forKey: "maxTokens")
    }
}
