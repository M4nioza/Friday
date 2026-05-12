import SwiftUI

/// Main content view
struct ContentView: View {
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var appState: AppState
    
    @State private var inputText: String = ""
    @State private var showingSidebar: Bool = true
    @State private var showLogPanel: Bool = false
    @State private var isModelLoaded: Bool = false
    @State private var currentModelName: String = "No model"
    @State private var logMessages: [String] = []
    @State private var modelLoadingProgress: Double = 0
    @State private var isModelLoading: Bool = false
    
    var body: some View {
        NavigationSplitView {
            // Sidebar with conversations and memory access
            SidebarView()
                .frame(minWidth: 250)
        } detail: {
            // Main chat area with status bar
            VStack(spacing: 0) {
                ChatContainerView()
                    .frame(minWidth: 400)
                
                // Status bar at bottom
                StatusBarView(
                    isModelLoaded: $isModelLoaded,
                    currentModelName: $currentModelName,
                    logMessages: $logMessages,
                    showLogPanel: $showLogPanel,
                    isModelLoading: $isModelLoading,
                    modelLoadingProgress: $modelLoadingProgress
                )
            }
        }
        .sheet(isPresented: $appState.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $appState.showModelManager) {
            ModelManagerPanelView()
        }
        .sheet(isPresented: $appState.showMemoryBrowser) {
            MemoryBrowserView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .sheet(isPresented: $appState.showCommandPalette) {
            CommandPaletteView()
        }
        .task {
            await checkModelStatus()
        }
        .task {
            // Periodically update model status every 2 seconds
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await checkModelStatus()
            }
        }
    }
    
    private func checkModelStatus() async {
        isModelLoaded = await LLMEngine.shared.isModelLoaded()
        if let model = await LLMEngine.shared.getCurrentModel() {
            currentModelName = model.displayName
        }
        
        // Log initial status
        addLog("Friday started. Model: \(currentModelName) [\(isModelLoaded ? "LOADED" : "NOT LOADED")]")
    }
    
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logMessages.insert("[\(timestamp)] \(message)", at: 0)
        if logMessages.count > 100 {
            logMessages.removeLast()
        }
        print("[Status] \(message)")
    }
}

/// Chat container with messages and input
struct ChatContainerView: View {
    @EnvironmentObject var chatManager: ChatManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(chatManager.messages) { message in
                            MessageView(message: message)
                                .id(message.id)
                        }
                        
                        if chatManager.isProcessing {
                            ProcessingIndicator()
                        }
                    }
                    .padding()
                }
                .onChange(of: chatManager.messages.count) { _, _ in
                    if let lastMessage = chatManager.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input area
            InputAreaView()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Individual message bubble
struct MessageView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                // Assistant avatar
                Circle()
                    .fill(Color.blue.gradient)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                    }
            } else {
                Spacer(minLength: 48)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                // Role label
                Text(message.role == .user ? "You" : "Friday")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Message content
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                
                // Actions if any
                if let actions = message.actions, !actions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(actions) { action in
                            HStack(spacing: 4) {
                                Image(systemName: action.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(action.success ? .green : .red)
                                Text(action.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                
                // Timestamp and model info
                HStack {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let model = message.modelUsed {
                        Text("• \(model)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if message.role == .user {
                // User avatar
                Circle()
                    .fill(Color.gray.gradient)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "person.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                    }
            } else {
                Spacer(minLength: 48)
            }
        }
        .padding(.horizontal)
    }
}

/// Processing indicator
struct ProcessingIndicator: View {
    @State private var animationOffset: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .offset(y: animationOffset + CGFloat(index) * 4)
            }
        }
        .padding()
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                animationOffset = -4
            }
        }
    }
}

/// Input area with text field and send button
struct InputAreaView: View {
    @EnvironmentObject var chatManager: ChatManager
    @State private var inputText: String = ""
    
    var body: some View {
        VStack(spacing: 8) {
            Divider()
            
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Ask Friday anything...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...5)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .onSubmit {
                        sendMessage()
                    }
                
                VStack(spacing: 8) {
                    // Send button
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(inputText.isEmpty ? .gray : .blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty || chatManager.isProcessing)
                    
                    // Task mode toggle
                    Button(action: sendAsTask) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 20))
                            .foregroundColor(inputText.isEmpty ? .gray : .orange)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty || chatManager.isProcessing)
                    .help("Execute as multi-step task")
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        let text = inputText
        inputText = ""
        Task {
            await chatManager.sendMessage(text)
        }
    }
    
    private func sendAsTask() {
        guard !inputText.isEmpty else { return }
        let text = inputText
        inputText = ""
        Task {
            await chatManager.executeTask(text)
        }
    }
}

/// Sidebar with conversations list
struct SidebarView: View {
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        List {
            Section("Conversations") {
                ForEach(chatManager.getConversations()) { conversation in
                    HStack {
                        Button(action: {
                            chatManager.loadConversation(conversation)
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversation.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(conversation.updatedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Button(action: {
                            chatManager.deleteConversation(conversation.id)
                        }) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Section("Actions") {
                Button(action: {
                    print("[Sidebar] New Chat button pressed")
                    chatManager.startNewChat()
                }) {
                    Label("New Chat", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    appState.showMemoryBrowser = true
                }) {
                    Label("Memory Browser", systemImage: "brain")
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    appState.showCommandPalette = true
                }) {
                    Label("Command Palette", systemImage: "command")
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    appState.showSettings = true
                }) {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.plain)
            }
            
            Section("Model") {
                Button(action: {
                    appState.showModelManager = true
                }) {
                    Label("Model Manager", systemImage: "cpu")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
    }
}

/// Status bar showing model status and logs at the bottom of the app
struct StatusBarView: View {
    @Binding var isModelLoaded: Bool
    @Binding var currentModelName: String
    @Binding var logMessages: [String]
    @Binding var showLogPanel: Bool
    @Binding var isModelLoading: Bool
    @Binding var modelLoadingProgress: Double
    
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Expandable log panel
            if showLogPanel {
                LogPanelView(logMessages: $logMessages)
                    .frame(height: 150)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Main status bar
            HStack(spacing: 16) {
                // Model status indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(isModelLoaded ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    
                    if isModelLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Loading \(currentModelName)...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(isModelLoaded ? "Model: \(currentModelName)" : "No model loaded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                    .frame(height: 16)
                
                // MLX status
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("MLX")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Toggle log panel button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showLogPanel.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: showLogPanel ? "chevron.down" : "chevron.up")
                            .font(.caption)
                        Text("Logs")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

/// Log panel showing application logs
struct LogPanelView: View {
    @Binding var logMessages: [String]
    @State private var autoScroll: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Activity Log")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
                    .font(.caption2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
            
            // Log messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logMessages.enumerated()), id: \.offset) { index, message in
                            Text(message)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .id(index)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: logMessages.count) { _, _ in
                    if autoScroll, let lastIndex = logMessages.indices.last {
                        withAnimation {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color.black.opacity(0.1))
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
