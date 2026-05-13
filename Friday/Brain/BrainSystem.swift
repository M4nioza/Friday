import Foundation

/// Brain System - A persistent memory system using interconnected Markdown files
actor BrainSystem {
    static let shared = BrainSystem()
    
    /// Directory where brain files are stored
    var brainDirectory: URL?
    
    /// Memory categories
    enum MemoryCategory: String, CaseIterable {
        case identity = "identity"        // Self-knowledge
        case learned = "learned"          // Things learned about user
        case projects = "projects"        // Project-related memories
        case facts = "facts"              // General facts
        case conversations = "conversations" // Conversation summaries
        case tasks = "tasks"              // Task history
        case preferences = "preferences"  // User preferences
        
        var directoryName: String { rawValue }
    }
    
    /// A single memory node
    struct MemoryNode: Identifiable, Codable {
        let id: UUID
        var title: String
        var content: String
        var category: String
        var links: [String]  // Links to other memory IDs or paths
        var tags: [String]
        var createdAt: Date
        var updatedAt: Date
        var importance: Int  // 1-5 scale
        
        init(
            id: UUID = UUID(),
            title: String,
            content: String,
            category: String,
            links: [String] = [],
            tags: [String] = [],
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            importance: Int = 3
        ) {
            self.id = id
            self.title = title
            self.content = content
            self.category = category
            self.links = links
            self.tags = tags
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.importance = importance
        }
        
        /// Convert to Markdown format
        func toMarkdown() -> String {
            var md = "# \(title)\n\n"
            md += "**ID:** `\(id.uuidString)`\n"
            md += "**Category:** [[\(category)]]\n"
            md += "**Tags:** \(tags.map { "#\($0)" }.joined(separator: " "))\n"
            md += "**Importance:** \(String(repeating: "⭐", count: importance))\n"
            md += "**Created:** \(createdAt.formatted())\n"
            md += "**Updated:** \(updatedAt.formatted())\n\n"
            
            md += "---\n\n"
            md += content + "\n\n"
            
            if !links.isEmpty {
                md += "---\n\n"
                md += "## Links\n\n"
                for link in links {
                    md += "- [[\(link)]]\n"
                }
            }
            
            return md
        }
        
        /// Parse from Markdown content
        static func fromMarkdown(_ content: String, path: String) -> MemoryNode? {
            let lines = content.components(separatedBy: .newlines)
            
            guard let titleLine = lines.first(where: { $0.hasPrefix("# ") }) else { return nil }
            let title = String(titleLine.dropFirst(2))
            
            // Parse metadata
            var id: UUID?
            var category = ""
            var tags: [String] = []
            var importance = 3
            var createdAt = Date()
            var updatedAt = Date()
            
            for line in lines {
                if line.hasPrefix("**ID:**") {
                    let idStr = line.replacingOccurrences(of: "**ID:**", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "`", with: "")
                    id = UUID(uuidString: idStr)
                } else if line.hasPrefix("**Category:**") {
                    let catStr = line.replacingOccurrences(of: "**Category:**", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if let regex = try? NSRegularExpression(pattern: "\\[\\[(.*?)\\]\\]"),
                       let match = regex.firstMatch(in: catStr, range: NSRange(catStr.startIndex..., in: catStr)),
                       let range = Range(match.range(at: 1), in: catStr) {
                        category = String(catStr[range])
                    }
                } else if line.hasPrefix("**Tags:**") {
                    let tagsStr = line.replacingOccurrences(of: "**Tags:**", with: "").trimmingCharacters(in: .whitespaces)
                    if let regex = try? NSRegularExpression(pattern: "#(\\w+)") {
                        let matches = regex.matches(in: tagsStr, range: NSRange(tagsStr.startIndex..., in: tagsStr))
                        tags = matches.compactMap { match in
                            if let range = Range(match.range(at: 1), in: tagsStr) {
                                return String(tagsStr[range])
                            }
                            return nil
                        }
                    }
                } else if line.hasPrefix("**Importance:**") {
                    let impStr = line.replacingOccurrences(of: "**Importance:**", with: "").trimmingCharacters(in: .whitespaces)
                    importance = impStr.filter { $0 == "⭐" }.count
                } else if line.hasPrefix("**Created:**") {
                    let dateStr = line.replacingOccurrences(of: "**Created:**", with: "").trimmingCharacters(in: .whitespaces)
                    if let date = ISO8601DateFormatter().date(from: dateStr) {
                        createdAt = date
                    }
                }
            }
            
            // Extract main content (between --- markers)
            // Find the second "---" separator after the metadata
            var separators: [String.Index] = []
            var searchStart = content.startIndex
            while let range = content.range(of: "---\n", range: searchStart..<content.endIndex) {
                separators.append(range.lowerBound)
                searchStart = range.upperBound
            }
            
            let contentStart: String.Index
            let contentEnd: String.Index
            
            if separators.count >= 2 {
                contentStart = content.index(after: separators[1])
                contentEnd = content.range(of: "## Links")?.lowerBound ?? content.endIndex
            } else {
                contentStart = content.startIndex
                contentEnd = content.range(of: "## Links")?.lowerBound ?? content.endIndex
            }
            
            let mainContent = String(content[contentStart..<contentEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Extract links
            var links: [String] = []
            if let linksSection = content.range(of: "## Links") {
                let afterLinks = content[linksSection.upperBound...]
                if let regex = try? NSRegularExpression(pattern: "\\[\\[(.*?)\\]\\]") {
                    let matches = regex.matches(in: String(afterLinks), range: NSRange(afterLinks.startIndex..., in: afterLinks))
                    links = matches.compactMap { match in
                        if let range = Range(match.range(at: 1), in: afterLinks) {
                            return String(afterLinks[range])
                        }
                        return nil
                    }
                }
            }
            
            guard let nodeId = id else { return nil }
            
            return MemoryNode(
                id: nodeId,
                title: title,
                content: mainContent,
                category: category,
                links: links,
                tags: tags,
                createdAt: createdAt,
                updatedAt: updatedAt,
                importance: importance
            )
        }
    }
    
    /// Index of all memories for fast lookup
    private var memoryIndex: [UUID: MemoryNode] = [:]
    private var categoryIndex: [MemoryCategory: [UUID]] = [:]
    
    private init() {}
    
    // MARK: - Initialization
    
    /// Initialize the brain system
    func initialize() async {
        // Set up brain directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let fridayDir = appSupport.appendingPathComponent("Friday", isDirectory: true)
        brainDirectory = fridayDir.appendingPathComponent("Brain", isDirectory: true)
        
        // Create directory structure
        try? FileManager.default.createDirectory(at: brainDirectory!, withIntermediateDirectories: true)
        
        for category in MemoryCategory.allCases {
            let catDir = brainDirectory!.appendingPathComponent(category.directoryName, isDirectory: true)
            try? FileManager.default.createDirectory(at: catDir, withIntermediateDirectories: true)
        }
        
        // Load existing memories
        await loadMemoryIndex()
        
        // Create identity file if not exists
        if !memoryIndex.values.contains(where: { $0.category == MemoryCategory.identity.rawValue }) {
            await createIdentityMemory()
        }
    }
    
    /// Save current state
    func saveState() async {
        // Save all memories to disk
        for (_, memory) in memoryIndex {
            await saveMemory(memory)
        }
    }
    
    // MARK: - Memory Operations
    
    /// Add a new memory
    func addMemory(
        title: String,
        content: String,
        category: MemoryCategory,
        links: [String] = [],
        tags: [String] = [],
        importance: Int = 3
    ) async -> MemoryNode {
        let memory = MemoryNode(
            title: title,
            content: content,
            category: category.rawValue,
            links: links,
            tags: tags,
            importance: importance
        )
        
        memoryIndex[memory.id] = memory
        categoryIndex[category, default: []].append(memory.id)
        
        await saveMemory(memory)
        
        return memory
    }
    
    /// Convenience method for adding simple facts
    func addMemory(fact: String, category: MemoryCategory) async {
        _ = await addMemory(
            title: fact.prefix(50).description,
            content: fact,
            category: category
        )
    }
    
    /// Update an existing memory
    func updateMemory(_ id: UUID, content: String) async {
        guard var memory = memoryIndex[id] else { return }
        memory.content = content
        memory.updatedAt = Date()
        memoryIndex[id] = memory
        await saveMemory(memory)
    }
    
    /// Delete a memory
    func deleteMemory(_ id: UUID) async {
        guard let memory = memoryIndex[id],
              let category = MemoryCategory(rawValue: memory.category) else { return }
        
        memoryIndex.removeValue(forKey: id)
        categoryIndex[category]?.removeAll { $0 == id }
        
        // Delete file
        let filePath = brainDirectory!
            .appendingPathComponent(category.directoryName)
            .appendingPathComponent("\(id.uuidString).md")
        try? FileManager.default.removeItem(at: filePath)
    }
    
    /// Link two memories together
    func linkMemories(_ id1: UUID, _ id2: UUID) async {
        guard var memory1 = memoryIndex[id1],
              var memory2 = memoryIndex[id2] else { return }
        
        let id1Str = id1.uuidString
        let id2Str = id2.uuidString
        
        if !memory1.links.contains(id2Str) {
            memory1.links.append(id2Str)
            memory1.updatedAt = Date()
            memoryIndex[id1] = memory1
            await saveMemory(memory1)
        }
        
        if !memory2.links.contains(id1Str) {
            memory2.links.append(id1Str)
            memory2.updatedAt = Date()
            memoryIndex[id2] = memory2
            await saveMemory(memory2)
        }
    }
    
    // MARK: - Retrieval
    
    /// Get memory by ID
    func getMemory(_ id: UUID) -> MemoryNode? {
        return memoryIndex[id]
    }
    
    /// Get memories by category
    func getMemories(category: MemoryCategory) -> [MemoryNode] {
        guard let ids = categoryIndex[category] else { return [] }
        return ids.compactMap { memoryIndex[$0] }
    }
    
    /// Search memories by query
    func searchMemories(query: String) -> [MemoryNode] {
        let lowercasedQuery = query.lowercased()
        return memoryIndex.values.filter { memory in
            memory.title.lowercased().contains(lowercasedQuery) ||
            memory.content.lowercased().contains(lowercasedQuery) ||
            memory.tags.contains { $0.lowercased().contains(lowercasedQuery) }
        }.sorted { $0.importance > $1.importance }
    }
    
    /// Get related memories (following links)
    func getRelatedMemories(_ id: UUID, depth: Int = 1) -> [MemoryNode] {
        guard let memory = memoryIndex[id] else { return [] }
        
        var related: [MemoryNode] = []
        var visited = Set<UUID>([id])
        
        for linkIdStr in memory.links {
            if let linkedId = UUID(uuidString: linkIdStr),
               let linkedMemory = memoryIndex[linkedId],
               !visited.contains(linkedId) {
                related.append(linkedMemory)
                visited.insert(linkedId)
            }
        }
        
        return related
    }
    
    /// Build context from relevant memories
    func buildContext(for query: String, maxMemories: Int = 10) -> String {
        let relevantMemories = searchMemories(query: query)
            .prefix(maxMemories)
        
        var context = "## Relevant Memories\n\n"
        
        for memory in relevantMemories {
            context += "### \(memory.title)\n"
            context += memory.content + "\n\n"
            
            if !memory.links.isEmpty {
                context += "_Related to: \(memory.links.joined(separator: ", "))_\n\n"
            }
        }
        
        return context
    }
    
    /// Get memories for LLM context with deep linking
    func getDeepContext(for query: String, depth: Int = 2) -> String {
        let relevantMemories = searchMemories(query: query)
        
        guard let primaryMemory = relevantMemories.first else {
            return ""
        }
        
        var visited = Set<UUID>()
        var contextMemories: [MemoryNode] = []
        
        func traverse(_ memory: MemoryNode, currentDepth: Int) {
            guard currentDepth <= depth, !visited.contains(memory.id) else { return }
            visited.insert(memory.id)
            contextMemories.append(memory)
            
            for linkIdStr in memory.links {
                if let linkedId = UUID(uuidString: linkIdStr),
                   let linkedMemory = memoryIndex[linkedId] {
                    traverse(linkedMemory, currentDepth: currentDepth + 1)
                }
            }
        }
        
        traverse(primaryMemory, currentDepth: 0)
        
        // Build hierarchical context
        var context = "## Deep Memory Context\n\n"
        context += "This context builds on related memories to provide comprehensive understanding:\n\n"
        
        for memory in contextMemories.prefix(10) {
            context += "---\n\n"
            context += "### \(memory.title)\n"
            context += memory.content + "\n\n"
        }
        
        return context
    }
    
    // MARK: - Private Helpers
    
    private func loadMemoryIndex() async {
        guard let brainDir = brainDirectory else { return }
        
        for category in MemoryCategory.allCases {
            let catDir = brainDir.appendingPathComponent(category.directoryName)
            
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: catDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for file in files where file.pathExtension == "md" {
                if let content = try? String(contentsOf: file, encoding: .utf8),
                   let memory = MemoryNode.fromMarkdown(content, path: file.path) {
                    memoryIndex[memory.id] = memory
                    categoryIndex[category, default: []].append(memory.id)
                }
            }
        }
    }
    
    private func saveMemory(_ memory: MemoryNode) async {
        guard let brainDir = brainDirectory,
              let category = MemoryCategory(rawValue: memory.category) else { return }
        
        let filePath = brainDir
            .appendingPathComponent(category.directoryName)
            .appendingPathComponent("\(memory.id.uuidString).md")
        
        try? memory.toMarkdown().write(to: filePath, atomically: true, encoding: .utf8)
    }
    
    private func createIdentityMemory() async {
        _ = await addMemory(
            title: "Friday - AI Assistant Identity",
            content: """
            I am Friday, a local AI assistant running on macOS using MLX-optimized models.
            
            ## My Capabilities
            - Answer questions directly and helpfully
            - Execute tasks on this Mac (file operations, app control)
            - Remember important information across conversations
            - Break down complex requests into steps when needed
            
            ## How I Should Respond
            - ANSWER DIRECTLY: Don't give generic template responses
            - No "It seems like you're trying to..." - just help
            - Be concise and focused on what the user needs
            - Stay on topic, respond to what was actually asked
            
            ## Privacy
            All processing happens locally on this Mac.
            I learn from our conversations to provide better assistance.
            """,
            category: .identity,
            tags: ["identity", "about", "capabilities"],
            importance: 5
        )
    }
}

// MARK: - Memory Statistics

extension BrainSystem {
    struct MemoryStats {
        let totalMemories: Int
        let byCategory: [String: Int]
        let averageImportance: Double
        let mostLinked: [BrainSystem.MemoryNode]
    }
    
    func getStatistics() -> MemoryStats {
        let memories = Array(memoryIndex.values)
        
        var categoryCount: [String: Int] = [:]
        var linkCounts: [(UUID, Int)] = []
        
        for memory in memories {
            categoryCount[memory.category, default: 0] += 1
            linkCounts.append((memory.id, memory.links.count))
        }
        
        let avgImportance = memories.isEmpty ? 0 : Double(memories.reduce(0) { $0 + $1.importance }) / Double(memories.count)
        
        let topLinked = linkCounts
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .compactMap { memoryIndex[$0.0] }
        
        return MemoryStats(
            totalMemories: memories.count,
            byCategory: categoryCount,
            averageImportance: avgImportance,
            mostLinked: topLinked
        )
    }
}
