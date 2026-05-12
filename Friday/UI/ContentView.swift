import SwiftUI

/// Main content view
struct ContentView: View {
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var appState: AppState
    
    @State private var inputText: String = ""
    @State private var showingSidebar: Bool = true
    
    var body: some View {
        NavigationSplitView {
            // Sidebar with conversations and memory access
            SidebarView()
                .frame(minWidth: 250)
        } detail: {
            // Main chat area
            ChatContainerView()
                .frame(minWidth: 400)
        }
        .sheet(isPresented: $appState.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $appState.showMemoryBrowser) {
            MemoryBrowserView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .sheet(isPresented: $appState.showCommandPalette) {
            CommandPaletteView()
        }
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
                    .contextMenu {
                        Button("Delete") {
                            chatManager.deleteConversation(conversation.id)
                        }
                    }
                }
            }
            
            Section("Actions") {
                Button(action: { chatManager.startNewChat() }) {
                    Label("New Chat", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                
                Button(action: { appState.showMemoryBrowser = true }) {
                    Label("Memory Browser", systemImage: "brain")
                }
                .buttonStyle(.plain)
                
                Button(action: { appState.showCommandPalette = true }) {
                    Label("Command Palette", systemImage: "command")
                }
                .buttonStyle(.plain)
            }
            
            Section("Quick Actions") {
                NavigationLink {
                    ModelSettingsView()
                } label: {
                    Label("Model Settings", systemImage: "cpu")
                }
                
                NavigationLink {
                    SystemStatusView()
                } label: {
                    Label("System Status", systemImage: "desktopcomputer")
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button(action: { appState.showSettings = true }) {
                    Image(systemName: "gear")
                }
            }
        }
    }
}
