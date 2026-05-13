import SwiftUI

/// Command palette for quick actions
struct CommandPaletteView: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    
    let commands: [Command] = [
        // File commands
        Command(
            title: "New Chat",
            description: "Start a new conversation",
            category: .file,
            icon: "plus.circle",
            action: { await ChatManager.shared.startNewChat() }
        ),
        Command(
            title: "Open Brain Folder",
            description: "Open the memory storage folder",
            category: .file,
            icon: "folder",
            action: {
                if let path = BrainSystem.shared.brainDirectory {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path)
                }
            }
        ),
        Command(
            title: "Export Conversation",
            description: "Export current conversation to file",
            category: .file,
            icon: "square.and.arrow.up",
            action: {
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.plainText]
                savePanel.nameFieldStringValue = "conversation.md"
                
                if savePanel.runModal() == .OK, let url = savePanel.url {
                    Task {
                        await ChatManager.shared.exportConversation(to: url)
                    }
                }
            }
        ),
        
        // View commands
        Command(
            title: "Toggle Memory Browser",
            description: "Show/hide memory browser",
            category: .view,
            icon: "brain",
            action: { AppState.shared.showMemoryBrowser.toggle() }
        ),
        Command(
            title: "Toggle Sidebar",
            description: "Show/hide the sidebar",
            category: .view,
            icon: "sidebar.left",
            action: { }
        ),
        Command(
            title: "Open Settings",
            description: "Open application settings",
            category: .view,
            icon: "gear",
            action: { AppState.shared.showSettings = true }
        ),
        
        // Model commands
        Command(
            title: "Load Default Model",
            description: "Load the default LLM model",
            category: .model,
            icon: "cpu",
            action: {
                Task {
                    try? await LLMEngine.shared.loadModel(.defaultModel)
                    await AppState.shared.updateModelState()
                }
            }
        ),
        Command(
            title: "Unload Model",
            description: "Unload current model to free memory",
            category: .model,
            icon: "xmark.circle",
            action: {
                Task {
                    await LLMEngine.shared.unloadModel()
                    await AppState.shared.updateModelState()
                }
            }
        ),
        
        // Brain commands
        Command(
            title: "Search Memories",
            description: "Search through your memories",
            category: .brain,
            icon: "magnifyingglass",
            action: { AppState.shared.showMemoryBrowser = true }
        ),
        Command(
            title: "Add Memory",
            description: "Add a new memory manually",
            category: .brain,
            icon: "plus",
            action: { AppState.shared.showMemoryBrowser = true }
        ),
        Command(
            title: "View Memory Stats",
            description: "View statistics about your memory",
            category: .brain,
            icon: "chart.bar",
            action: { }
        ),
        
        // System commands
        Command(
            title: "Show System Info",
            description: "Display system information",
            category: .system,
            icon: "desktopcomputer",
            action: { }
        ),
        Command(
            title: "List Running Apps",
            description: "Show currently running applications",
            category: .system,
            icon: "app.badge",
            action: { }
        ),
        Command(
            title: "Quit Friday",
            description: "Close the application",
            category: .system,
            icon: "power",
            action: { NSApp.terminate(nil) }
        )
    ]
    
    var filteredCommands: [Command] {
        if searchText.isEmpty {
            return commands
        }
        
        let query = searchText.lowercased()
        return commands.filter {
            $0.title.lowercased().contains(query) ||
            $0.description.lowercased().contains(query) ||
            $0.category.rawValue.lowercased().contains(query)
        }
    }
    
    var groupedCommands: [Command.Category: [Command]] {
        Dictionary(grouping: filteredCommands) { $0.category }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Image(systemName: "command")
                    .foregroundColor(.secondary)
                TextField("Type a command...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($isSearchFocused)
                    .onSubmit {
                        if let first = filteredCommands.first {
                            executeCommand(first)
                        }
                    }
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Command list
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(Command.Category.allCases, id: \.self) { category in
                        if let commands = groupedCommands[category], !commands.isEmpty {
                            Section {
                                ForEach(commands) { command in
                                    CommandRowView(command: command) {
                                        executeCommand(command)
                                    }
                                }
                            } header: {
                                CommandSectionHeader(category: category)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                Text("Press Enter to execute")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(filteredCommands.count) commands")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(width: 500, height: 400)
        .onAppear {
            isSearchFocused = true
        }
    }
    
    private func executeCommand(_ command: Command) {
        dismiss()
        Task {
            await command.action()
        }
    }
}

/// Command model
struct Command: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let category: Category
    let icon: String
    let action: () async -> Void
    
    enum Category: String, CaseIterable {
        case file = "File"
        case view = "View"
        case model = "Model"
        case brain = "Memory"
        case system = "System"
    }
}

/// Command row
struct CommandRowView: View {
    let command: Command
    let onExecute: () -> Void
    
    var body: some View {
        Button(action: onExecute) {
            HStack(spacing: 12) {
                Image(systemName: command.icon)
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(command.title)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(command.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
    }
}

/// Section header for command categories
struct CommandSectionHeader: View {
    let category: Command.Category
    
    var body: some View {
        HStack {
            Text(category.rawValue)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
