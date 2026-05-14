import SwiftUI

// MARK: - Theme Constants

enum FridayTheme {
    static let cornerRadius: CGFloat = 12
    static let smallCornerRadius: CGFloat = 8
    static let messagePadding: CGFloat = 12
    static let animationSpring = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let fastAnimation = Animation.easeOut(duration: 0.2)

    static let accentGradient = LinearGradient(
        colors: [.blue, Color(nsColor: .systemBlue).opacity(0.7)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let assistantBubbleBg = Color(nsColor: .controlBackgroundColor).opacity(0.6)
    static let userBubbleBg = Color.accentColor.opacity(0.12)
}

// MARK: - View Modifiers

struct CardBackground: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: FridayTheme.cornerRadius))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

struct HoverableCard: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isHovered ? Color(nsColor: .controlBackgroundColor).opacity(0.5) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: FridayTheme.cornerRadius))
            .shadow(
                color: .black.opacity(isHovered ? 0.12 : 0.04),
                radius: isHovered ? 12 : 6,
                x: 0,
                y: isHovered ? 6 : 2
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(FridayTheme.fastAnimation, value: isHovered)
    }
}

struct MessageAppear: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
            .animation(FridayTheme.animationSpring, value: appeared)
            .onAppear { appeared = true }
    }
}

extension View {
    func cardBackground() -> some View {
        modifier(CardBackground())
    }

    func hoverableCard() -> some View {
        modifier(HoverableCard())
    }

    func messageAppear() -> some View {
        modifier(MessageAppear())
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var appState: AppState

    @State private var inputText: String = ""
    @State private var showLogPanel: Bool = false
    @State private var modelLoadingProgress: Double = 0
    @State private var isModelLoading: Bool = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 180, maxWidth: 300)
        } detail: {
            VStack(spacing: 0) {
                ChatContainerView()
                    .frame(minWidth: 400)

                StatusBarView(
                    showLogPanel: $showLogPanel,
                    isModelLoading: $isModelLoading,
                    modelLoadingProgress: $modelLoadingProgress
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $appState.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $appState.showModelManager) {
            ModelManagerPanelView()
        }
        .sheet(isPresented: $appState.showMemoryBrowser) {
            MemoryBrowserView()
                .frame(minWidth: 700, idealWidth: 900, minHeight: 500, idealHeight: 700)
        }
        .overlay {
            if appState.showCommandPalette {
                CommandPaletteOverlay()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.showCommandPalette)
        .task {
            await appState.updateModelState()
            let modelStatus = appState.isModelLoaded ? "LOADED" : "NOT LOADED"
            appState.log("Model: \(appState.loadedModelName) [\(modelStatus)]", category: .model)
        }
    }
}

// MARK: - Chat Container

struct ChatContainerView: View {
    @EnvironmentObject var chatManager: ChatManager

    var body: some View {
        VStack(spacing: 0) {
            if chatManager.messages.isEmpty && !chatManager.isProcessing {
                WelcomeView()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(chatManager.messages) { message in
                                MessageView(message: message)
                                    .environmentObject(AppState.shared)
                                    .id(message.id)
                            }

                            if chatManager.isProcessing {
                                ProcessingIndicator()
                                    .id("processing")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: chatManager.messages.count) { _, _ in
                        if let lastMessage = chatManager.messages.last {
                            withAnimation(FridayTheme.animationSpring) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: chatManager.isProcessing) { _, isProcessing in
                        if isProcessing {
                            withAnimation(FridayTheme.animationSpring) {
                                proxy.scrollTo("processing", anchor: .bottom)
                            }
                        }
                    }
                }
            }

            InputAreaView()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @EnvironmentObject var chatManager: ChatManager
    @State private var suggestedPrompts: [String] = [
        "What can you help me with today?",
        "Show me my memory system",
        "Plan a task for me"
    ]
    @State private var iconPulse = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 120, height: 120)
                        .blur(radius: 25)

                    Circle()
                        .fill(FridayTheme.accentGradient)
                        .frame(width: 80, height: 80)

                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(spacing: 8) {
                    Text("Friday")
                        .font(.system(size: 32, weight: .bold, design: .rounded))

                    Text("Your local AI assistant")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }

            VStack(spacing: 12) {
                Text("Try asking me something")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    ForEach(suggestedPrompts, id: \.self) { prompt in
                        Button(action: { sendSuggestion(prompt) }) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                Text(prompt)
                                    .font(.subheadline)
                                Spacer()
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: FridayTheme.smallCornerRadius))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 40)
            }

            HStack(spacing: 24) {
                HStack(spacing: 6) {
                    Image(systemName: "command")
                        .font(.caption2)
                    Text("K")
                        .font(.caption)
                        .fontDesign(.monospaced)
                    Text("Command Palette")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "command")
                        .font(.caption2)
                    Text("N")
                        .font(.caption)
                        .fontDesign(.monospaced)
                    Text("New Chat")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.caption2)
                    Text("Memory Browser")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { iconPulse = true }
    }

    private func sendSuggestion(_ text: String) {
        Task {
            await chatManager.sendMessage(text)
        }
    }
}

