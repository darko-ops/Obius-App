import SwiftUI

/// Autocomplete dropdown for @mentions
struct HandleAutocomplete: View {
    let handles: [Handle]
    let query: String
    let onSelect: (Handle) -> Void
    let onDismiss: () -> Void

    private var filteredHandles: [Handle] {
        if query.isEmpty {
            return handles
        }
        let normalizedQuery = query.lowercased()
        return handles.filter { handle in
            handle.name.contains(normalizedQuery) ||
            handle.displayName.lowercased().contains(normalizedQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if filteredHandles.isEmpty {
                emptyState
            } else {
                handleList
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }

    private var handleList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredHandles.prefix(8)) { handle in
                    HandleAutocompleteRow(handle: handle) {
                        onSelect(handle)
                    }

                    if handle.id != filteredHandles.prefix(8).last?.id {
                        Divider()
                            .padding(.leading, 40)
                    }
                }
            }
        }
        .frame(maxHeight: 280)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "at.badge.plus")
                .font(.title2)
                .foregroundStyle(.secondary)

            if query.isEmpty {
                Text("No handles yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No handles matching '\(query)'")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if Handle.validateName(query) == nil {
                    Text("Create @\(query)?")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

/// Individual row in the autocomplete list
struct HandleAutocompleteRow: View {
    let handle: Handle
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Intent color indicator
                Circle()
                    .fill(handle.intent.color)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(handle.formattedName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)

                    if !handle.preview.isEmpty {
                        Text(handle.preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "return")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Wrapper view that positions autocomplete below text input
struct HandleAutocompleteOverlay: View {
    @Binding var isShowing: Bool
    @Binding var query: String
    let handles: [Handle]
    let onSelect: (Handle) -> Void

    var body: some View {
        if isShowing {
            HandleAutocomplete(
                handles: handles,
                query: query,
                onSelect: { handle in
                    onSelect(handle)
                    isShowing = false
                    query = ""
                },
                onDismiss: {
                    isShowing = false
                    query = ""
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
        }
    }
}

// MARK: - Handle Detection Helper

/// Detects @mention patterns in text for autocomplete triggering
struct HandleMentionDetector {
    /// Check if text ends with an active @mention being typed
    /// Returns the query after @ if active, nil otherwise
    static func detectActiveMention(in text: String, cursorPosition: Int) -> String? {
        guard cursorPosition <= text.count else { return nil }

        let prefixText = String(text.prefix(cursorPosition))
        guard let atIndex = prefixText.lastIndex(of: "@") else { return nil }

        let queryStartIndex = text.index(after: atIndex)
        guard queryStartIndex <= text.endIndex else { return nil }

        let query = String(prefixText[queryStartIndex...])

        // Check if query contains invalid characters (space, newline, etc.)
        let invalidChars = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        if query.unicodeScalars.contains(where: { invalidChars.contains($0) && $0 != "_" }) {
            return nil
        }

        return query
    }

    /// Check if the text starts with @HandleName and return the handle name
    static func detectHandleAtStart(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("@") else { return nil }

        let afterAt = trimmed.dropFirst()
        let name = afterAt.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" })

        return name.isEmpty ? nil : String(name)
    }
}

// MARK: - Preview

#Preview("Handle Autocomplete") {
    VStack {
        Spacer()

        HandleAutocomplete(
            handles: [
                Handle(name: "jokes", displayName: "Jokes", content: "Why did the chicken cross the road?", intent: .idea),
                Handle(name: "todos", displayName: "TODOs", content: "Buy groceries, call mom", intent: .task),
                Handle(name: "research", displayName: "Research", content: "According to recent studies...", intent: .evidence),
                Handle(name: "questions", displayName: "Questions", content: "What if we tried a different approach?", intent: .question)
            ],
            query: "jo",
            onSelect: { handle in
                print("Selected: \(handle.formattedName)")
            },
            onDismiss: {
                print("Dismissed")
            }
        )
        .frame(width: 300)

        Spacer()
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}

#Preview("Empty Autocomplete") {
    HandleAutocomplete(
        handles: [],
        query: "new",
        onSelect: { _ in },
        onDismiss: { }
    )
    .frame(width: 300)
    .padding()
}
