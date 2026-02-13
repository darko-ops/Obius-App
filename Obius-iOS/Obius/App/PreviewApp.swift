import SwiftUI

/// Standalone preview app for testing UI without Supabase
/// Run any Preview in Xcode to see the UI
struct PreviewTestView: View {
    @State private var sections: [Section] = [
        Section(
            id: "1",
            noteId: "note1",
            content: "This is an idea - tap to edit",
            orderKey: "A",
            intent: .idea
        ),
        Section(
            id: "2",
            noteId: "note1",
            content: "What if we tried a different approach?",
            orderKey: "B",
            intent: .question
        ),
        Section(
            id: "3",
            noteId: "note1",
            content: "Complete the implementation",
            orderKey: "C",
            indentLevel: 1,
            intent: .task
        ),
        Section(
            id: "4",
            noteId: "note1",
            content: "According to research, this approach works well",
            title: "Research Citation",
            orderKey: "D",
            indentLevel: 2,
            intent: .evidence
        ),
        Section(
            id: "5",
            noteId: "note1",
            content: "This is a locked section - requires authentication",
            orderKey: "E",
            isLocked: true,
            intent: .evidence
        ),
    ]
    
    @State private var focusedId: String?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(sections) { section in
                        SectionView(
                            section: section,
                            isFocused: focusedId == section.id,
                            isAuthenticated: false,
                            hasChildren: sections.contains { $0.parentSectionId == section.id },
                            onContentChange: { _, _ in },
                            onReturn: {},
                            onBackspaceEmpty: {},
                            onIndent: {},
                            onOutdent: {},
                            onToggleCollapse: {},
                            onToggleLock: {},
                            onUnlockRequest: { print("Unlock requested for \(section.id)") },
                            onIntentChange: { _ in }
                        )
                        .onTapGesture {
                            focusedId = section.id
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Obius Preview")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let newSection = Section(
                            id: UUID().uuidString,
                            noteId: "note1",
                            content: "",
                            orderKey: String(Character(UnicodeScalar(65 + sections.count)!)),
                            intent: .idea
                        )
                        sections.append(newSection)
                        focusedId = newSection.id
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

#Preview("Obius UI Test") {
    PreviewTestView()
}

#Preview("All Intent Types") {
    VStack(spacing: 12) {
        ForEach(IntentType.allCases, id: \.self) { intent in
            SectionView(
                section: Section(
                    noteId: "1",
                    content: "\(intent.displayName) section example content",
                    orderKey: "A",
                    intent: intent
                ),
                isFocused: false,
                onContentChange: { _, _ in },
                onReturn: {},
                onBackspaceEmpty: {},
                onIndent: {},
                onOutdent: {},
                onToggleCollapse: {}
            )
        }
    }
    .padding()
}

#Preview("Locked Section States") {
    VStack(spacing: 16) {
        // Locked, not authenticated
        SectionView(
            section: Section(
                noteId: "1",
                content: "This content is hidden behind the shimmer",
                orderKey: "A",
                isLocked: true,
                intent: .evidence
            ),
            isFocused: false,
            isAuthenticated: false,
            onContentChange: { _, _ in },
            onReturn: {},
            onBackspaceEmpty: {},
            onIndent: {},
            onOutdent: {},
            onToggleCollapse: {},
            onUnlockRequest: { print("Unlock!") }
        )
        
        // Locked, authenticated
        SectionView(
            section: Section(
                noteId: "1",
                content: "This content is now visible after authentication",
                orderKey: "B",
                isLocked: true,
                intent: .task
            ),
            isFocused: false,
            isAuthenticated: true,
            onContentChange: { _, _ in },
            onReturn: {},
            onBackspaceEmpty: {},
            onIndent: {},
            onOutdent: {},
            onToggleCollapse: {}
        )
    }
    .padding()
}