// MARK: - Message View

struct MessageView: View {
    let message: ChatMessage
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false
    @State private var showCopyFeedback = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if !isUser {
                assistantAvatar
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if !isUser {
                    Text("Friday")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }

                bubbleContent
                    .modifier(MessageAppear())

                bottomRow
            }
            .frame(maxWidth: 560, alignment: isUser ? .trailing : .leading)

            if isUser {
                userAvatar
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        Text(message.content)
            .font(.body)
            .foregroundColor(isUser ? .primary : .primary)
            .textSelection(.enabled)
            .padding(FridayTheme.messagePadding)
            .background(bubbleBg)
            .clipShape(BubbleShape(isUser: isUser))
            .overlay(alignment: .topTrailing) {
                if isHovered {
                    copyButton
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
    }

    private var bubbleBg: some ShapeStyle {
        if isUser {
            return AnyShapeStyle(FridayTheme.userBubbleBg)
        } else {
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        }
    }

    private var bottomRow: some View {
        Group {
            if isHovered || !(message.actions?.isEmpty ?? true) {
                HStack(spacing: 12) {
                    if let actions = message.actions, !actions.isEmpty {
                        ForEach(actions) { action in
                            HStack(spacing: 4) {
                                Image(systemName: action.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(action.success ? .green : .red)
                                    .font(.caption2)
                                Text(action.description)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if appState.showMessageMetadata && isHovered {
                        Text(message.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if let model = message.modelUsed {
                            Text("• \(model)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let metrics = message.metrics {
                        Text(metrics)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .padding(.top, 2)
                .animation(FridayTheme.fastAnimation, value: isHovered)
            }
        }
    }

    private var copyButton: some View {
        Button(action: copyText) {
            Image(systemName: showCopyFeedback ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .padding(6)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(Circle())
        .help("Copy message")
    }

    private var assistantAvatar: some View {
        Circle()
            .fill(FridayTheme.accentGradient)
            .frame(width: 36, height: 36)
            .overlay {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.white)
                    .font(.system(size: 16))
            }
    }

    private var userAvatar: some View {
        Circle()
            .fill(Color.gray.opacity(0.4))
            .frame(width: 36, height: 36)
            .overlay {
                Image(systemName: "person.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 16))
            }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        showCopyFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopyFeedback = false
        }
    }
}

struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = FridayTheme.cornerRadius
        let tail: CGFloat = 6

        if isUser {
            path.move(to: CGPoint(x: r, y: 0))
            path.addLine(to: CGPoint(x: rect.width - r, y: 0))
            path.addQuadCurve(to: CGPoint(x: rect.width, y: r), control: CGPoint(x: rect.width, y: 0))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height - r - tail))
            path.addQuadCurve(to: CGPoint(x: rect.width - r, y: rect.height - tail), control: CGPoint(x: rect.width, y: rect.height - tail))
            path.addLine(to: CGPoint(x: rect.width - r - tail, y: rect.height - tail))
            path.addLine(to: CGPoint(x: rect.width - r - tail * 2, y: rect.height + 2))
            path.addLine(to: CGPoint(x: rect.width - r - tail * 2, y: rect.height - tail))
            path.addLine(to: CGPoint(x: r, y: rect.height - tail))
            path.addQuadCurve(to: CGPoint(x: 0, y: rect.height - tail - r), control: CGPoint(x: 0, y: rect.height - tail))
            path.addLine(to: CGPoint(x: 0, y: r))
            path.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: 0))
        } else {
            path.move(to: CGPoint(x: r, y: tail))
            path.addLine(to: CGPoint(x: rect.width - r, y: tail))
            path.addQuadCurve(to: CGPoint(x: rect.width, y: tail + r), control: CGPoint(x: rect.width, y: tail))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height - r))
            path.addQuadCurve(to: CGPoint(x: rect.width - r, y: rect.height), control: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: r + tail * 2, y: rect.height))
            path.addLine(to: CGPoint(x: r + tail, y: rect.height + 2))
            path.addLine(to: CGPoint(x: r + tail, y: rect.height))
            path.addLine(to: CGPoint(x: r, y: rect.height))
            path.addQuadCurve(to: CGPoint(x: 0, y: rect.height - r), control: CGPoint(x: 0, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: tail + r))
            path.addQuadCurve(to: CGPoint(x: r, y: tail), control: CGPoint(x: 0, y: tail))
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Processing Indicator

struct ProcessingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .offset(y: isAnimating ? -6 : 0)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: isAnimating
                    )
            }

            Text("Friday is thinking...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .onAppear { isAnimating = true }
    }
}

// MARK: - Input Area

struct InputAreaView: View {
    @EnvironmentObject var chatManager: ChatManager
    @State private var inputText: String = ""
    @State private var showSlashMenu = false
    @State private var filteredCommands: [SlashCommand] = []
    @State private var isFocused = false
    @State private var isSendPressed = false
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            if showSlashMenu && !filteredCommands.isEmpty {
                slashCommandMenu
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                inputField

                sendButtons
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 36 && event.modifierFlags.contains(.shift) {
                    DispatchQueue.main.async {
                        inputText += "\n"
                    }
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    private var inputField: some View {
        ZStack(alignment: .topLeading) {
            textEditor

            if inputText.isEmpty {
                Text("Ask Friday anything...")
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: FridayTheme.cornerRadius))
        .shadow(color: .black.opacity(0.05), radius: 8, y: -4)
    }

    private var textEditor: some View {
        TextEditor(text: $inputText)
            .font(.body)
            .frame(minHeight: 44, maxHeight: 120)
            .scrollContentBackground(.hidden)
            .padding(14)
            .background(textFieldBackground)
            .onKeyPress(.escape) {
                showSlashMenu = false
                return .handled
            }
            .onKeyPress(.return) {
                sendMessage()
                return .handled
            }
            .onChange(of: inputText) { _, newValue in
                handleTextChange(newValue)
            }
    }

    private var textFieldBackground: some View {
        RoundedRectangle(cornerRadius: FridayTheme.cornerRadius)
            .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 1.5)
            .background(
                RoundedRectangle(cornerRadius: FridayTheme.cornerRadius)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )
    }

    private func handleTextChange(_ newValue: String) {
        let words = newValue.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        if let lastWord = words.last, lastWord.hasPrefix("/") {
            showSlashMenu = true
            let query = String(lastWord.dropFirst()).lowercased()
            filteredCommands = query.isEmpty
                ? availableSlashCommands
                : availableSlashCommands.filter { $0.command.lowercased().contains(query) }
        } else {
            showSlashMenu = false
        }
    }

    private var sendButtons: some View {
        VStack(spacing: 8) {
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(
                        inputText.isEmpty || chatManager.isProcessing
                            ? .gray.opacity(0.5)
                            : .accentColor
                    )
                    .scaleEffect(isSendPressed ? 0.85 : 1.0)
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || chatManager.isProcessing)

            Button(action: sendAsTask) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 18))
                    .foregroundColor(
                        inputText.isEmpty || chatManager.isProcessing
                            ? .gray.opacity(0.5)
                            : .orange
                    )
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || chatManager.isProcessing)
            .help("Execute as multi-step task")
        }
    }

