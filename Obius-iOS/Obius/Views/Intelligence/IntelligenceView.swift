import SwiftUI

struct IntelligenceView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var insightRepository: InsightRepository
    @State private var isScanning = false
    @State private var selectedInsight: Insight?
    @State private var showCreateSheet = false
    @State private var navigateToNote: Note?
    @State private var navigateSectionId: String?
    @State private var pendingGoToNoteId: String?
    @State private var pendingGoToSectionId: String?
    @State private var showingLoops = false
    @State private var showWorkspaceSheet = false
    @State private var showingSettings = false
    @AppStorage("selectedModuleId") private var selectedModuleId: String?
    @State private var showingModulePicker = false
    @StateObject private var handleManager = HandleManager.shared
    @StateObject private var echoManager = EchoManager.shared
    @State private var activeCategorySheet: InsightType?
    @State private var selectedEcho: Echo?
    @State private var showingManageEchoes = false
    @State private var lastScanFingerprint: Int64 = 0
    @State private var selectedFilter: InsightType?

    private var insightEngine: InsightEngine {
        InsightEngine(
            noteRepository: appState.noteRepository,
            sectionRepository: appState.sectionRepository,
            handleRepository: appState.handleRepository,
            echoRepository: appState.echoRepository,
            insightRepository: insightRepository,
            database: appState.database
        )
    }

    private var selectedModuleName: String {
        appState.moduleRepository.modules.first { $0.id == selectedModuleId }?.name ?? "Artifacts"
    }

    /// Note IDs in the selected module. nil = show all (no filter).
    private var moduleNoteIds: Set<String>? {
        guard let moduleId = selectedModuleId else { return nil }
        return Set(appState.noteRepository.notes.filter { $0.moduleId == moduleId }.map(\.id))
    }

    /// Filter any insight array to the selected module.
    /// Insights with nil sourceNoteId pass through (shown in all modules).
    private func insightsInModule(_ insights: [Insight]) -> [Insight] {
        guard let noteIds = moduleNoteIds else { return insights }
        return insights.filter { insight in
            // Inactive loop insights store handleId in sourceNoteId — show in all modules
            if insight.sourceSectionId == "inactive_loop" { return true }
            guard let sourceNoteId = insight.sourceNoteId else { return true }
            return noteIds.contains(sourceNoteId)
        }
    }

    // MARK: - Category Grouping

    /// Display order for categories on the main view.
    private static let categoryOrder: [InsightType] = [.safety, .link, .list, .cleanup]

    /// Groups surfaced (non-echo) insights by type.
    private var categoryGroups: [(type: InsightType, insights: [Insight])] {
        let nonEcho = insightsInModule(insightRepository.surfacedInsights)
            .filter { $0.insightType != .upcomingEcho }

        var grouped: [InsightType: [Insight]] = [:]
        for insight in nonEcho {
            grouped[insight.insightType, default: []].append(insight)
        }

        return Self.categoryOrder.compactMap { type in
            guard let insights = grouped[type], !insights.isEmpty else { return nil }
            return (type: type, insights: insights)
        }
    }

    var body: some View {
        mainContent
        .background(Color.black)
        .navigationTitle("")
        .inlineNavigationTitle()
        .platformToolbarBackground(.black)
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .offset(y: 2)
                }
            }
            #endif
            ToolbarItem(placement: .principal) {
                Button {
                    showingModulePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(selectedModuleName)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingLoops = true
                } label: {
                    Text("@")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .sheet(item: $selectedInsight, onDismiss: {
            handleInsightSheetDismiss()
        }) { insight in
            insightDetailSheet(for: insight)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateInsightSheet { title, body in
                Task {
                    try? await insightRepository.createInsight(
                        type: .cleanup,
                        title: title,
                        body: body,
                        status: .tracked
                    )
                    haptic(.success)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
            .frame(minWidth: 450, minHeight: 500)
            .preferredColorScheme(.dark)
            .environmentObject(appState)
            .environmentObject(AuthManager.shared)
            .environmentObject(AppearanceManager.shared)
        }
        .sheet(isPresented: $showingLoops) {
            LoopsSheetView(handles: handleManager.handles)
        }
        .sheet(isPresented: $showingModulePicker) {
            ModulePickerSheet(
                moduleRepository: appState.moduleRepository,
                selectedModuleId: $selectedModuleId
            )
        }
        .sheet(isPresented: $showWorkspaceSheet) {
            WorkspaceSheet(handles: handleManager.handles)
                .environmentObject(appState)
        }
        .sheet(item: $selectedEcho) { echo in
            EchoDetailSheet(echo: echo)
        }
        .sheet(isPresented: $showingManageEchoes) {
            ManageEchoesSheet(echoManager: echoManager, onSelect: { echo in
                showingManageEchoes = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    selectedEcho = echo
                }
            })
        }
        .sheet(item: $activeCategorySheet) { type in
            let insights = categoryGroups.first(where: { $0.type == type })?.insights ?? []
            CategoryDetailSheet(
                insightType: type,
                insights: insights,
                onTrack: { insight in
                    Task {
                        try? await insightRepository.trackInsight(insight.id)
                        haptic(.success)
                    }
                },
                onDismiss: { insight in
                    Task {
                        try? await insightRepository.dismissInsight(insight.id)
                    }
                    haptic(.light)
                },
                onSelectInsight: { insight in
                    activeCategorySheet = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        selectedInsight = insight
                    }
                }
            )
        }
        .task {
            if selectedModuleId == nil,
               let local = appState.moduleRepository.getLocalModule() {
                selectedModuleId = local.id
            }
            await runScan()
        }
        .onChange(of: selectedModuleId) { _, _ in
            selectedFilter = nil
            Task { await runScan() }
        }
        .navigationDestination(item: $navigateToNote) { note in
            NoteEditorView(noteId: note.id, targetSectionId: navigateSectionId)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 16) {
                    activeEchoesSection

                    trackedSection

                    if !allSurfacedInsights.isEmpty {
                        categoriesSection
                    }

                    if upcomingEchoInsights.isEmpty
                        && allSurfacedInsights.isEmpty
                        && insightsInModule(insightRepository.trackedInsights).isEmpty
                        && firingEchoes.isEmpty
                        && !isScanning {
                        emptyState
                    }
                }
                .padding()
            }
            .refreshable {
                await refreshIfNeeded()
            }
            .overlay {
                WorkspaceFAB {
                    guard TierManager.shared.requireFeature(.aiWorkspace) else { return }
                    showWorkspaceSheet = true
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    label: "For You",
                    icon: "sparkles",
                    isSelected: selectedFilter == nil,
                    tint: .white
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedFilter = nil
                    }
                }

                ForEach(availableFilterTypes) { type in
                    FilterChip(
                        label: type.label,
                        icon: type.icon,
                        isSelected: selectedFilter == type,
                        tint: type.tint.color
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = type
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Active Echoes

    private var firingEchoes: [Echo] {
        echoManager.activeEchoes.filter { $0.isAlerted }
    }

    private var activeEchoesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ECHOES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            ForEach(firingEchoes) { echo in
                EchoRowView(echo: echo)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedEcho = echo
                    }

                Divider()
            }

            Button {
                showingManageEchoes = true
            } label: {
                HStack {
                    Text("Manage Echoes")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(echoManager.activeEchoes.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                    .background(Color(red: 0.06, green: 0.06, blue: 0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Upcoming Echoes

    private var upcomingEchoInsights: [Insight] {
        insightsInModule(insightRepository.surfacedInsights).filter { $0.insightType == .upcomingEcho }
    }

    private var upcomingEchoesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ECHOES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(upcomingEchoInsights) { insight in
                        UpcomingEchoCard(
                            insight: insight,
                            onTap: {
                                selectedInsight = insight
                            },
                            onLongPress: {
                                selectedInsight = insight
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Filter

    /// Insight types that currently have surfaced insights, in display order.
    private var availableFilterTypes: [InsightType] {
        let presentTypes = Set(allSurfacedInsights.map(\.insightType))
        return Self.categoryOrder.filter { presentTypes.contains($0) }
    }

    // MARK: - Category Cards

    private var allSurfacedInsights: [Insight] {
        insightsInModule(insightRepository.surfacedInsights)
            .filter { $0.insightType != .upcomingEcho }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private var filteredSurfacedInsights: [Insight] {
        guard let filter = selectedFilter else { return allSurfacedInsights }
        return allSurfacedInsights.filter { $0.insightType == filter }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("INSIGHTS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            if !availableFilterTypes.isEmpty {
                filterBar
                    .padding(.horizontal, -16)
                    .padding(.bottom, 8)
            }

            ForEach(filteredSurfacedInsights) { insight in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: insight.displayIcon)
                                .font(.caption2)
                            Text(insight.displayLabel)
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(insight.displayTint.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(insight.displayTint.color.opacity(0.15))
                        .clipShape(Capsule())

                        Spacer()

                        HStack(spacing: 16) {
                            Button {
                                Task {
                                    try? await insightRepository.trackInsight(insight.id)
                                    haptic(.success)
                                }
                            } label: {
                                Image(systemName: "star")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)

                            Button {
                                Task {
                                    try? await insightRepository.dismissInsight(insight.id)
                                }
                                haptic(.light)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text(insight.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if !insight.body.isEmpty {
                        Text(insight.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedInsight = insight
                }

                if insight.id != filteredSurfacedInsights.last?.id {
                    Divider()
                        .padding(.leading, 36)
                }
            }
        }
    }

    // MARK: - Tracked

    private var trackedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TRACKING")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline)
                        .foregroundStyle(Color(.lightGray))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(insightsInModule(insightRepository.trackedInsights).sorted { lhs, rhs in
                        if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                        return lhs.createdAt > rhs.createdAt
                    }) { insight in
                        TrackedInsightChip(
                            insight: insight,
                            onTap: {
                                selectedInsight = insight
                            },
                            onUntrack: {
                                Task {
                                    try? await insightRepository.untrackInsight(insight.id)
                                    haptic(.light)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                EmptyStatePulse()

                Text("All clear")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Workspace FAB (moved to shared WorkspaceFAB component)

    // MARK: - Actions

    private func handleInsightSheetDismiss() {
        if let noteId = pendingGoToNoteId,
           let note = appState.noteRepository.notes.first(where: { $0.id == noteId }) {
            navigateSectionId = pendingGoToSectionId
            navigateToNote = note
        }
        pendingGoToNoteId = nil
        pendingGoToSectionId = nil
    }

    @ViewBuilder
    private func insightDetailSheet(for insight: Insight) -> some View {
        let refs = resolveReferences(for: insight)
        InsightDetailSheet(
            insight: insight,
            onTrack: {
                Task {
                    try? await insightRepository.trackInsight(insight.id)
                    haptic(.success)
                }
            },
            onDismiss: {
                Task {
                    try? await insightRepository.dismissInsight(insight.id)
                }
                haptic(.light)
            },
            onUntrack: {
                Task {
                    try? await insightRepository.untrackInsight(insight.id)
                    haptic(.light)
                }
            },
            onDeleteNote: (insight.insightType == .cleanup && insight.sourceSectionId == "nonsense") ? {
                Task {
                    if let noteId = insight.sourceNoteId {
                        try? await appState.noteRepository.deleteNote(noteId)
                        try? await insightRepository.dismissInsight(insight.id)
                        haptic(.success)
                    }
                }
            } : nil,
            onDeleteLoop: (insight.insightType == .cleanup && insight.sourceSectionId == "inactive_loop") ? {
                Task {
                    if let handleId = insight.sourceNoteId {
                        try? await HandleManager.shared.deleteHandle(id: handleId)
                        try? await insightRepository.dismissInsight(insight.id)
                        haptic(.success)
                    }
                }
            } : nil,
            onCreateBlock: (insight.insightType == .cleanup && insight.sourceSectionId == "dormant_loop") ? { blockName in
                Task {
                    if let noteId = insight.sourceNoteId {
                        try? await appState.noteRepository.setGroupName(noteId: noteId, groupName: blockName)
                        try? await insightRepository.dismissInsight(insight.id)
                        haptic(.success)
                    }
                }
            } : nil,
            references: refs,
            onNavigate: { ref in
                pendingGoToNoteId = ref.noteId
                pendingGoToSectionId = ref.sectionId
            }
        )
    }

    private func resolveReferences(for insight: Insight) -> [InsightReference] {
        var refs: [InsightReference] = []

        if let noteId = insight.sourceNoteId,
           let note = appState.noteRepository.notes.first(where: { $0.id == noteId }) {
            // For new consolidated types, sourceSectionId stores the subtype string — not a real section.
            // Only pass sourceSectionId as a real section for reminder subtypes that kept it from old code.
            let sectionId: String? = nil  // subtypes are never real section IDs
            refs.append(InsightReference(noteId: noteId, title: note.displayTitle, sectionId: sectionId))
        }

        // relatedNoteId may contain comma-separated IDs for multi-reference insights
        if let relatedField = insight.relatedNoteId {
            let relatedIds = relatedField.split(separator: ",").map(String.init)
            for relatedId in relatedIds {
                if let note = appState.noteRepository.notes.first(where: { $0.id == relatedId }) {
                    refs.append(InsightReference(noteId: relatedId, title: note.displayTitle, sectionId: nil))
                }
            }
        }

        return refs
    }

    /// Fingerprint based on note count + max updatedAt — changes when any page is added, deleted, or edited.
    private var currentFingerprint: Int64 {
        let notes = appState.noteRepository.notes.filter { !$0.isDeleted }
        let maxUpdated = notes.map(\.updatedAt).max() ?? 0
        return maxUpdated &+ Int64(notes.count)
    }

    private func runScan() async {
        isScanning = true
        await insightEngine.scan(moduleId: selectedModuleId)
        lastScanFingerprint = currentFingerprint
        isScanning = false
    }

    private func refreshIfNeeded() async {
        guard currentFingerprint != lastScanFingerprint else { return }
        await runScan()
    }

    // MARK: - Haptics

    private func haptic(_ style: HapticFeedback.FeedbackStyle) {
        HapticFeedback.impact(style)
    }

    private func haptic(_ type: HapticFeedback.FeedbackType) {
        HapticFeedback.notification(type)
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? .black : tint)
            .background(
                Capsule()
                    .fill(isSelected ? tint : tint.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(tint.opacity(isSelected ? 0 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String
    var actions: [SuggestedAction]
    let timestamp = Date()

    enum MessageRole {
        case user
        case assistant
    }

    init(role: MessageRole, content: String, actions: [SuggestedAction] = []) {
        self.role = role
        self.content = content
        self.actions = actions
    }
}

// MARK: - Chat Message View

struct ChatMessageView: View {
    let message: ChatMessage
    var onOptionSelect: ((String) -> Void)? = nil

    /// Parsed content: intro text + option items (if any) + trailing text
    private var parsedContent: (intro: String, options: [String], trailing: String) {
        guard message.role == .assistant else { return (message.content, [], "") }

        let lines = message.content.components(separatedBy: "\n")
        var intro: [String] = []
        var options: [String] = []
        var trailing: [String] = []
        var foundOptions = false
        var doneWithOptions = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if !doneWithOptions, isOptionLine(trimmed) {
                foundOptions = true
                let cleaned = stripOptionPrefix(trimmed)
                if !cleaned.isEmpty {
                    options.append(cleaned)
                }
            } else if foundOptions && !doneWithOptions {
                // Non-option line after options started = trailing text
                if trimmed.isEmpty && options.count > 0 {
                    // Allow one blank line between options group and trailing
                    doneWithOptions = true
                } else {
                    doneWithOptions = true
                    trailing.append(line)
                }
            } else if doneWithOptions {
                trailing.append(line)
            } else {
                intro.append(line)
            }
        }

        // Only treat as options if we found 2+ items
        if options.count < 2 {
            return (message.content, [], "")
        }

        return (
            intro.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            options,
            trailing.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func isOptionLine(_ line: String) -> Bool {
        // Match: 1. text, 2) text, - text, • text, * text
        let patterns = [
            #"^\d+[\.\)]\s+"#,
            #"^[-•\*]\s+"#
        ]
        return patterns.contains { line.range(of: $0, options: .regularExpression) != nil }
    }

    private func stripOptionPrefix(_ line: String) -> String {
        line.replacingOccurrences(of: #"^\d+[\.\)]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[-•\*]\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                let parsed = parsedContent

                // Intro text bubble
                if !parsed.intro.isEmpty || parsed.options.isEmpty {
                    let displayText = parsed.options.isEmpty ? message.content : parsed.intro
                    formattedText(displayText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(message.role == .user ? Color.white : Color(red: 0.12, green: 0.12, blue: 0.12))
                        .foregroundStyle(message.role == .user ? .black : Color(.lightGray))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                // Option buttons
                if !parsed.options.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(Array(parsed.options.enumerated()), id: \.offset) { index, option in
                            Button {
                                onOptionSelect?(option)
                            } label: {
                                HStack(spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white.opacity(0.5))
                                        .frame(width: 20, height: 20)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())

                                    formattedText(option)
                                        .font(.subheadline)
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.leading)

                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(white: 0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Trailing text bubble
                if !parsed.trailing.isEmpty {
                    formattedText(parsed.trailing)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.12, green: 0.12, blue: 0.12))
                        .foregroundStyle(Color(.lightGray))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }

            if message.role == .assistant {
                Spacer()
            }
        }
    }

    /// Parse markdown headings and **bold** into styled Text
    private func formattedText(_ input: String) -> Text {
        let lines = input.components(separatedBy: "\n")
        var result = Text("")

        for (index, line) in lines.enumerated() {
            if index > 0 {
                result = result + Text("\n")
            }

            if line.hasPrefix("### ") {
                let content = String(line.dropFirst(4))
                result = result + Text(content).font(.subheadline).bold()
            } else if line.hasPrefix("## ") {
                let content = String(line.dropFirst(3))
                result = result + Text(content).font(.headline).bold()
            } else if line.hasPrefix("# ") {
                let content = String(line.dropFirst(2))
                result = result + Text(content).font(.title3).bold()
            } else {
                result = result + parseBold(line)
            }
        }

        return result
    }

    /// Parse **bold** within a single line
    private func parseBold(_ input: String) -> Text {
        var result = Text("")
        var remaining = input[...]

        while let starIndex = remaining.range(of: "**") {
            let before = remaining[remaining.startIndex..<starIndex.lowerBound]
            result = result + Text(before)

            let afterOpen = remaining[starIndex.upperBound...]
            if let closeIndex = afterOpen.range(of: "**") {
                let boldContent = afterOpen[afterOpen.startIndex..<closeIndex.lowerBound]
                result = result + Text(boldContent).bold()
                remaining = afterOpen[closeIndex.upperBound...]
            } else {
                result = result + Text("**")
                remaining = afterOpen
            }
        }

        result = result + Text(remaining)
        return result
    }
}


// MARK: - Loops Sheet View

/// Sheet that lists all loops, reusing the same row style as the Library page.
struct LoopsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    let handles: [Handle]

    @State private var selectedHandle: Handle?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if handles.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "link")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Loops")
                            .font(.headline)
                        Text("Loops sync content across sections")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(handles) { handle in
                                LoopRowView(handle: handle)
                                    .padding(.horizontal)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedHandle = handle
                                    }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("Loops")
            .inlineNavigationTitle()
            #if os(iOS)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedHandle) { handle in
                LoopDetailSheet(handle: handle)
            }
        }
    }
}

// MARK: - Workspace Sheet

// MARK: - Body Text Editor with Selection + Create Node

#if os(iOS)
/// A UITextView wrapper that supports text selection tracking.
struct BodyTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange?
    var onCreateNode: () -> Void
    var onTextChange: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WidthConstrainedTextView {
        let tv = WidthConstrainedTextView()
        tv.delegate = context.coordinator
        tv.font = .preferredFont(forTextStyle: .caption1)
        tv.textColor = .label
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ tv: WidthConstrainedTextView, context: Context) {
        if tv.text != text {
            tv.text = text
        }
    }

    class WidthConstrainedTextView: UITextView {
        override var intrinsicContentSize: CGSize {
            guard let superview else { return super.intrinsicContentSize }
            let width = superview.bounds.width
            if width > 0 {
                let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
                return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
            }
            return super.intrinsicContentSize
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            invalidateIntrinsicContentSize()
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: BodyTextEditor

        init(_ parent: BodyTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.onTextChange()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let range = textView.selectedRange
            if range.length > 0 {
                parent.selectedRange = range
            } else {
                parent.selectedRange = nil
            }
        }
    }
}
#else
/// macOS body text editor using TextEditor
struct BodyTextEditor: View {
    @Binding var text: String
    @Binding var selectedRange: NSRange?
    var onCreateNode: () -> Void
    var onTextChange: () -> Void

    var body: some View {
        TextEditor(text: $text)
            .font(.caption)
            .scrollContentBackground(.hidden)
            .onChange(of: text) { _, _ in
                onTextChange()
            }
    }
}
#endif

struct WorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    let handles: [Handle]
    var preselectedPageId: String? = nil
    var embedded: Bool = false

    enum FocusMode: String, CaseIterable {
        case pages = "Pages"
        case loops = "Loops"
    }

    enum InteractionMode: String, CaseIterable {
        case edit = "Edit"
        case chat = "Chat"
    }

    @State private var selectedHandleIds: Set<String> = []
    @State private var focusMode: FocusMode?
    @State private var selectedPageId: String?
    @State private var cachedPageSections: [Section] = []
    @State private var editableContent = ""
    @State private var editingHandleId: String?
    @State private var contentHasUnsavedChanges = false
    @State private var interactionMode: InteractionMode?
    @State private var searchText = ""
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @FocusState private var isInputFocused: Bool

    // Editable page content state
    @State private var editableTitle = ""
    @State private var editableBody = ""
    @State private var editableSectionContents: [String: String] = [:]
    @State private var bodySelection: NSRange?
    @State private var showCreateNodeFromSelection = false

    // History — backed by real commits
    @State private var isHistoryExpanded = false
    @State private var pageCommits: [Commit] = []
    @State private var expandedCommitId: String?
    @State private var expandedCommitContent: CommitContent?

    private var selectedHandles: [Handle] {
        handles.filter { selectedHandleIds.contains($0.id) }
    }

    private var primaryHandle: Handle? {
        guard let firstId = selectedHandleIds.sorted().first else { return nil }
        return handles.first { $0.id == firstId }
    }

    @AppStorage("selectedModuleId") private var selectedModuleId: String?

    private var pages: [Note] {
        appState.noteRepository.notes.filter { !$0.isDeleted && $0.moduleId == selectedModuleId }
    }

    private var pageHandles: [Handle] {
        let handleIds = Set(cachedPageSections.compactMap(\.handleId))
        return handles.filter { handleIds.contains($0.id) }
    }

    private var filteredPages: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return pages }
        return pages.filter {
            $0.displayTitle.lowercased().contains(query) ||
            $0.body.lowercased().contains(query)
        }
    }

    private var filteredHandles: [Handle] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return handles }
        return handles.filter {
            $0.displayName.lowercased().contains(query) ||
            $0.content.lowercased().contains(query)
        }
    }

    private var hasSelection: Bool {
        if focusMode == nil && preselectedPageId == nil { return true }
        return selectedPageId != nil || !selectedHandleIds.isEmpty
    }

    private var isProjectWideMode: Bool {
        focusMode == nil && preselectedPageId == nil
    }

    private static let editPlaceholders = [
        "Lets build something...",
        "Drop an idea here...",
        "Give this a shape...",
        "Initialize a concept...",
        "Unfold the vision...",
        "Refine the core...",
        "Architect the thought...",
        "Draft the intent...",
    ]

    private static let chatPlaceholders = [
        "Give this a shape...",
        "Initialize a concept...",
        "Unfold the vision...",
        "Refine the core...",
        "Architect the thought...",
        "Draft the intent...",
    ]

    @State private var currentEditPlaceholder = editPlaceholders.randomElement()!
    @State private var currentChatPlaceholder = chatPlaceholders.randomElement()!

    private var inputPlaceholder: String {
        interactionMode == .edit ? currentEditPlaceholder : currentChatPlaceholder
    }

    private var canSend: Bool {
        guard !isLoading else { return false }
        return !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var workspaceContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !embedded {
                        // Search bar (hidden when something is selected)
                        if !hasSelection {
                            searchBar
                        }

                        // Focus mode selector (hidden when opened from editor with a specific page)
                        if preselectedPageId == nil {
                            focusSelector
                        }

                        // Pages list or Loop list based on mode
                        if focusMode == .pages && preselectedPageId == nil {
                            pagesList
                        } else if focusMode == .loops && preselectedPageId == nil {
                            loopSelector
                        }

                        // Full page content when a page is selected
                        if let pageId = selectedPageId,
                           let page = pages.first(where: { $0.id == pageId }) {
                            pageFullContent(for: page)
                        }

                        // Change history (below page content)
                        if selectedPageId != nil {
                            changeHistory
                        }

                        // Loop content editor (only in loops mode)
                        if focusMode == .loops, let handle = primaryHandle {
                            loopContentEditor(for: handle)
                        }
                    }

                    // Change history at the top of the terminal panel
                    if embedded && selectedPageId != nil {
                        changeHistory
                    }

                    // Mode picker after selection
                    if hasSelection && interactionMode == nil {
                        modePicker
                    }

                    // Chat messages (only after mode chosen)
                    if interactionMode != nil && !messages.isEmpty {
                        chatSection
                    }

                    if interactionMode != nil && isLoading {
                        loadingIndicator
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            }

            // Input bar pinned at bottom (only after mode chosen)
            if interactionMode != nil {
                inputBar
            }
        }
        .background(Color.black)
    }

    var body: some View {
        Group {
            if embedded {
                workspaceContent
            } else {
                NavigationStack {
                    workspaceContent
                        .navigationTitle("Workspace")
                        .inlineNavigationTitle()
                        #if os(iOS)
                        .toolbarBackground(Color.black, for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    savePendingEdits()
                                    dismiss()
                                }
                            }
                        }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            if let preselectedPageId, selectedPageId == nil {
                selectedPageId = preselectedPageId
                focusMode = .pages
                loadSectionsForPage(preselectedPageId)
                loadCommits(for: preselectedPageId)
            }
        }
    }

    // MARK: - Loop Content Editor

    @ViewBuilder
    private func loopContentEditor(for handle: Handle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("@\(handle.displayName)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(handle.intent.color)

                if contentHasUnsavedChanges {
                    Text("Edited")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(handle.intent.color.opacity(0.7))
                        .clipShape(Capsule())
                }

                Spacer()
            }

            TextEditor(text: $editableContent)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 100, maxHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .onChange(of: editableContent) {
                    if editingHandleId == handle.id {
                        contentHasUnsavedChanges = true
                    }
                }
        }
    }

    // MARK: - Full Page Content

    @ViewBuilder
    private func pageFullContent(for note: Note) -> some View {
        let isEditable = preselectedPageId != nil
        return VStack(alignment: .leading, spacing: 0) {
            // Page title
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(note.intent.color)
                    .frame(width: 4, height: 18)
                if isEditable {
                    TextField("Title", text: $editableTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .textFieldStyle(.plain)
                        .onChange(of: editableTitle) { _ in
                            savePageTitle(noteId: note.id)
                        }
                } else {
                    Text(note.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Spacer()
            }
            .padding(.bottom, 8)

            // Page body + sections + interstitials
            VStack(alignment: .leading, spacing: 0) {
                if isEditable {
                    BodyTextEditor(
                        text: $editableBody,
                        selectedRange: $bodySelection,
                        onCreateNode: { createNodeFromSelection(noteId: note.id) },
                        onTextChange: { savePageBody(noteId: note.id) }
                    )
                    .frame(minHeight: 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)

                    // Show "Create Node" button when text is selected
                    if bodySelection != nil {
                        Button {
                            createNodeFromSelection(noteId: note.id)
                        } label: {
                            Label("Create Node from Selection", systemImage: "plus.rectangle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 6)
                    }
                } else {
                    let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !body.isEmpty {
                        Text(body)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 6)
                    }
                }

                let sections = cachedPageSections.filter { $0.deletedAt == nil }
                ForEach(sections) { section in
                    if isEditable {
                        editableSectionRow(for: section)
                    } else {
                        sectionRow(for: section)
                    }

                    // Interstitial text after this section
                    let interstitial = note.textAfterSection(section.id)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !interstitial.isEmpty {
                        Text(interstitial)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                }

                // End interstitial
                let endText = note.endText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !endText.isEmpty {
                    Text(endText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
            .padding(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func sectionRow(for section: Section) -> some View {
        let content = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let handleName = section.handleId
            .flatMap { HandleManager.shared.getHandle(id: $0) }
            .map { "@\($0.displayName)" }

        if section.sectionType == .fold {
            // Node / bubble style
            VStack(alignment: .leading, spacing: 4) {
                if let handleName {
                    Text(handleName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(section.intent.color)
                }

                if section.contentType == .checklist {
                    HStack(spacing: 4) {
                        Image(systemName: content.isEmpty ? "square" : "checkmark.square")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if !content.isEmpty {
                            Text(content)
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                    }
                } else if section.contentType == .image {
                    #if os(iOS)
                    let hashes = content.split(separator: ",").map { entry in
                        String(entry.split(separator: "|").first ?? "")
                    }
                    ImageNodeView(
                        imageHashes: hashes,
                        mediaRepository: appState.mediaRepository,
                        onTap: {}
                    )
                    .frame(height: 160)
                    #endif
                } else if section.contentType == .audio {
                    #if os(iOS)
                    let parts = content.split(separator: "|")
                    let hash = String(parts.first ?? "")
                    let duration = TimeInterval(parts.count > 1 ? String(parts[1]) : "0") ?? 0
                    AudioNodeView(
                        audioHash: hash,
                        duration: duration,
                        mediaRepository: appState.mediaRepository
                    )
                    #endif
                } else if !content.isEmpty {
                    Text(content)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(section.intent.backgroundTint))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.vertical, 2)
        } else {
            // Line style — simple inline text
            HStack(alignment: .top, spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(section.intent.color.opacity(0.5))
                    .frame(width: 2, height: 14)
                    .padding(.top, 2)

                if section.contentType == .image {
                    #if os(iOS)
                    let hashes = content.split(separator: ",").map { entry in
                        String(entry.split(separator: "|").first ?? "")
                    }
                    ImageNodeView(
                        imageHashes: hashes,
                        mediaRepository: appState.mediaRepository,
                        onTap: {}
                    )
                    .frame(height: 160)
                    #endif
                } else if section.contentType == .audio {
                    #if os(iOS)
                    let parts = content.split(separator: "|")
                    let hash = String(parts.first ?? "")
                    let duration = TimeInterval(parts.count > 1 ? String(parts[1]) : "0") ?? 0
                    AudioNodeView(
                        audioHash: hash,
                        duration: duration,
                        mediaRepository: appState.mediaRepository
                    )
                    #endif
                } else if !content.isEmpty {
                    Text(content)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func editableSectionRow(for section: Section) -> some View {
        // Image and audio sections are not text-editable — render them visually
        if section.contentType == .image || section.contentType == .audio {
            sectionRow(for: section)
        } else {
            let handleName = section.handleId
                .flatMap { HandleManager.shared.getHandle(id: $0) }
                .map { "@\($0.displayName)" }

            let binding = Binding<String>(
                get: { editableSectionContents[section.id] ?? section.content },
                set: { editableSectionContents[section.id] = $0 }
            )

            if section.sectionType == .fold {
                // Node / bubble style — editable
                VStack(alignment: .leading, spacing: 4) {
                    if let handleName {
                        Text(handleName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(section.intent.color)
                    }

                    TextField("Content", text: binding, axis: .vertical)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: binding.wrappedValue) { _ in
                            saveSectionContent(sectionId: section.id)
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(section.intent.backgroundTint))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.vertical, 2)
            } else {
                // Line style — editable
                HStack(alignment: .top, spacing: 6) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(section.intent.color.opacity(0.5))
                        .frame(width: 2, height: 14)
                        .padding(.top, 2)

                    TextField("Content", text: binding, axis: .vertical)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: binding.wrappedValue) { _ in
                            saveSectionContent(sectionId: section.id)
                        }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// Create a node from the currently selected body text.
    /// Splits the body into before/after, creates a section with the selected text.
    private func createNodeFromSelection(noteId: String) {
        guard let range = bodySelection,
              range.length > 0,
              let swiftRange = Range(range, in: editableBody) else { return }

        let selectedText = String(editableBody[swiftRange])
        let beforeText = String(editableBody[editableBody.startIndex..<swiftRange.lowerBound])
        let afterText = String(editableBody[swiftRange.upperBound..<editableBody.endIndex])

        // Update the body to only contain the text before the selection
        editableBody = beforeText.trimmingCharacters(in: .whitespacesAndNewlines)
        bodySelection = nil

        Task {
            // Save the trimmed body
            try? await appState.noteRepository.updateNoteBody(noteId, body: editableBody)

            // Create a section with the selected text
            let section = try? await appState.sectionRepository.createSection(
                noteId: noteId,
                content: selectedText.trimmingCharacters(in: .whitespacesAndNewlines),
                contentType: .text,
                sectionType: .fold
            )

            // If there's text after the selection, save it as interstitial content after the new section
            let trimmedAfter = afterText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedAfter.isEmpty, let section = section {
                try? await appState.noteRepository.updateInterstitialContent(
                    noteId,
                    afterSectionId: section.id,
                    content: trimmedAfter
                )
            }

            // Refresh the workspace view
            loadSectionsForPage(noteId)

            // Auto-commit this change
            _ = try? await appState.commitModule.createCommit(
                noteId: noteId,
                name: "Created node from body text"
            )
            loadCommits(for: noteId)
        }
    }

    private func savePageTitle(noteId: String) {
        let title = editableTitle
        Task {
            try? await appState.noteRepository.updateNoteTitle(noteId, title: title.isEmpty ? nil : title)
        }
    }

    private func savePageBody(noteId: String) {
        let body = editableBody
        Task {
            try? await appState.noteRepository.updateNoteBody(noteId, body: body)
        }
    }

    private func saveSectionContent(sectionId: String) {
        guard let content = editableSectionContents[sectionId] else { return }
        Task {
            try? await appState.sectionRepository.updateContent(sectionId, content: content)
        }
    }

    // MARK: - Commit Helpers

    private func loadCommits(for noteId: String) {
        Task {
            if let commits = try? await appState.commitRepository.getCommits(noteId: noteId) {
                await MainActor.run {
                    pageCommits = commits.filter { !$0.isHidden }
                }
            }
        }
    }

    /// Create a commit snapshot after an accepted AI action.
    private func autoCommitAction(_ action: SuggestedAction, noteId: String) {
        Task {
            let name = "AI: \(action.title)"
            _ = try? await appState.commitModule.createCommit(
                noteId: noteId,
                name: name,
                isAutoCommit: false
            )
            // Reload commits to update the history
            loadCommits(for: noteId)
        }
    }

    // MARK: - Change History (backed by real commits)

    private var changeHistory: some View {
        let noteName = pages.first(where: { $0.id == selectedPageId })?.displayTitle ?? "Page"

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHistoryExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                    Text("HISTORY")
                        .font(.caption.weight(.semibold))
                    if !pageCommits.isEmpty {
                        Text("\(pageCommits.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.white.opacity(0.15)))
                    }
                    Spacer()
                    Image(systemName: isHistoryExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isHistoryExpanded {
                if pageCommits.isEmpty {
                    Text("No history yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                } else {
                    let displayCommits = Array(pageCommits.prefix(20))
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(displayCommits.enumerated()), id: \.element.id) { index, commit in
                            CommitRowView(commit: commit, noteName: noteName, isFirst: index == 0, isLast: index == displayCommits.count - 1)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedCommitId == commit.id {
                                            expandedCommitId = nil
                                            expandedCommitContent = nil
                                        } else {
                                            expandedCommitId = commit.id
                                            expandedCommitContent = nil
                                            loadCommitContent(for: commit)
                                        }
                                    }
                                }

                            if expandedCommitId == commit.id {
                                commitContentView(for: commit)
                                    .padding(.leading, 14)
                                    .padding(.top, 4)
                                    .padding(.bottom, 8)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func commitContentView(for commit: Commit) -> some View {
        if let content = expandedCommitContent {
            commitSnapshotCard(content: content, commit: commit)
        } else {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Loading...")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
    }

    private func commitSnapshotCard(content: CommitContent, commit: Commit) -> some View {
        let tint: Color = commit.isAutoCommit ? .orange : .accentColor
        let intentColor = IntentType(rawValue: content.note.intent)?.color ?? tint
        let body = content.note.body.trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 8) {
            if let title = content.note.title, !title.isEmpty {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(intentColor)
                        .frame(width: 3, height: 14)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }

            if !body.isEmpty {
                Text(body)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(content.sections, id: \.id) { section in
                commitSectionRow(section: section)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func commitSectionRow(section: CommitSectionSnapshot) -> some View {
        let text = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let sectionIntent = IntentType(rawValue: section.intent) ?? .idea

        if section.contentType == "image" {
            #if os(iOS)
            let hashes = text.split(separator: ",").map { entry in
                String(entry.split(separator: "|").first ?? "")
            }
            ImageNodeView(
                imageHashes: hashes,
                mediaRepository: appState.mediaRepository,
                onTap: {}
            )
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            #endif
        } else if section.contentType == "audio" {
            #if os(iOS)
            let parts = text.split(separator: "|")
            let hash = String(parts.first ?? "")
            let duration = TimeInterval(parts.count > 1 ? String(parts[1]) : "0") ?? 0
            AudioNodeView(
                audioHash: hash,
                duration: duration,
                mediaRepository: appState.mediaRepository
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(sectionIntent.backgroundTint))
            #endif
        } else if !text.isEmpty {
            if section.sectionType == "fold" {
                VStack(alignment: .leading, spacing: 2) {
                    if let handleId = section.handleId,
                       let handle = HandleManager.shared.getHandle(id: handleId) {
                        Text("@\(handle.displayName)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(sectionIntent.color)
                    }
                    Text(text)
                        .font(.caption2)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(sectionIntent.backgroundTint))
            } else {
                HStack(alignment: .top, spacing: 4) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(sectionIntent.color.opacity(0.5))
                        .frame(width: 2, height: 12)
                        .padding(.top, 1)
                    Text(text)
                        .font(.caption2)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private func loadCommitContent(for commit: Commit) {
        Task {
            do {
                let content = try appState.commitModule.getCommitContent(hash: commit.hash)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        expandedCommitContent = content
                    }
                }
            } catch {
                await MainActor.run {
                    expandedCommitId = nil
                }
            }
        }
    }

    // MARK: - Loop Selector

    private var loopSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            if handles.isEmpty {
                Text("No loops available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else if let selectedHandle = selectedHandleIds.sorted().first.flatMap({ id in handles.first { $0.id == id } }) {
                loopRow(for: selectedHandle)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedHandleIds.removeAll()
                        editableContent = ""
                        editingHandleId = nil
                        contentHasUnsavedChanges = false
                        interactionMode = nil
                        messages.removeAll()
                    }
                } label: {
                    Label("Change loop", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(filteredHandles) { handle in
                    loopRow(for: handle)
                }
            }
        }
    }

    @ViewBuilder
    private func loopRow(for handle: Handle) -> some View {
        let isSelected = selectedHandleIds.contains(handle.id)
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                toggleHandle(handle)
            }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(handle.intent.color)
                    .frame(width: 4, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(handle.displayName)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    let preview = handle.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func toggleHandle(_ handle: Handle) {
        if selectedHandleIds.contains(handle.id) {
            selectedHandleIds.remove(handle.id)
        } else {
            savePendingEdits()
            selectedHandleIds.insert(handle.id)
        }

        // Reset mode when selection changes
        interactionMode = nil
        messages.removeAll()
        searchText = ""

        if let primary = primaryHandle {
            editableContent = primary.content
            editingHandleId = primary.id
            contentHasUnsavedChanges = false
        } else {
            editableContent = ""
            editingHandleId = nil
            contentHasUnsavedChanges = false
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Search pages and loops...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.subheadline)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Focus Selector

    private var focusSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NARROW FOCUS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(FocusMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if focusMode == mode {
                                // Deselect — go back to project-wide
                                focusMode = nil
                                selectedHandleIds.removeAll()
                                selectedPageId = nil
                                cachedPageSections = []
                                editableContent = ""
                                editingHandleId = nil
                                contentHasUnsavedChanges = false
                                interactionMode = nil
                                messages.removeAll()
                            } else {
                                focusMode = mode
                                selectedHandleIds.removeAll()
                                selectedPageId = nil
                                cachedPageSections = []
                                editableContent = ""
                                editingHandleId = nil
                                contentHasUnsavedChanges = false
                                interactionMode = nil
                                messages.removeAll()
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode == .pages ? "doc.text" : "link")
                                .font(.caption)
                            Text(mode.rawValue)
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundColor(focusMode == mode ? .black : Color(.lightGray))
                        .background(focusMode == mode ? Color.white : Color(red: 0.06, green: 0.06, blue: 0.06))
                        .overlay(
                            Capsule()
                                .strokeBorder(focusMode == mode ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Pages List

    private var pagesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selectedPage = pages.first(where: { $0.id == selectedPageId }) {
                pageRow(for: selectedPage)

                if preselectedPageId == nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedPageId = nil
                            cachedPageSections = []
                            selectedHandleIds.removeAll()
                            editableContent = ""
                            editingHandleId = nil
                            contentHasUnsavedChanges = false
                            interactionMode = nil
                            messages.removeAll()
                        }
                    } label: {
                        Label("Change page", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(filteredPages) { note in
                    pageRow(for: note)
                }
            }
        }
    }

    @ViewBuilder
    private func pageRow(for note: Note) -> some View {
        let isSelected = selectedPageId == note.id
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected && preselectedPageId == nil {
                    selectedPageId = nil
                    cachedPageSections = []
                    selectedHandleIds.removeAll()
                    editableContent = ""
                    editingHandleId = nil
                    contentHasUnsavedChanges = false
                    interactionMode = nil
                    messages.removeAll()
                } else if !isSelected {
                    selectedPageId = note.id
                    selectedHandleIds.removeAll()
                    editableContent = ""
                    editingHandleId = nil
                    contentHasUnsavedChanges = false
                    interactionMode = nil
                    messages.removeAll()
                    searchText = ""
                    loadSectionsForPage(note.id)
                    loadCommits(for: note.id)
                }
            }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(note.intent.color)
                    .frame(width: 4, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(note.displayTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    let preview = note.body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var loopsInPageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LOOPS IN PAGE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pageHandles) { handle in
                        let isSelected = selectedHandleIds.contains(handle.id)
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                toggleHandle(handle)
                            }
                        } label: {
                            Text("@\(handle.displayName)")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .foregroundStyle(isSelected ? .white : handle.intent.color)
                                .background(isSelected ? handle.intent.color : .clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(handle.intent.color, lineWidth: 1.5)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 12) {
            modeButton(.edit, icon: "pencil.line", description: "Apply changes")
            modeButton(.chat, icon: "bubble.left.and.text.bubble.right", description: "Discuss content")
        }
        .padding(.top, 4)
    }

    private func modeButton(_ mode: InteractionMode, icon: String, description: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                interactionMode = mode
                messages.removeAll()
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color(.lightGray))
                Text(mode.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.lightGray))
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(red: 0.06, green: 0.06, blue: 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func loadSectionsForPage(_ noteId: String) {
        Task {
            if let sections = try? await appState.sectionRepository.getSections(noteId: noteId) {
                await MainActor.run {
                    cachedPageSections = sections
                    // Populate editable section contents
                    var contents: [String: String] = [:]
                    for section in sections where section.deletedAt == nil {
                        contents[section.id] = section.content
                    }
                    editableSectionContents = contents
                }
            }
            // Populate editable title/body from the note
            if let note = appState.noteRepository.notes.first(where: { $0.id == noteId }) {
                let sections = cachedPageSections
                await MainActor.run {
                    editableTitle = note.displayTitle(sections: sections)
                    editableBody = note.body
                }
            }
        }
    }

    // MARK: - Chat Section

    private var chatSection: some View {
        VStack(spacing: 12) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { messageIndex, message in
                ChatMessageView(message: message, onOptionSelect: { option in
                    inputText = option
                    sendMessage()
                })
                    .id(message.id)

                if message.role == .assistant {
                    ForEach(Array(message.actions.enumerated()), id: \.element.id) { actionIndex, action in
                        ActionCardView(
                            action: action,
                            onAccept: { acceptAction(messageIndex: messageIndex, actionIndex: actionIndex) },
                            onDismiss: { dismissAction(messageIndex: messageIndex, actionIndex: actionIndex) },
                            previewSections: cachedPageSections,
                            mediaRepository: appState.mediaRepository
                        )
                    }
                }
            }
        }
    }

    private var loadingIndicator: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Thinking...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(
                "",
                text: $inputText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if inputText.isEmpty {
                    Text(inputPlaceholder)
                        .foregroundStyle(Color.gray)
                        .padding(.leading, 14)
                        .allowsHitTesting(false)
                }
            }
            .focused($isInputFocused)
            .lineLimit(1...10)
            .onSubmit {
                sendMessage()
            }
            #if os(macOS)
            .background {
                WorkspaceInputKeyHandler(inputText: $inputText)
            }
            #endif

            Button {
                sendMessage()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.body)
                    .foregroundStyle(canSend ? .black : .white)
                    .frame(width: 36, height: 36)
                    .background(canSend ? Color.white : Color.gray.opacity(0.3))
                    .clipShape(Circle())
            }
            .disabled(!canSend)
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black)
    }

    // MARK: - Send Message

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }

        savePendingEdits()

        // Build loop content if loops are selected
        let currentHandles = selectedHandles
        let loopContent: String
        if currentHandles.isEmpty {
            loopContent = ""
        } else {
            loopContent = currentHandles.map { handle in
                let content = handle.id == editingHandleId ? editableContent : handle.content
                let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
                return "Loop: @\(handle.displayName) (id: \(handle.id))\nContent:\n\(cleaned.isEmpty ? "(empty)" : cleaned)"
            }.joined(separator: "\n\n---\n\n")
        }

        messages.append(ChatMessage(role: .user, content: text))
        inputText = ""
        isLoading = true

        let currentMode = interactionMode ?? .edit

        Task {
            do {
                // In project-wide Edit mode, auto-create a new page so the AI has a target
                var autoCreatedPage: Note?
                if isProjectWideMode && currentMode == .edit && selectedPageId == nil {
                    let newPage = try await appState.noteRepository.createNote(
                        moduleId: selectedModuleId
                    )
                    autoCreatedPage = newPage
                    await MainActor.run {
                        selectedPageId = newPage.id
                        loadSectionsForPage(newPage.id)
                        loadCommits(for: newPage.id)
                    }
                }

                // Build structured page context as JSON
                let pageContext: String
                if let autoPage = autoCreatedPage {
                    // Use the auto-created page directly — reactive `pages` may not have it yet
                    pageContext = buildStructuredPageContext(page: autoPage)
                } else if let pageId = selectedPageId,
                          let page = pages.first(where: { $0.id == pageId }) {
                    pageContext = buildStructuredPageContext(page: page)
                } else {
                    pageContext = ""
                }

                let apiMessages = buildAPIMessages()

                var contextParts: [String] = []
                // Always include rich project context in project-wide mode
                let richContext = await buildRichContext(for: text)
                if !richContext.isEmpty { contextParts.append(richContext) }
                if !pageContext.isEmpty { contextParts.append(pageContext) }
                if !loopContent.isEmpty { contextParts.append("Selected loop content:\n\n\(loopContent)") }
                let context = contextParts.joined(separator: "\n\n")

                switch currentMode {
                case .edit:
                    let response = try await ClaudeService.sendWithTools(
                        messages: apiMessages,
                        noteContext: context
                    )

                    // Coalesce multiple micro-actions into a single rewrite_page
                    let finalActions = coalesceMicroActions(response.actions)

                    let content: String
                    if !response.text.isEmpty {
                        content = response.text
                    } else if !finalActions.isEmpty {
                        content = "Here's what I suggest:"
                    } else {
                        content = "I wasn't able to generate a response. Try rephrasing your request."
                    }
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: content,
                        actions: finalActions
                    ))

                case .chat:
                    let responseText = try await ClaudeService.sendChat(
                        messages: apiMessages,
                        noteContext: context
                    )
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: responseText
                    ))
                }
            } catch {
                let errorDesc = "\(error)"
                let errorMessage: String
                if errorDesc.contains("404") || error.localizedDescription.contains("404") {
                    errorMessage = "The AI edge function returned 404. Make sure the ai-proxy function is deployed:\n\n`supabase functions deploy ai-proxy`\n\nand that ANTHROPIC_API_KEY is set in your Supabase project secrets."
                } else if !SupabaseManager.shared.isConfigured {
                    errorMessage = "Supabase is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY to your Info.plist."
                } else if !SupabaseManager.shared.isAuthenticated {
                    errorMessage = "You need to sign in before using AI features."
                } else {
                    errorMessage = "Something went wrong: \(error.localizedDescription)"
                }
                messages.append(ChatMessage(role: .assistant, content: errorMessage))
            }
            isLoading = false
        }
    }

    // MARK: - Content Persistence

    private func savePendingEdits() {
        guard contentHasUnsavedChanges, let handleId = editingHandleId else { return }
        let content = editableContent
        contentHasUnsavedChanges = false
        Task {
            try? await HandleManager.shared.updateContent(handleId: handleId, content: content)
        }
    }

    // MARK: - Action Coalescing

    /// If the AI returns 2+ delete_section / update_section_content calls for the same page,
    /// merge them into a single rewrite_page action so the user sees one preview card.
    private func coalesceMicroActions(_ actions: [SuggestedAction]) -> [SuggestedAction] {
        // Count section-level micro-actions (deletes + updates targeting sections)
        var deleteIds: Set<String> = []
        var sectionUpdates: [String: String] = [:] // sectionId -> newContent
        var otherActions: [SuggestedAction] = []

        for action in actions {
            switch action.actionType {
            case .deleteSection(let p):
                deleteIds.insert(p.sectionId)
            case .updateSectionContent(let p):
                sectionUpdates[p.sectionId] = p.newContent
            default:
                otherActions.append(action)
            }
        }

        // Only coalesce if there are 2+ micro-actions
        let microCount = deleteIds.count + sectionUpdates.count
        guard microCount >= 2, let pageId = selectedPageId else {
            return actions
        }

        // Build keep_sections: all current sections that are NOT being deleted
        let activeSections = cachedPageSections.filter { $0.deletedAt == nil }
        var keepSections: [SuggestedAction.KeepSection] = []
        for section in activeSections {
            if deleteIds.contains(section.id) { continue }
            let newContent = sectionUpdates[section.id]
            keepSections.append(SuggestedAction.KeepSection(
                sectionId: section.id,
                newContent: newContent
            ))
        }

        // Get current page info
        let page = pages.first(where: { $0.id == pageId })
        let noteTitle = page?.displayTitle ?? ""

        // Check if there's an update_page_body in otherActions — pull its body out
        var newBody = page?.body ?? ""
        otherActions = otherActions.filter { action in
            if case .updatePageBody(let p) = action.actionType, p.noteId == pageId {
                newBody = p.newBody
                return false // remove from otherActions, folded into rewrite
            }
            return true
        }

        // Build summary
        var summaryParts: [String] = []
        if deleteIds.count > 0 {
            summaryParts.append("Removed \(deleteIds.count) section\(deleteIds.count == 1 ? "" : "s")")
        }
        if sectionUpdates.count > 0 {
            summaryParts.append("Updated \(sectionUpdates.count) section\(sectionUpdates.count == 1 ? "" : "s")")
        }
        let summary = summaryParts.joined(separator: ", ")

        // Build page preview showing what the page will look like after the edit
        var previewParts: [String] = []
        let trimmedBody = newBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty { previewParts.append(trimmedBody) }
        for section in activeSections {
            if deleteIds.contains(section.id) { continue }
            // Use updated content if available, otherwise existing content
            let content: String
            if let updated = sectionUpdates[section.id] {
                content = updated
            } else {
                content = section.content
            }
            if section.contentType == .image {
                let count = content.split(separator: ",").count
                let label = count > 1 ? "[\(count) Photos]" : "[Photo]"
                let prefix = section.sectionType == .fold ? "▪ " : "│ "
                previewParts.append("\(prefix)\(label)")
            } else if section.contentType == .audio {
                let parts = content.split(separator: "|")
                let duration = TimeInterval(parts.count > 1 ? String(parts[1]) : "0") ?? 0
                let mins = Int(duration) / 60
                let secs = Int(duration) % 60
                let label = "[Audio Recording \(String(format: "%d:%02d", mins, secs))]"
                let prefix = section.sectionType == .fold ? "▪ " : "│ "
                previewParts.append("\(prefix)\(label)")
            } else {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let prefix = section.sectionType == .fold ? "▪ " : "│ "
                    previewParts.append("\(prefix)\(trimmed)")
                }
            }
        }
        let pagePreview = previewParts.joined(separator: "\n\n")

        let rewriteAction = SuggestedAction(
            id: UUID().uuidString,
            actionType: .rewritePage(SuggestedAction.RewritePageParams(
                noteId: pageId,
                noteTitle: noteTitle,
                newBody: newBody,
                keepSections: keepSections,
                summary: summary,
                pagePreview: pagePreview
            ))
        )

        return [rewriteAction] + otherActions
    }

    // MARK: - Context Builder

    /// Strip non-readable content (base64 RTF, encoded data) from text.
    /// `truncate` limits to 300 chars for broad project summaries; false sends full content for the focused page.
    private static func cleanContentForAI(_ text: String, truncate: Bool = true) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Skip base64-encoded RTF blobs
        if trimmed.hasPrefix("e]") || trimmed.hasPrefix("ew0") || trimmed.hasPrefix("eyJ") ||
           trimmed.contains("{\\rtf") || trimmed.contains("\\fonttbl") {
            return ""
        }
        return truncate ? String(trimmed.prefix(300)) : trimmed
    }

    /// Build a structured JSON representation of the focused page for AI context.
    /// Sends full content (no truncation) so the AI can see everything it needs for restructuring.
    private func buildStructuredPageContext(page: Note) -> String {
        let activeSections = cachedPageSections.filter { $0.deletedAt == nil }

        var sectionDicts: [[String: Any]] = []
        for (index, section) in activeSections.prefix(50).enumerated() {
            let content = Self.cleanContentForAI(section.content, truncate: false)
            var dict: [String: Any] = [
                "id": section.id,
                "content": content,
                "type": section.sectionType == .fold ? "node" : "line",
                "content_type": section.contentType.rawValue,
                "indent": section.indentLevel,
                "intent": section.intent.rawValue,
                "order": index
            ]
            if let hId = section.handleId,
               let h = HandleManager.shared.getHandle(id: hId) {
                dict["handle"] = "@\(h.displayName)"
                dict["handle_id"] = hId
            }
            sectionDicts.append(dict)
        }

        // Build interstitial map — full content
        var interstitials: [String: String] = [:]
        for (key, value) in page.interstitialContent {
            let content = Self.cleanContentForAI(value, truncate: false)
            if !content.isEmpty {
                interstitials[key] = content
            }
        }

        let noteDict: [String: Any] = [
            "id": page.id,
            "title": page.displayTitle,
            "intent": page.intent.rawValue,
            "body": Self.cleanContentForAI(page.body, truncate: false),
            "sections": sectionDicts,
            "interstitial_content": interstitials,
            "tags": page.tags + page.aiTags
        ]

        let wrapper: [String: Any] = ["focused_page": noteDict]

        if let data = try? JSONSerialization.data(withJSONObject: wrapper, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }

        // Fallback to flat text
        return "Focused page (id: \(page.id)): \"\(page.displayTitle)\""
    }

    private func buildRichContext(for query: String) async -> String {
        var parts: [String] = []

        let notes = appState.noteRepository.notes.filter { !$0.isDeleted }

        // Full project content — include note bodies and section content
        // so the AI can see the entire project, not just loops.
        var noteDetails: [String] = []
        for note in notes.prefix(25) {
            let title = note.displayTitle
            let intent = note.intent.rawValue
            let body = Self.cleanContentForAI(note.body)

            var noteEntry = "Page: \"\(title)\" (intent: \(intent))"
            if !body.isEmpty {
                noteEntry += "\n  Body: \(body)"
            }

            // Include section content
            if let sections = try? await appState.sectionRepository.getSections(noteId: note.id) {
                let textSections = sections
                    .filter { $0.contentType == .text || $0.contentType == .checklist || $0.contentType == .quote }
                    .prefix(8)
                var sectionPreviews: [String] = []
                for section in textSections {
                    let cleaned = Self.cleanContentForAI(section.content)
                    guard !cleaned.isEmpty else { continue }
                    let handleTag = section.handleId
                        .flatMap { HandleManager.shared.getHandle(id: $0) }
                        .map { "@\($0.displayName): " } ?? ""
                    sectionPreviews.append("    \(handleTag)\(cleaned)")
                }
                if !sectionPreviews.isEmpty {
                    noteEntry += "\n  Sections:\n\(sectionPreviews.joined(separator: "\n"))"
                }
            }

            // Include interstitial content
            let interstitials = note.interstitialContent.values
                .map { Self.cleanContentForAI($0) }
                .filter { !$0.isEmpty }
                .prefix(3)
            if !interstitials.isEmpty {
                noteEntry += "\n  Between sections: \(interstitials.joined(separator: " | "))"
            }

            noteDetails.append(noteEntry)
        }

        if !noteDetails.isEmpty {
            let header = "Project pages (\(notes.count) total):"
            parts.append("\(header)\n\n\(noteDetails.joined(separator: "\n\n"))")
        }

        // All loops with their content
        let allHandles = HandleManager.shared.handles
        if !allHandles.isEmpty {
            let loopDetails = allHandles.prefix(20).map { handle in
                let preview = Self.cleanContentForAI(handle.content)
                let suffix = preview.isEmpty ? " (empty)" : "\n  Content: \(preview)"
                return "  @\(handle.displayName) (\(handle.intent.rawValue))\(suffix)"
            }
            parts.append("Project loops (\(allHandles.count) total):\n\(loopDetails.joined(separator: "\n"))")
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - API Message Builder

    private func buildAPIMessages() -> [ClaudeService.Message] {
        var apiMessages: [ClaudeService.Message] = []

        for message in messages {
            apiMessages.append(ClaudeService.Message(
                role: message.role == .user ? "user" : "assistant",
                content: message.content
            ))

            if message.role == .assistant && !message.actions.isEmpty {
                let resolvedSummaries = message.actions.compactMap { action -> String? in
                    switch action.status {
                    case .accepted:
                        return "[\(action.toolName) was accepted and executed]"
                    case .dismissed:
                        return "[\(action.toolName) was dismissed by user]"
                    case .failed(let reason):
                        return "[\(action.toolName) failed: \(reason)]"
                    case .pending:
                        return nil
                    }
                }
                if !resolvedSummaries.isEmpty {
                    apiMessages.append(ClaudeService.Message(
                        role: "user",
                        content: resolvedSummaries.joined(separator: "\n")
                    ))
                }
            }
        }

        return apiMessages
    }

    // MARK: - Action Handlers

    private func acceptAction(messageIndex: Int, actionIndex: Int) {
        guard messageIndex < messages.count,
              actionIndex < messages[messageIndex].actions.count else { return }

        let action = messages[messageIndex].actions[actionIndex]
        guard action.status == .pending else { return }

        Task {
            do {
                try await action.execute(appState: appState)

                // If this was a loop content update, refresh the editor
                if case .updateLoopContent(let p) = action.actionType,
                   p.handleId == editingHandleId {
                    editableContent = p.newContent
                    contentHasUnsavedChanges = false
                }

                // Refresh cached sections and editable fields after any structural change
                if let pageId = selectedPageId {
                    switch action.actionType {
                    case .deleteSection, .updateSectionContent, .addSection, .moveSection, .setSectionIntent:
                        loadSectionsForPage(pageId)
                    case .updatePageBody(let p) where p.noteId == pageId:
                        await MainActor.run { editableBody = p.newBody }
                    case .rewritePage(let p) where p.noteId == pageId:
                        loadSectionsForPage(pageId)
                        await MainActor.run { editableBody = p.newBody }
                    default:
                        break
                    }
                }

                await MainActor.run {
                    messages[messageIndex].actions[actionIndex] = action.withStatus(.accepted)
                    isHistoryExpanded = true
                }

                // Auto-commit the change so it appears in page history
                if let pageId = selectedPageId {
                    autoCommitAction(action, noteId: pageId)
                }

                haptic(.success)
            } catch {
                await MainActor.run {
                    messages[messageIndex].actions[actionIndex] = action.withStatus(.failed(error.localizedDescription))
                }
                haptic(.error)
            }
        }
    }

    private func dismissAction(messageIndex: Int, actionIndex: Int) {
        guard messageIndex < messages.count,
              actionIndex < messages[messageIndex].actions.count else { return }

        let action = messages[messageIndex].actions[actionIndex]
        guard action.status == .pending else { return }

        messages[messageIndex].actions[actionIndex] = action.withStatus(.dismissed)
        haptic(.light)
    }

    // MARK: - Haptics

    private func haptic(_ style: HapticFeedback.FeedbackStyle) {
        HapticFeedback.impact(style)
    }

    private func haptic(_ type: HapticFeedback.FeedbackType) {
        HapticFeedback.notification(type)
    }
}

// MARK: - Shift+Return Key Handler (macOS)

#if os(macOS)
/// Invisible NSView that installs a local event monitor so Shift+Return
/// inserts a newline into the workspace input instead of sending.
struct WorkspaceInputKeyHandler: NSViewRepresentable {
    @Binding var inputText: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Return key = keyCode 36
            if event.keyCode == 36, event.modifierFlags.contains(.shift) {
                DispatchQueue.main.async {
                    self.inputText += "\n"
                }
                return nil // swallow the event
            }
            return event
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var monitor: Any?
        deinit {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
#endif

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

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
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

// MARK: - Empty State Pulse

/// Separate view so SwiftUI destroys animation state when removed.
private struct EmptyStatePulse: View {
    @State private var pulse = false

    var body: some View {
        Image(systemName: "brain.head.profile")
            .font(.system(size: 36))
            .foregroundStyle(Color(white: 0.25))
            .opacity(pulse ? 0.4 : 0.7)
            .onAppear {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

#Preview {
    let appState = AppState()
    NavigationStack {
        IntelligenceView()
            .environmentObject(appState.insightRepository)
    }
    .environmentObject(appState)
}
