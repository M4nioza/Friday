import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize the Brain system synchronously
        Task {
            print("[AppDelegate] Initializing Brain system...")
            await BrainSystem.shared.initialize()
            
            // Log brain stats after initialization
            let stats = BrainSystem.shared.getStatistics()
            print("[AppDelegate] Brain initialized - Total memories: \(stats.totalMemories)")
        }
        
        // Create the main window
        let contentView = ContentView()
            .environmentObject(ChatManager.shared)
            .environmentObject(AppState.shared)
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window?.center()
        window?.setFrameAutosaveName("FridayMainWindow")
        window?.title = "Friday"
        window?.minSize = NSSize(width: 700, height: 500)
        window?.contentView = NSHostingView(rootView: contentView)
        window?.makeKeyAndOrderFront(nil)
        
        // Setup menu bar
        setupMenuBar()
        
        // Activate the app
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Save brain state before closing
        Task {
            await BrainSystem.shared.saveState()
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    private func setupMenuBar() {
        let mainMenu = NSMenu()
        
        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Friday", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Friday", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Chat", action: #selector(newChat), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open Brain...", action: #selector(openBrain), keyEquivalent: "o")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Export Conversation...", action: #selector(exportConversation), keyEquivalent: "e")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)
        
        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Toggle Memory Browser", action: #selector(toggleMemoryBrowser), keyEquivalent: "m")
        viewMenu.addItem(withTitle: "Toggle Command Palette", action: #selector(toggleCommandPalette), keyEquivalent: "k")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
        
        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        
        // Help menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Friday Help", action: #selector(showHelp), keyEquivalent: "?")
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        
        NSApp.mainMenu = mainMenu
    }
    
    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
    
    @objc func showSettings() {
        Task { @MainActor in
            AppState.shared.showSettings = true
        }
    }
    
    @objc func newChat() {
        Task { @MainActor in
            ChatManager.shared.startNewChat()
        }
    }
    
    @objc func openBrain() {
        Task {
            if let brainPath = await BrainSystem.shared.brainDirectory {
                await MainActor.run {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: brainPath.path)
                }
            }
        }
    }
    
    @objc func exportConversation() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "conversation.md"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            Task {
                await ChatManager.shared.exportConversation(to: url)
            }
        }
    }
    
    @objc func toggleMemoryBrowser() {
        Task { @MainActor in
            AppState.shared.showMemoryBrowser.toggle()
        }
    }
    
    @objc func toggleCommandPalette() {
        Task { @MainActor in
            AppState.shared.showCommandPalette.toggle()
        }
    }
    
    @objc func showHelp() {
        if let url = URL(string: "https://github.com/M4nioza/Friday") {
            NSWorkspace.shared.open(url)
        }
    }
}