    private var slashCommandMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredCommands) { cmd in
                        Button(action: { selectCommand(cmd) }) {
                            HStack {
                                Text(cmd.command)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Text(cmd.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: FridayTheme.smallCornerRadius))
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: -2)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func selectCommand(_ cmd: SlashCommand) {
        var words = inputText.components(separatedBy: .whitespacesAndNewlines)
        _ = words.popLast()
        let newText = words.joined(separator: " ") + (words.isEmpty ? "" : " ") + cmd.template
        inputText = newText
        showSlashMenu = false
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        let text = inputText
        inputText = ""
        showSlashMenu = false
        Task {
            await chatManager.sendMessage(text)
        }
    }

    private func sendAsTask() {
        guard !inputText.isEmpty else { return }
        let text = inputText
        inputText = ""
        showSlashMenu = false
        Task {
            await chatManager.executeTask(text)
        }
    }
}

// Press events button style for scale animation
struct PressEventsButtonStyle: ButtonStyle {
    var onPress: () -> Void
    var onRelease: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { onPress() } else { onRelease() }
            }
    }
}

extension Button {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        self.buttonStyle(PressEventsButtonStyle(onPress: onPress, onRelease: onRelease))
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var appState: AppState
    @State private var hoveredConversationId: UUID?
    @State private var conversationToDelete: UUID?
    @State private var isCompact: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let compact = geometry.size.width < 160

