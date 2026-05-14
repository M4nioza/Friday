# Friday - Local AI Assistant

A native macOS AI assistant powered by local MLX-based LLM models with persistent memory and system integration.

## Features

### 🤖 Local LLM Integration
- Runs locally using Apple's MLX framework for optimal M-series chip performance
- Multiple model support (Llama, Mistral, Phi-3, etc.)
- Configurable temperature and token limits
- No data leaves your machine

### 🧠 Persistent Memory System ("Brain")
- Markdown-based memory storage with automatic interlinking
- Categories: Identity, Learned Facts, Projects, Preferences, Tasks
- Semantic search across memories
- Deep context linking for understanding relationships between memories

### 📱 Application Control
- Launch and close applications
- File system operations (read, write, create, delete)
- AppleScript execution
- UI automation (click, type)

### 📋 Task Planning
- Breaks complex tasks into executable steps
- Step-by-step execution with progress tracking
- Automatic error handling and recovery
- Can remember learned information

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Friday App                       │
├─────────────────────────────────────────────────────┤
│  UI Layer (SwiftUI)                                 │
│  ├── ChatView                                       │
│  ├── MemoryBrowserView                              │
│  ├── CommandPaletteView                             │
│  └── SettingsView                                   │
├─────────────────────────────────────────────────────┤
│  Core Engine                                        │
│  ├── LLMEngine (MLX Swift)                          │
│  ├── TaskPlanner                                    │
│  └── ContextManager                                 │
├─────────────────────────────────────────────────────┤
│  Brain System                                       │
│  ├── MemoryStore (Markdown files)                   │
│  ├── LinkParser                                     │
│  └── ContextGraph                                   │
├─────────────────────────────────────────────────────┤
│  System Integration                                 │
│  ├── AppController (NSWorkspace)                    │
│  ├── FileSystemManager                              │
│  └── AccessibilityService                           │
└─────────────────────────────────────────────────────┘
```

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1, M2, M3, M4) or Intel Mac

## Installation

### Building from Source

1. Clone the repository:
```bash
git clone https://github.com/M4nioza/Friday.git
cd Friday
```

2. Generate the Xcode project:
```bash
xcodegen generate
```

3. Build the project:
```bash
xcodebuild -project Friday.xcodeproj -scheme Friday -configuration Release build
```

4. The app will be created at `build/Release/Friday.app`

### Model Setup

Friday supports any MLX-compatible instruct model. Download models from HuggingFace's mlx-community:

1. Open Settings → Model
2. Enter a HuggingFace URL for an mlx-community model, or use one of the quick download options
3. Friday will download and manage the model for you

**Supported model types:**
- Text instruct models (Llama, Mistral, Phi, Qwen, Gemma, etc.)
- Vision instruct models (for image understanding)
- Any model with MLX format available on HuggingFace

Models are stored at: `~/.cache/mlx-model/models/`

## Usage

### Chat Interface
- Type messages naturally to interact with Friday
- Use the orange button to execute complex tasks as multi-step plans
- Access previous conversations from the sidebar

### Memory Browser
- View all memories organized by category
- Search and filter memories
- Edit or delete memories
- See how memories are linked together

### Command Palette
- Press Cmd+K to open the command palette
- Quick access to all features
- Search commands by name or category

## Brain System

The brain is stored as interconnected Markdown files in:
```
~/Library/Application Support/Friday/Brain/
├── identity/      # Self-knowledge
├── learned/       # Learned facts about user
├── projects/      # Project-related memories
├── facts/         # General facts
├── conversations/ # Conversation summaries
├── tasks/         # Task history
└── preferences/   # User preferences
```

### Memory Links
Memories can link to each other using wiki-style links:
```markdown
## Links
- [[memory-id-1]]
- [[memory-id-2]]
```

The context manager builds rich context by:
1. Finding relevant memories for the current query
2. Traversing linked memories for deep understanding
3. Including recent conversation history
4. Adding system state information

## Privacy

All processing happens locally:
- No data sent to external servers
- Conversations stored only on your machine
- Brain memories are local Markdown files
- Can be audited and modified directly

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - see LICENSE file for details

## Acknowledgments

- MLX Team at Apple for the MLX framework
- Hugging Face for transformers library
- The open-source LLM community
