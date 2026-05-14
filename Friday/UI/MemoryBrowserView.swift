import SwiftUI

struct MemoryBrowserView: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText: String = ""
    @State private var selectedCategory: BrainSystem.MemoryCategory?
    @State private var selectedMemory: BrainSystem.MemoryNode?
    @State private var memories: [BrainSystem.MemoryNode] = []
    @State private var isLoading: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 0) {
                categorySidebar

                Divider()

                contentArea
            }
        }
        .frame(minWidth: 700, idealWidth: 900, minHeight: 500, idealHeight: 700)
        .background(.ultraThinMaterial)
        .task {
            await loadMemories()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Memory Browser")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("Explore and manage your memories")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Categories")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            Button(action: { selectedCategory = nil }) {
                HStack {
                    Image(systemName: "brain")
                        .font(.caption)
                        .frame(width: 20)
                    Text("All Memories")
                        .font(.subheadline)
                    Spacer()
                    if selectedCategory == nil {
                        Text("\(memories.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selectedCategory == nil ? Color.accentColor.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .foregroundColor(selectedCategory == nil ? .accentColor : .primary)

            ForEach(BrainSystem.MemoryCategory.allCases, id: \.self) { category in
                categoryButton(category)
            }

            Spacer()

            Divider()
                .padding(.horizontal, 12)

            Button(action: addNewMemory) {
                Label("Add Memory", systemImage: "plus")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 180)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private func categoryButton(_ category: BrainSystem.MemoryCategory) -> some View {
        let count = memories.filter { $0.category == category.rawValue }.count
        let isSelected = selectedCategory == category

        return Button(action: { selectedCategory = category }) {
            HStack {
                Image(systemName: iconForCategory(category))
                    .font(.caption)
                    .frame(width: 20)
                Text(category.rawValue.capitalized)
                    .font(.subheadline)
                Spacer()
                if isSelected {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .accentColor : .primary)
    }

    @ViewBuilder
    private var contentArea: some View {
        if let memory = selectedMemory {
            MemoryDetailView(
                memory: memory,
                onDelete: deleteMemory,
                onBack: { selectedMemory = nil }
            )
        } else {
            MemoryListView(
                memories: filteredMemories,
                searchText: $searchText,
                onSelect: { selectedMemory = $0 }
            )
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

// MARK: - Memory List

struct MemoryListView: View {
    let memories: [BrainSystem.MemoryNode]
    @Binding var searchText: String
    let onSelect: (BrainSystem.MemoryNode) -> Void

    @State private var hoveredId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            if memories.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search memories...", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(searchText.isEmpty ? "No memories found" : "No results for '\(searchText)'")
                .font(.headline)
                .foregroundColor(.secondary)

            if !searchText.isEmpty {
                Text("Try a different search term")
                    .font(.caption)
                    .foregroundColor(Color.secondary.opacity(0.5))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(memories) { memory in
                    MemoryCardView(
                        memory: memory,
                        isHovered: hoveredId == memory.id
                    )
                    .onTapGesture { onSelect(memory) }
                    .onHover { hovering in
                        hoveredId = hovering ? memory.id : nil
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Memory Card

struct MemoryCardView: View {
    let memory: BrainSystem.MemoryNode
    let isHovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(memory.category.capitalized)
                            .font(.caption2)
                            .foregroundColor(.accentColor)

                        Text("•")
                            .foregroundColor(Color.secondary.opacity(0.5))

                        Text(memory.updatedAt, style: .relative)
                            .font(.caption2)
                            .foregroundColor(Color.secondary.opacity(0.5))
                    }
                }

                Spacer()

                if memory.importance > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<memory.importance, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                        }
                    }
                }

                if isHovered {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
            }

            Text(memory.content)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            if !memory.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(memory.tags.prefix(4), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    if memory.tags.count > 4 {
                        Text("+\(memory.tags.count - 4)")
                            .font(.caption2)
                            .foregroundColor(Color.secondary.opacity(0.5))
                    }
                }
            }

            if !memory.links.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(memory.links.count) linked")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(isHovered ? 0.1 : 0.04),
            radius: isHovered ? 10 : 4,
            x: 0,
            y: isHovered ? 4 : 1
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Memory Detail

struct MemoryDetailView: View {
    let memory: BrainSystem.MemoryNode
    let onDelete: (UUID) -> Void
    let onBack: () -> Void

    @State private var isEditing: Bool = false
    @State private var editedContent: String = ""

    var body: some View {
        VStack(spacing: 0) {
            detailHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    contentSection

                    if !memory.links.isEmpty {
                        linksSection
                    }

                    if !memory.tags.isEmpty {
                        tagsSection
                    }

                    metadataSection
                }
                .padding()
            }
        }
        .onAppear {
            editedContent = memory.content
        }
    }

    private var detailHeader: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                    Text("Back")
                        .font(.subheadline)
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(memory.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(memory.category.capitalized)
                    .font(.caption2)
                    .foregroundColor(.accentColor)
            }

            Spacer()

            Button(action: { isEditing.toggle() }) {
                Label(isEditing ? "Done" : "Edit", systemImage: isEditing ? "checkmark" : "pencil")
            }
            .buttonStyle(.bordered)

            Button(role: .destructive, action: { onDelete(memory.id) }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            if isEditing {
                TextEditor(text: $editedContent)
                    .font(.body)
                    .frame(minHeight: 150)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            } else {
                Text(memory.content)
                    .font(.body)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Related Memories")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            HStack {
                ForEach(memory.links, id: \.self) { link in
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.caption2)
                        Text(link)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            FlowLayout(spacing: 6) {
                ForEach(memory.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Metadata")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 4) {
                metadataRow(label: "ID", value: memory.id.uuidString)
                metadataRow(label: "Created", value: memory.createdAt.formatted())
                metadataRow(label: "Updated", value: memory.updatedAt.formatted())
                metadataRow(label: "Importance", value: String(repeating: "★", count: memory.importance))
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .lineLimit(1)
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}