            VStack(spacing: 0) {
                newChatButton(isCompact: compact)
                    .padding(.horizontal, compact ? 8 : 12)
                    .padding(.top, compact ? 8 : 16)
                    .padding(.bottom, compact ? 4 : 8)
                    .animation(FridayTheme.fastAnimation, value: compact)

                if !compact {
                    Divider()
                        .padding(.horizontal, 12)
                }

                conversationsList(isCompact: compact)

                if !compact {
                    Divider()
                        .padding(.horizontal, 12)
                }

                bottomToolbar(isCompact: compact)
                    .padding(.horizontal, compact ? 8 : 12)
                    .padding(.vertical, compact ? 6 : 8)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .onChange(of: geometry.size.width) { _, newWidth in
                isCompact = newWidth < 160
            }
            .onAppear {
                isCompact = geometry.size.width < 160
            }
        }
    }

    private var compactNewChatButton: some View {
        Button(action: {
            chatManager.startNewChat()
        }) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: FridayTheme.smallCornerRadius))
        }
        .buttonStyle(.plain)
        .help("New Chat")
    }

    private func newChatButton(isCompact: Bool) -> some View {
        Group {
            if isCompact {
                compactNewChatButton
            } else {
                Button(action: {
                    chatManager.startNewChat()
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                        Text("New Chat")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: FridayTheme.smallCornerRadius))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func conversationsList(isCompact: Bool) -> some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(chatManager.getConversations()) { conversation in
                    conversationRow(conversation, isCompact: isCompact)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func conversationRow(_ conversation: ChatManager.Conversation, isCompact: Bool) -> some View {
        let isSelected = chatManager.currentConversation?.id == conversation.id
        let isHovered = hoveredConversationId == conversation.id

        if isCompact {
            return AnyView(compactConversationRow(conversation, isSelected: isSelected, isHovered: isHovered))
        } else {
            return AnyView(expandedConversationRow(conversation, isSelected: isSelected, isHovered: isHovered))
        }
    }

    private func compactConversationRow(_ conversation: ChatManager.Conversation, isSelected: Bool, isHovered: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)

                Text(String(conversation.title.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .secondary)
            }

            if isHovered {
                Text(conversation.title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 52)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            chatManager.loadConversation(conversation)
        }
        .contextMenu {
            Button("Delete Conversation", role: .destructive) {
                conversationToDelete = conversation.id
            }
        }
        .alert("Delete Conversation?", isPresented: .init(
            get: { conversationToDelete != nil },
            set: { if !$0 { conversationToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { conversationToDelete = nil }
            Button("Delete", role: .destructive) {
                if let id = conversationToDelete {
                    chatManager.deleteConversation(id)
                }
                conversationToDelete = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func expandedConversationRow(_ conversation: ChatManager.Conversation, isSelected: Bool, isHovered: Bool) -> some View {
        HStack(spacing: 8) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 32)
            } else {
                Color.clear.frame(width: 3, height: 32)
            }

            Button(action: {
                chatManager.loadConversation(conversation)
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(conversation.title)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .lineLimit(1)
                            .foregroundColor(.primary)

                        if let lastMsg = conversation.messages.last {
                            Text(lastMsg.content)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Text(conversation.updatedAt, style: .relative)
                            .font(.caption2)
                            .foregroundColor(Color.secondary.opacity(0.5))
                    }

                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(
                    isHovered
                        ? Color(nsColor: .controlBackgroundColor)
                        : (isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            if isHovered {
                Button(action: { conversationToDelete = conversation.id }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .animation(FridayTheme.fastAnimation, value: isHovered)
        .onHover { hovering in
            hoveredConversationId = hovering ? conversation.id : nil
        }
        .contextMenu {
            Button("Delete Conversation", role: .destructive) {
                conversationToDelete = conversation.id
            }
        }
        .alert("Delete Conversation?", isPresented: .init(
            get: { conversationToDelete != nil },
            set: { if !$0 { conversationToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { conversationToDelete = nil }
            Button("Delete", role: .destructive) {
                if let id = conversationToDelete {
                    chatManager.deleteConversation(id)
                }
                conversationToDelete = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func bottomToolbar(isCompact: Bool) -> some View {
        VStack(spacing: 2) {
            toolbarButton(icon: "brain", label: "Memory", isCompact: isCompact, action: { appState.showMemoryBrowser = true })
            toolbarButton(icon: "command", label: "Commands", isCompact: isCompact, action: { appState.showCommandPalette = true })
            toolbarButton(icon: "cpu", label: "Models", isCompact: isCompact, action: { appState.showModelManager = true })
            toolbarButton(icon: "gearshape", label: "Settings", isCompact: isCompact, action: { appState.showSettings = true })
        }
    }

    private func toolbarButton(icon: String, label: String, isCompact: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                if !isCompact {
                    Text(label)
                        .font(.caption2)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .contentShape(Rectangle())
        .help(label)
        .animation(FridayTheme.fastAnimation, value: isCompact)
    }
}

// MARK: - Status Bar

struct StatusBarView: View {
    @Binding var showLogPanel: Bool
    @Binding var isModelLoading: Bool
    @Binding var modelLoadingProgress: Double

    @EnvironmentObject var appState: AppState
    @State private var indicatorPulse = false

    var body: some View {
        VStack(spacing: 0) {
            if showLogPanel {
                ActivityLogPanelView()
                    .frame(height: 150)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 16) {
                modelStatus

                Divider().frame(height: 16)

                mlxStatus

                Spacer()

                logToggle
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var modelStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.isModelLoaded ? Color.green : Color.red)
                .frame(width: 8, height: 8)
                .scaleEffect(indicatorPulse ? 1.2 : 1.0)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: indicatorPulse
                )
                .onAppear {
                    if appState.isModelLoaded { indicatorPulse = true }
                }

            if isModelLoading {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Loading \(appState.loadedModelName)...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(appState.isModelLoaded ? "Model: \(appState.loadedModelName)" : "No model loaded")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var mlxStatus: some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("MLX")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var logToggle: some View {
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
}

// MARK: - Activity Log Panel

struct ActivityLogPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var autoScroll: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Activity Log")
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.switch)
                    .scaleEffect(0.65)
                    .labelsHidden()

                Text("Auto-scroll")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(appState.activityLog) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: categoryIcon(entry.category))
                                    .font(.system(size: 9))
                                    .foregroundColor(categoryColor(entry.category))
                                    .frame(width: 12)
                                Text(entry.message)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(entry.timestamp, style: .time)
                                    .font(.system(size: 9))
                                    .foregroundColor(Color.secondary.opacity(0.5))
                            }
                            .id(entry.id)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                (appState.activityLog.firstIndex(where: { $0.id == entry.id }) ?? 0) % 2 == 0
                                    ? Color.clear
                                    : Color.black.opacity(0.03)
                            )
                        }
                    }
                    .padding(4)
                }
                .onChange(of: appState.activityLog.count) { _, _ in
                    if autoScroll, let lastEntry = appState.activityLog.first {
                        withAnimation {
                            proxy.scrollTo(lastEntry.id, anchor: .top)
                        }
                    }
                }
            }
            .background(Color.black.opacity(0.05))
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func categoryIcon(_ category: ActivityCategory) -> String {
        switch category {
        case .chat: return "bubble.left"
        case .model: return "cpu"
        case .memory: return "brain"
        case .system: return "gearshape"
        case .task: return "checklist"
        }
    }

    private func categoryColor(_ category: ActivityCategory) -> Color {
        switch category {
        case .chat: return .blue
        case .model: return .green
        case .memory: return .purple
        case .system: return .gray
        case .task: return .orange
        }
    }
}

// MARK: - Slash Commands

struct SlashCommand: Identifiable {
    let id = UUID()
    let command: String
    let description: String
    let template: String
}

let availableSlashCommands: [SlashCommand] = [
    SlashCommand(command: "/openURL", description: "Open a URL in Safari", template: "/openURL "),
    SlashCommand(command: "/extractWebData", description: "Extract text from the active Safari tab", template: "/extractWebData"),
    SlashCommand(command: "/saveToFile", description: "Save pending data to a file", template: "/saveToFile filename: "),
    SlashCommand(command: "/storeInMemory", description: "Store pending data in memory", template: "/storeInMemory name: "),
    SlashCommand(command: "/analyzeData", description: "Analyze or summarize pending data", template: "/analyzeData"),
    SlashCommand(command: "/launchApp", description: "Launch an application by bundle ID", template: "/launchApp bundleId: "),
    SlashCommand(command: "/closeApp", description: "Close an application", template: "/closeApp bundleId: "),
    SlashCommand(command: "/readFile", description: "Read a file", template: "/readFile path: "),
    SlashCommand(command: "/writeFile", description: "Write content to a file", template: "/writeFile path: \ncontent: "),
    SlashCommand(command: "/createDirectory", description: "Create a directory", template: "/createDirectory path: "),
    SlashCommand(command: "/deleteItem", description: "Delete a file or directory", template: "/deleteItem path: "),
    SlashCommand(command: "/executeAppleScript", description: "Execute an AppleScript", template: "/executeAppleScript script: "),
    SlashCommand(command: "/uiClick", description: "Click at coordinates", template: "/uiClick x: y: "),
    SlashCommand(command: "/uiType", description: "Type text via UI", template: "/uiType text: "),
    SlashCommand(command: "/wait", description: "Wait for seconds", template: "/wait seconds: "),
    SlashCommand(command: "/think", description: "Think for reasoning", template: "/think reasoning: "),
    SlashCommand(command: "/askUser", description: "Ask the user a question", template: "/askUser question: "),
    SlashCommand(command: "/rememberToBrain", description: "Save a fact to the Brain", template: "/rememberToBrain fact: ")
]