import Foundation
import AppKit

/// System integration for controlling applications, files, and UI automation
actor SystemIntegration {
    static let shared = SystemIntegration()
    
    private init() {}
    
    // MARK: - Application Control
    
    /// Launch an application by bundle ID
    func launchApplication(bundleId: String) async throws {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else {
            // App not running, launch it
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
                throw SystemError.appNotFound(bundleId)
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            try await NSWorkspace.shared.openApplication(at: url, configuration: config)
            return
        }
        
        // App is already running, just activate it
        app.activate()
    }
    
    /// Close an application by bundle ID
    func closeApplication(bundleId: String) async throws {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else {
            throw SystemError.appNotRunning(bundleId)
        }
        
        // Use AppleScript to quit the app
        let script = """
        tell application id "\(bundleId)"
            quit
        end tell
        """
        
        try await runAppleScript(script)
    }
    
    /// Get list of running applications
    func getRunningApplications() -> [RunningApp] {
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleId = app.bundleIdentifier,
                  let name = app.localizedName else { return nil }
            return RunningApp(
                name: name,
                bundleId: bundleId,
                isActive: app.isActive
            )
        }
    }
    
    // MARK: - File System Operations
    
    /// Read a file at the given path
    func readFile(at path: String) async throws -> String {
        let expandedPath = NSString(string: path).expandingTildeInPath
        
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw SystemError.fileNotFound(path)
        }
        
        return try String(contentsOfFile: expandedPath, encoding: .utf8)
    }
    
    /// Write content to a file
    func writeFile(content: String, to path: String) async throws {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        
        // Create parent directories if needed
        let parentDir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    /// Read directory contents
    func readDirectory(at path: String) async throws -> [FileItem] {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw SystemError.directoryNotFound(path)
        }
        
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        return contents.compactMap { fileURL in
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]),
                  let isDirectory = resourceValues.isDirectory else { return nil }
            
            return FileItem(
                name: fileURL.lastPathComponent,
                path: fileURL.path,
                isDirectory: isDirectory,
                size: resourceValues.fileSize ?? 0,
                modifiedDate: resourceValues.contentModificationDate ?? Date()
            )
        }
    }
    
    /// Create a directory
    func createDirectory(at path: String) async throws {
        let expandedPath = NSString(string: path).expandingTildeInPath
        try FileManager.default.createDirectory(atPath: expandedPath, withIntermediateDirectories: true)
    }
    
    /// Delete a file or directory
    func deleteItem(at path: String) async throws {
        let expandedPath = NSString(string: path).expandingTildeInPath
        try FileManager.default.removeItem(atPath: expandedPath)
    }
    
    /// Copy item from source to destination
    func copyItem(from source: String, to destination: String) async throws {
        let expandedSource = NSString(string: source).expandingTildeInPath
        let expandedDest = NSString(string: destination).expandingTildeInPath
        try FileManager.default.copyItem(atPath: expandedSource, toPath: expandedDest)
    }
    
    /// Move item from source to destination
    func moveItem(from source: String, to destination: String) async throws {
        let expandedSource = NSString(string: source).expandingTildeInPath
        let expandedDest = NSString(string: destination).expandingTildeInPath
        try FileManager.default.moveItem(atPath: expandedSource, toPath: expandedDest)
    }
    
    /// Check if file exists
    func fileExists(at path: String) -> Bool {
        let expandedPath = NSString(string: path).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expandedPath)
    }
    
    // MARK: - AppleScript
    
    /// Run AppleScript and return the result
    func runAppleScript(_ script: String) async throws -> String? {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                if let scriptObject = NSAppleScript(source: script) {
                    let output = scriptObject.executeAndReturnError(&error)
                    if let error = error {
                        let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                        continuation.resume(throwing: SystemError.appleScriptFailed(errorMessage))
                    } else {
                        continuation.resume(returning: output.stringValue)
                    }
                } else {
                    continuation.resume(throwing: SystemError.appleScriptFailed("Failed to create AppleScript"))
                }
            }
        }
    }
    
    // MARK: - Web Automation
    
    /// Open a URL in Safari
    func openWebURL(url: String) async throws {
        let script = """
        tell application "Safari"
            activate
            if (count of windows) = 0 then
                make new document with properties {URL:"\(url)"}
            else
                tell window 1 to make new tab with properties {URL:"\(url)"}
                set current tab of window 1 to tab (count of tabs of window 1) of window 1
            end if
        end tell
        """
        _ = try await runAppleScript(script)
        // Wait for page to load
        try await Task.sleep(nanoseconds: 2_000_000_000)
    }
    
    /// Extract text from the active Safari tab
    func extractWebPageText() async throws -> String {
        let script = """
        tell application "Safari"
            if (count of documents) = 0 then return ""
            return text of document 1
        end tell
        """
        let result = try await runAppleScript(script)
        return result ?? ""
    }
    
    // MARK: - UI Automation
    
    /// Click at screen coordinates
    func clickAt(x: Int, y: Int) async throws {
        // Use CGEvent to simulate a click
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: CGFloat(x), y: CGFloat(y)), mouseButton: .left) else {
            throw SystemError.uiAutomationFailed("Failed to create mouse event")
        }
        
        event.post(tap: .cghidEventTap)
        
        // Release the mouse
        guard let upEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: CGPoint(x: CGFloat(x), y: CGFloat(y)), mouseButton: .left) else {
            throw SystemError.uiAutomationFailed("Failed to create mouse up event")
        }
        
        upEvent.post(tap: .cghidEventTap)
    }
    
    /// Double click at screen coordinates
    func doubleClickAt(x: Int, y: Int) async throws {
        guard let downEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: CGFloat(x), y: CGFloat(y)), mouseButton: .left) else {
            throw SystemError.uiAutomationFailed("Failed to create mouse event")
        }
        downEvent.setIntegerValueField(.mouseEventClickState, value: 2)
        downEvent.post(tap: .cghidEventTap)
        
        guard let upEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: CGPoint(x: CGFloat(x), y: CGFloat(y)), mouseButton: .left) else {
            throw SystemError.uiAutomationFailed("Failed to create mouse up event")
        }
        upEvent.setIntegerValueField(.mouseEventClickState, value: 2)
        upEvent.post(tap: .cghidEventTap)
    }
    
    /// Type text
    func typeText(_ text: String) async throws {
        for char in text.unicodeScalars {
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                continue
            }
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: Array(String(char).utf16))
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
    
    /// Press a keyboard shortcut
    func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags = []) async throws {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            throw SystemError.uiAutomationFailed("Failed to create key event")
        }
        keyDown.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        
        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            throw SystemError.uiAutomationFailed("Failed to create key up event")
        }
        keyUp.flags = modifiers
        keyUp.post(tap: .cghidEventTap)
    }
    
    // MARK: - System Information
    
    /// Get current system info
    func getSystemInfo() -> SystemInfo {
        return SystemInfo(
            computerName: Host.current().localizedName ?? "Unknown",
            currentUser: NSUserName(),
            homeDirectory: NSHomeDirectory(),
            workingDirectory: FileManager.default.currentDirectoryPath,
            availableMemory: getAvailableMemory(),
            cpuCount: ProcessInfo.processInfo.processorCount
        )
    }
    
    private func getAvailableMemory() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            return UInt64(stats.free_count) * pageSize
        }
        
        return 0
    }
}

// MARK: - Supporting Types

struct RunningApp: Identifiable {
    let id = UUID()
    let name: String
    let bundleId: String
    let isActive: Bool
}

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int
    let modifiedDate: Date
}

struct SystemInfo {
    let computerName: String
    let currentUser: String
    let homeDirectory: String
    let workingDirectory: String
    let availableMemory: UInt64
    let cpuCount: Int
}

/// System-related errors
enum SystemError: LocalizedError {
    case appNotFound(String)
    case appNotRunning(String)
    case fileNotFound(String)
    case directoryNotFound(String)
    case appleScriptFailed(String)
    case uiAutomationFailed(String)
    case permissionDenied(String)
    
    var errorDescription: String? {
        switch self {
        case .appNotFound(let bundleId):
            return "Application not found: \(bundleId)"
        case .appNotRunning(let bundleId):
            return "Application is not running: \(bundleId)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .directoryNotFound(let path):
            return "Directory not found: \(path)"
        case .appleScriptFailed(let reason):
            return "AppleScript failed: \(reason)"
        case .uiAutomationFailed(let reason):
            return "UI automation failed: \(reason)"
        case .permissionDenied(let resource):
            return "Permission denied: \(resource)"
        }
    }
}
