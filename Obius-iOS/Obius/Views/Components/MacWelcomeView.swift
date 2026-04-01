import SwiftUI

#if os(macOS)
struct MacWelcomeView: View {
    @EnvironmentObject var appState: AppState
    let onNewProject: () -> Void
    let onNewPage: () -> Void
    let onBrowse: () -> Void

    @State private var showingNewProject = false
    @State private var newProjectName = ""
    @AppStorage("selectedModuleId") private var selectedModuleId: String?

    private var recentNotes: [Note] {
        Array(
            appState.noteRepository.notes
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(5)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Logo and greeting
                VStack(spacing: 12) {
                    Image("ObiusLogoClean")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)

                    Text("Welcome to Obius")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)

                    Text("What would you like to do?")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(white: 0.5))
                }

                // Action cards
                HStack(spacing: 16) {
                    welcomeCard(
                        icon: "folder.badge.plus",
                        title: "New Project",
                        subtitle: "Start a fresh workspace",
                        color: .blue
                    ) {
                        showingNewProject = true
                    }

                    welcomeCard(
                        icon: "doc.badge.plus",
                        title: "New Page",
                        subtitle: "Create a new page",
                        color: .green
                    ) {
                        Task {
                            if selectedModuleId == nil,
                               let local = appState.moduleRepository.getLocalModule() {
                                selectedModuleId = local.id
                            }
                            if let _ = try? await appState.noteRepository.createNote(moduleId: selectedModuleId) {
                                onNewPage()
                            }
                        }
                    }

                    welcomeCard(
                        icon: "magnifyingglass",
                        title: "Browse",
                        subtitle: "Find something you've been working on",
                        color: .purple
                    ) {
                        onBrowse()
                    }
                }
                .frame(maxWidth: 600)

                // Recent pages
                if !recentNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("RECENT")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(white: 0.4))
                            .padding(.leading, 4)

                        VStack(spacing: 2) {
                            ForEach(recentNotes) { note in
                                Button {
                                    selectedModuleId = note.moduleId
                                    NotificationCenter.default.post(
                                        name: .sidebarNoteSelected,
                                        object: nil,
                                        userInfo: ["noteId": note.id]
                                    )
                                    onBrowse()
                                } label: {
                                    HStack(spacing: 10) {
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(note.intent.color)
                                            .frame(width: 3, height: 14)

                                        Text(note.displayTitle)
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color(white: 0.75))
                                            .lineLimit(1)

                                        Spacer()

                                        Text(relativeTime(note.updatedDate))
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color(white: 0.35))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(white: 0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: 500)
                }
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .alert("New Project", isPresented: $showingNewProject) {
            TextField("Project name", text: $newProjectName)
            Button("Create") {
                let name = newProjectName
                newProjectName = ""
                Task {
                    if let module = try? await appState.moduleRepository.createModule(name: name) {
                        selectedModuleId = module.id
                        onNewProject()
                    }
                }
            }
            Button("Cancel", role: .cancel) { newProjectName = "" }
        } message: {
            Text("Enter a name for your new project")
        }
    }

    private func welcomeCard(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(color)
                    .frame(width: 48, height: 48)
                    .background(color.opacity(0.1))
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(color.opacity(0.2), lineWidth: 1)
                    )

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.45))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color(white: 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(white: 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
#endif
