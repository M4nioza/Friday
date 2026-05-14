import SwiftUI

struct CommandPaletteOverlay: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    @State private var selectedIndex: Int = 0
    @State private var fadeIn = false

    let commands: [Command] = [
        Command(title: "New Chat", description: "Start a new conversation", category: .file, icon: "plus.circle", action: { await ChatManager.shared.startNewChat() }),
        Command(title: "Open Brain Folder", description: "Open the memory storage folder", category: .file, icon: "folder", action: { if let path = BrainSystem.shared.brainDirectory { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path) } }),
        Command(title: "Export Conversation", description: "Export current conversation to file", category: .file, icon: "square.and.arrow.up", action: { let savePanel = NSSavePanel(); savePanel.allowedContentTypes = [.plainText]; savePanel.nameFieldStringValue = "conversation.md"; if savePanel.runModal() == .OK, let url = savePanel.url { Task { await ChatManager.shared.exportConversation(to: url) } } }),
        Command(title: "Toggle Memory Browser", description: "Show/hide memory browser", category: .view, icon: "brain", action: { AppState.shared.showMemoryBrowser.toggle() }),
        Command(title: "Open Settings", description: "Open application settings", category: .view, icon: "gear", action: { AppState.shared.showSettings = true }),
        Command(title: "Load Default Model", description: "Load the default LLM model", category: .model, icon: "cpu", action: { Task { try? await LLMEngine.shared.loadModel(.defaultModel); await AppState.shared.updateModelState() } }),
        Command(title: "Unload Model", description: "Unload current model to free memory", category: .model, icon: "xmark.circle", action: { Task { await LLMEngine.shared.unloadModel(); await AppState.shared.updateModelState() } }),
        Command(title: "Search Memories", description: "Search through your memories", category: .brain, icon: "magnifyingglass", action: { AppState.shared.showMemoryBrowser = true }),
        Command(title: "Add Memory", description: "Add a new memory manually", category: .brain, icon: "plus", action: { AppState.shared.showMemoryBrowser = true }),
        Command(title: "Show System Info", description: "Display system information", category: .system, icon: "desktopcomputer", action: { }),
        Command(title: "Quit Friday", description: "Close the application", category: .system, icon: "power", action: { NSApp.terminate(nil) })
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

    var sortedCategories: [Command.Category] {
        Command.Category.allCases.filter { groupedCommands[$0] != nil }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
                .onAppear { withAnimation(.easeOut(duration: 0.15)) { fadeIn = true } }

            panel
                .scaleEffect(fadeIn ? 1 : 0.95)
                .opacity(fadeIn ? 1 : 0)
        }
        .transition(.opacity)
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onChange(of: filteredCommands.count) { _, _ in selectedIndex = 0 }
        .onChange(of: searchText) { _, _ in selectedIndex = 0 }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            headerSearch
            Divider()
            commandList
            Divider()
            footer
        }
        .frame(width: 540, height: 440)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 12)
    }

    private var headerSearch: some View {
        HStack(spacing: 12) {
            Image(systemName: "command")
                .font(.title3)
                .foregroundColor(.secondary)

            TextField("Type a command or search...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var commandList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(sortedCategories, id: \.self) { category in
                    Section {
                        ForEach(Array((groupedCommands[category] ?? []).enumerated()), id: \.element.id) { index, command in
                            let globalIndex = flatIndex(category: category, localIndex: index)
                            CommandRowView(command: command, isSelected: globalIndex == selectedIndex) {
                                executeCommand(command)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
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

    private var footer: some View {
        HStack(spacing: 16) {
            Text("\(filteredCommands.count) commands")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "escape")
                    .font(.caption2)
                Text("Dismiss")
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func flatIndex(category: Command.Category, localIndex: Int) -> Int {
        var index = 0
        for cat in sortedCategories {
            if cat == category { return index + localIndex }
            index += (groupedCommands[cat]?.count ?? 0)
        }
        return 0
    }

    private func executeCommand(_ command: Command) {
        dismiss()
        Task { await command.action() }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.12)) {
            appState.showCommandPalette = false
        }
    }
}

// MARK: - Command Row

struct CommandRowView: View {
    let command: Command
    let isSelected: Bool
    let onExecute: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.icon)
                .font(.title3)
                .foregroundColor(isSelected ? .white : .accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.body)
                    .foregroundColor(isSelected ? .white : .primary)
                Text(command.description)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
            }

            Spacer()

            Text(command.category.rawValue)
                .font(.caption2)
                .foregroundColor(isSelected ? .white.opacity(0.5) : Color.secondary.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    isSelected
                        ? Color.white.opacity(0.15)
                        : Color.secondary.opacity(0.1)
                )
                .clipShape(Capsule())

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(isSelected ? .white.opacity(0.5) : .secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Section Header

struct CommandSectionHeader: View {
    let category: Command.Category

    var body: some View {
        HStack {
            Text(category.rawValue.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
    }
}

// MARK: - Command Model

struct Command: Identifiable, Equatable {
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

    static func == (lhs: Command, rhs: Command) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Legacy sheet-based view (kept for compatibility)

struct CommandPaletteView: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool

    let commands: [Command] = [
        Command(title: "New Chat", description: "Start a new conversation", category: .file, icon: "plus.circle", action: { await ChatManager.shared.startNewChat() }),
        Command(title: "Open Brain Folder", description: "Open the memory storage folder", category: .file, icon: "folder", action: { if let path = BrainSystem.shared.brainDirectory { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path) } }),
        Command(title: "Export Conversation", description: "Export current conversation to file", category: .file, icon: "square.and.arrow.up", action: { let savePanel = NSSavePanel(); savePanel.allowedContentTypes = [.plainText]; savePanel.nameFieldStringValue = "conversation.md"; if savePanel.runModal() == .OK, let url = savePanel.url { Task { await ChatManager.shared.exportConversation(to: url) } } }),
        Command(title: "Toggle Memory Browser", description: "Show/hide memory browser", category: .view, icon: "brain", action: { AppState.shared.showMemoryBrowser.toggle() }),
        Command(title: "Open Settings", description: "Open application settings", category: .view, icon: "gear", action: { AppState.shared.showSettings = true }),
        Command(title: "Load Default Model", description: "Load the default LLM model", category: .model, icon: "cpu", action: { Task { try? await LLMEngine.shared.loadModel(.defaultModel); await AppState.shared.updateModelState() } }),
        Command(title: "Unload Model", description: "Unload current model to free memory", category: .model, icon: "xmark.circle", action: { Task { await LLMEngine.shared.unloadModel(); await AppState.shared.updateModelState() } }),
        Command(title: "Search Memories", description: "Search through your memories", category: .brain, icon: "magnifyingglass", action: { AppState.shared.showMemoryBrowser = true }),
        Command(title: "Add Memory", description: "Add a new memory manually", category: .brain, icon: "plus", action: { AppState.shared.showMemoryBrowser = true }),
        Command(title: "Show System Info", description: "Display system information", category: .system, icon: "desktopcomputer", action: { }),
        Command(title: "Quit Friday", description: "Close the application", category: .system, icon: "power", action: { NSApp.terminate(nil) })
    ]

    var filteredCommands: [Command] {
        if searchText.isEmpty { return commands }
        let query = searchText.lowercased()
        return commands.filter {
            $0.title.lowercased().contains(query) ||
            $0.description.lowercased().contains(query) ||
            $0.category.rawValue.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Command Palette")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Type a command...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($isSearchFocused)
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

            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(Command.Category.allCases, id: \.self) { category in
                        let filtered = filteredCommands.filter { $0.category == category }
                        if !filtered.isEmpty {
                            Section {
                                ForEach(filtered) { command in
                                    CommandPaletteRowView(command: command) {
                                        dismiss()
                                        Task { await command.action() }
                                    }
                                }
                            } header: {
                                CommandPaletteSectionHeader(category: category)
                            }
                        }
                    }
                }
            }

            Divider()

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
        .onAppear { isSearchFocused = true }
    }
}

struct CommandPaletteRowView: View {
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

                Text(command.category.rawValue)
                    .font(.caption2)
                    .foregroundColor(Color.secondary.opacity(0.6))

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct CommandPaletteSectionHeader: View {
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