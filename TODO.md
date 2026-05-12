# Friday - Local AI Assistant

## Project Overview
A native macOS AI assistant powered by local MLX-based LLM models with persistent memory and system integration.

## Todo List

### Phase 1: Project Setup ✅
- [x] Create project structure and XcodeGen configuration
- [x] Create Info.plist and entitlements
- [x] Set up main.swift entry point

### Phase 2: Core Architecture ✅
- [x] Implement LLM Engine with MLX integration
- [x] Build Memory/Brain system with Markdown interlinking
- [x] Create Task Planner for complex operations
- [x] Implement System Integration layer (App control, File ops)

### Phase 3: UI Layer ✅
- [x] Create main window with chat interface
- [x] Implement memory browser view
- [x] Add settings and configuration panel
- [x] Build system command palette

### Phase 4: Brain System ✅
- [x] Design Markdown-based memory schema
- [x] Implement context linking engine
- [x] Create memory persistence layer
- [x] Build semantic context understanding

### Phase 5: System Integration ✅
- [x] Application launching/closing via NSWorkspace
- [x] File system operations with proper permissions
- [x] UI automation (click, type)
- [x] AppleScript execution

### Phase 6: Documentation ✅
- [x] Create README with setup instructions
- [x] Add LICENSE file

### Remaining Tasks
- [ ] Install XcodeGen if not present
- [ ] Build and test the application
- [ ] Set up MLX models

## Architecture
```
┌─────────────────────────────────────────────────────┐
│                    Friday App                        │
├─────────────────────────────────────────────────────┤
│  UI Layer (SwiftUI)                                  │
│  ├── ChatView                                        │
│  ├── MemoryBrowserView                              │
│  └── SettingsView                                    │
├─────────────────────────────────────────────────────┤
│  Core Engine                                         │
│  ├── LLMEngine (MLX Swift)                          │
│  ├── TaskPlanner                                    │
│  └── ContextManager                                 │
├─────────────────────────────────────────────────────┤
│  Brain System                                        │
│  ├── MemoryStore (Markdown files)                   │
│  ├── LinkParser                                     │
│  └── ContextGraph                                   │
├─────────────────────────────────────────────────────┤
│  System Integration                                  │
│  ├── AppController (NSWorkspace)                    │
│  ├── FileSystemManager                               │
│  └── AccessibilityService                           │
└─────────────────────────────────────────────────────┘
```
