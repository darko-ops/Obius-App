import SwiftUI

// MARK: - Loading View

struct LoadingView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Skeleton Loader

struct SkeletonView: View {
    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(
                LinearGradient(
                    colors: [
                        Color.gray.opacity(0.2),
                        Color.gray.opacity(0.3),
                        Color.gray.opacity(0.2)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .mask(
                Rectangle()
                    .offset(x: isAnimating ? 200 : -200)
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    isAnimating = true
                }
            }
    }
}

struct NoteRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 8) {
                SkeletonView()
                    .frame(width: 150, height: 16)

                SkeletonView()
                    .frame(width: 80, height: 12)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct NotesListSkeleton: View {
    var body: some View {
        List {
            ForEach(0..<5, id: \.self) { _ in
                NoteRowSkeleton()
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }
}

// MARK: - Empty States

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title2.bold())

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let actionTitle = actionTitle, let action = action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
            }
        }
    }
}

// MARK: - Error State

struct ErrorStateView: View {
    let error: Error
    var retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Something went wrong")
                .font(.title2.bold())

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let retry = retryAction {
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
            }
        }
    }
}

// MARK: - Offline State

struct OfflineStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.title)
                .foregroundStyle(.orange)

            Text("You're offline")
                .font(.headline)

            Text("Changes will sync when you're back online")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Loading Overlay Modifier

struct LoadingOverlay: ViewModifier {
    let isLoading: Bool
    var message: String = "Loading..."

    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(isLoading)
                .blur(radius: isLoading ? 2 : 0)

            if isLoading {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()

                LoadingView(message: message)
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

extension View {
    func loadingOverlay(_ isLoading: Bool, message: String = "Loading...") -> some View {
        modifier(LoadingOverlay(isLoading: isLoading, message: message))
    }
}

// MARK: - Async Content View

struct AsyncContentView<Content: View, Placeholder: View>: View {
    @Binding var isLoading: Bool
    @Binding var error: Error?
    var retryAction: (() async -> Void)?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        Group {
            if let error = error {
                ErrorStateView(error: error) {
                    Task {
                        await retryAction?()
                    }
                }
            } else if isLoading {
                placeholder()
            } else {
                content()
            }
        }
    }
}

// MARK: - Previews

#Preview("Loading") {
    LoadingView()
}

#Preview("Skeleton") {
    NotesListSkeleton()
}

#Preview("Empty State") {
    EmptyStateView(
        icon: "note.text",
        title: "No Notes",
        message: "Tap the + button to create your first note",
        actionTitle: "Create Note",
        action: {}
    )
}

#Preview("Error State") {
    ErrorStateView(
        error: NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Network connection failed"]),
        retryAction: {}
    )
}

#Preview("Offline") {
    OfflineStateView()
}
