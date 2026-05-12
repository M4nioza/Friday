import SwiftUI

/// Memory browser for viewing and managing the brain
struct MemoryBrowserView: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText: String = ""
    @State private var selectedCategory: BrainSystem.MemoryCategory?
    @State private var selectedMemory: BrainSystem.MemoryNode?
    @State private var memories: [BrainSystem.MemoryNode] = []
    @State private var isLoading: Bool = true
    
    var body: some View {
        NavigationSplitView {
            // Category sidebar
            VStack(spacing: 0) {
                List(selection: $selectedCategory) {
                    Section("Categories") {
                        Button(action: { selectedCategory = nil }) {
                            Label("All Memories", systemImage: "brain")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(selectedCategory == nil ? .blue : .primary)
                        
                        ForEach(BrainSystem.MemoryCategory.allCases, id: \.self) { category in
                            Button(action: { selectedCategory = category }) {
                                Label(category.rawValue.capitalized, systemImage: iconForCategory(category))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(selectedCategory == category ? .blue : .primary)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        } detail: {
            // Memory list and detail - use flexible layout
            if selectedMemory != nil {
                MemoryDetailView(memory: selectedMemory!, onDelete: deleteMemory)
                    .frame(minWidth: 400)
            } else {
                MemoryListView(
                    memories: filteredMemories,
                    searchText: $searchText,
                    onSelect: { selectedMemory = $0 }
                )
                .frame(minWidth: 300)
            }
        }
        .searchable(text: $searchText, prompt: "Search memories...")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button(action: addNewMemory) {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            await loadMemories()
        }
    }
    
    private var filteredMemories: [BrainSystem.MemoryNode] {
        var result = memories
        
        if let category = selectedCategory {
            result = result.filter { $0.category == category.rawValue }
        }
        
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.content.lowercased().contains(query) ||
                $0.tags.contains { $0.lowercased().contains(query) }
            }
        }
        
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    private func loadMemories() async {
        isLoading = true
        var allMemories: [BrainSystem.MemoryNode] = []
        
        for category in BrainSystem.MemoryCategory.allCases {
            let categoryMemories = await BrainSystem.shared.getMemories(category: category)
            allMemories.append(contentsOf: categoryMemories)
        }
        
        memories = allMemories
        isLoading = false
    }
    
    private func addNewMemory() {
        // Would show a sheet to create new memory
    }
    
    private func deleteMemory(_ id: UUID) {
        Task {
            await BrainSystem.shared.deleteMemory(id)
            await loadMemories()
            selectedMemory = nil
        }
    }
    
    private func iconForCategory(_ category: BrainSystem.MemoryCategory) -> String {
        switch category {
        case .identity: return "person.crop.circle"
        case .learned: return "lightbulb"
        case .projects: return "folder"
        case .facts: return "info.circle"
        case .conversations: return "bubble.left.and.bubble.right"
        case .tasks: return "checkmark.circle"
        case .preferences: return "slider.horizontal.3"
        }
    }
}

/// List of memories
struct MemoryListView: View {
    let memories: [BrainSystem.MemoryNode]
    @Binding var searchText: String
    let onSelect: (BrainSystem.MemoryNode) -> Void
    
    var body: some View {
        if memories.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "brain")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No memories found")
                    .font(.headline)
                    .foregroundColor(.secondary)
                if !searchText.isEmpty {
                    Text("Try a different search term")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(memories, selection: .constant(memories.first?.id)) { memory in
                Button(action: { onSelect(memory) }) {
                    MemoryRowView(memory: memory)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
    }
}

/// Single memory row
struct MemoryRowView: View {
    let memory: BrainSystem.MemoryNode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(memory.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                HStack(spacing: 2) {
                    ForEach(0..<memory.importance, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                }
            }
            
            Text(memory.content)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            HStack {
                Label(memory.category, systemImage: "tag")
                    .font(.caption2)
                    .foregroundColor(.blue)
                
                if !memory.tags.isEmpty {
                    Text("•")
                        .foregroundColor(.secondary)
                    ForEach(memory.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Text(memory.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Memory detail view
struct MemoryDetailView: View {
    let memory: BrainSystem.MemoryNode
    let onDelete: (UUID) -> Void
    
    @State private var isEditing: Bool = false
    @State private var editedContent: String = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(memory.title)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        HStack {
                            Label(memory.category, systemImage: "tag")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                            
                            HStack(spacing: 2) {
                                ForEach(0..<memory.importance, id: \.self) { _ in
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundColor(.yellow)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: { isEditing.toggle() }) {
                        Label(isEditing ? "Done" : "Edit", systemImage: isEditing ? "checkmark" : "pencil")
                    }
                }
                
                Divider()
                
                // Content
                if isEditing {
                    TextEditor(text: $editedContent)
                        .font(.body)
                        .frame(minHeight: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                } else {
                    Text(memory.content)
                        .font(.body)
                }
                
                // Links
                if !memory.links.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Related Memories")
                            .font(.headline)
                        
                        ForEach(memory.links, id: \.self) { link in
                            HStack {
                                Image(systemName: "link")
                                    .foregroundColor(.blue)
                                Text(link)
                                    .font(.caption)
                            }
                        }
                    }
                }
                
                // Tags
                if !memory.tags.isEmpty {
                    HStack {
                        ForEach(memory.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
                
                // Metadata
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("ID: \(memory.id.uuidString)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Created: \(memory.createdAt.formatted())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Updated: \(memory.updatedAt.formatted())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
        }
        .onAppear {
            editedContent = memory.content
        }
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive, action: { onDelete(memory.id) }) {
                    Image(systemName: "trash")
                }
            }
        }
    }
}
