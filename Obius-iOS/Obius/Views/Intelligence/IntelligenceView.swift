import SwiftUI

struct IntelligenceView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var insightRepository: InsightRepository
    @State private var isScanning = false
    @State private var selectedInsight: Insight?
    @State private var showCreateSheet = false
    @State private var scheduleEchoInsight: Insight?
    @State private var navigateToNote: Note?
    @State private var navigateSectionId: String?
    @State private var pendingGoToNoteId: String?
    @State private var pendingGoToSectionId: String?
    @State private var showingLoops = false
    @State private var showWorkspaceSheet = false
    @State private var showMacWorkspace = false
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
    @State private var rescanTask: Task<Void, Never>?

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

    /// Display order for categories on the main view. Momentum sits near the
    /// top so the weekly pulse card acts as a dashboard summary above the
    /// actionable detection results.
    private static let categoryOrder: [InsightType] = [.safety, .progress, .schedule, .link, .list, .cleanup]

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
                    // Opaque black capsule keeps the project name legible when
                    // content scrolls behind the toolbar.
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.black)
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )
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
        .sheet(item: $scheduleEchoInsight) { insight in
            let fireDate: Date = {
                if let ms = insight.relatedNoteId.flatMap({ Int64($0) }) {
                    return Date(timeIntervalSince1970: Double(ms) / 1000)
                }
                return Date().addingTimeInterval(3600)
            }()
            let note = appState.noteRepository.notes.first { $0.id == insight.sourceNoteId }
            let rawName = note?.displayTitle ?? "Scheduled"
            let handleName = String(rawName
                .replacingOccurrences(of: " ", with: "_")
                .filter { $0.isLetter || $0.isNumber || $0 == "_" }
                .prefix(50))
            let bodyPreview = String((note?.body ?? "").prefix(200))

            CreateEchoSheet(
                prefillName: handleName,
                prefillContent: bodyPreview,
                prefillDate: fireDate,
                onCreated: {
                    Task {
                        try? await insightRepository.dismissInsight(insight.id)
                        haptic(.success)
                    }
                }
            )
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
            #if os(macOS)
            .frame(minWidth: 450, minHeight: 500)
            #endif
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
        .onChange(of: currentFingerprint) { _, newValue in
            guard newValue != lastScanFingerprint else { return }
            rescanTask?.cancel()
            rescanTask = Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s debounce
                guard !Task.isCancelled else { return }
                await runScan()
            }
        }
        .navigationDestination(item: $navigateToNote) { note in
            NoteEditorView(noteId: note.id, targetSectionId: navigateSectionId)
        }
        #if os(macOS)
        .navigationDestination(isPresented: $showMacWorkspace) {
            MacAIWorkspaceView()
                .environmentObject(appState)
        }
        #endif
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 16) {
                    EchoCalendarView(calendarMemoRepository: appState.calendarMemoRepository)

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
                    #if os(macOS)
                    showMacWorkspace = true
                    #else
                    showWorkspaceSheet = true
                    #endif
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
            onCreateEcho: (insight.insightType == .schedule) ? {
                // Defer to after the insight sheet dismisses, then show CreateEchoSheet
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    scheduleEchoInsight = insight
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

                // Main text content
                if !parsed.intro.isEmpty || parsed.options.isEmpty {
                    let displayText = parsed.options.isEmpty ? message.content : parsed.intro
                    if message.role == .user {
                        // User messages: keep bubble
                        formattedText(displayText)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        // AI messages: inline text, no bubble
                        formattedText(displayText)
                            .textSelection(.enabled)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.vertical, 4)
                    }
                }

                // Option buttons (clarity options — keep styled)
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

                // Trailing text
                if !parsed.trailing.isEmpty {
                    formattedText(parsed.trailing)
                        .textSelection(.enabled)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.vertical, 4)
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
    @State private var selectedFilter: LoopFilter = .all
    @State private var showingCreateSheet = false

    private var filteredHandles: [Handle] {
        guard let intent = selectedFilter.intent else { return handles }
        return handles.filter { $0.intent == intent }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Centered intent filter bar
                if !handles.isEmpty {
                    HStack {
                        Spacer()
                        loopFilterBar
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }

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
                } else if filteredHandles.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No loops match this filter")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredHandles) { handle in
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
                        .padding(.top, 4)
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
                ToolbarItem(placement: .primaryAction) {
                    Button("+ New") {
                        showingCreateSheet = true
                    }
                }
            }
            .sheet(item: $selectedHandle) { handle in
                LoopDetailSheet(handle: handle)
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateLoopSheet()
            }
        }
    }

    private var loopFilterBar: some View {
        HStack(spacing: 4) {
            ForEach(LoopFilter.allCases, id: \.self) { filter in
                let isSelected = selectedFilter == filter
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedFilter = filter
                    }
                } label: {
                    Group {
                        if filter == .all {
                            Text("All")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(isSelected ? Color.primary : .secondary)
                                .padding(.horizontal, isSelected ? 10 : 8)
                                .padding(.vertical, 5)
                        } else {
                            Capsule()
                                .fill(filter.tint)
                                .frame(width: 22, height: 8)
                                .opacity(isSelected ? 1 : 0.55)
                                .padding(.horizontal, isSelected ? 8 : 6)
                                .padding(.vertical, 6)
                        }
                    }
                    .contentShape(Capsule())
                    .background(
                        Capsule()
                            .fill(isSelected ? filter.tint.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Workspace Sheet

// MARK: - Body Text Editor with Selection + Create Node

#if os(iOS)
/// A UITextView wrapper that supports rich text, a formatting keyboard
/// toolbar, and text-selection tracking (for "Create Node from Selection").
struct BodyTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange?
    var richText: String? = nil
    var onCreateNode: () -> Void
    var onTextChange: (String, String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WidthConstrainedTextView {
        let tv = WidthConstrainedTextView()
        tv.delegate = context.coordinator
        tv.font = .preferredFont(forTextStyle: .body)
        tv.textColor = .label
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Keyboard accessory toolbar — reuses the main editor's formatting
        // controls so AI-generated headings/bold/italic are editable in-place.
        let toolbar = BodyKeyboardToolbar()
        toolbar.textView = tv
        toolbar.onDismiss = { [weak tv] in
            tv?.resignFirstResponder()
        }
        tv.inputAccessoryView = toolbar

        // Load rich text if present, otherwise plain text
        if let richText = richText,
           let attrText = RichTextHelper.deserialize(richText) {
            tv.attributedText = attrText
        } else {
            tv.text = text
        }
        context.coordinator.lastAppliedRichText = richText
        return tv
    }

    func updateUIView(_ tv: WidthConstrainedTextView, context: Context) {
        let textChanged = tv.text != text
        let richTextChanged = richText != context.coordinator.lastAppliedRichText

        if tv.isFirstResponder && textChanged && !richTextChanged {
            // Binding round-trip while typing — skip to avoid cursor jumps.
            context.coordinator.lastAppliedRichText = richText
            return
        }

        if textChanged || richTextChanged {
            tv.delegate = nil
            if let richText = richText,
               let attrText = RichTextHelper.deserialize(richText) {
                tv.attributedText = attrText
            } else {
                tv.text = text
            }
            tv.delegate = context.coordinator
            context.coordinator.lastAppliedRichText = richText
            tv.invalidateIntrinsicContentSize()
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
        var lastAppliedRichText: String?

        init(_ parent: BodyTextEditor) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if let toolbar = textView.inputAccessoryView as? BodyKeyboardToolbar {
                toolbar.syncWithTypingAttributes()
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            // Serialize rich text on focus loss so formatting changes persist.
            let rich = RichTextHelper.serialize(textView.attributedText)
            let newText = textView.text ?? ""
            parent.text = newText
            parent.onTextChange(newText, rich)
        }

        func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            parent.text = newText
            textView.invalidateIntrinsicContentSize()
            // Skip RTF serialization during active typing — covered by focus loss.
            parent.onTextChange(newText, nil)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let range = textView.selectedRange
            if range.length > 0 {
                parent.selectedRange = range
            } else {
                parent.selectedRange = nil
            }
            if let toolbar = textView.inputAccessoryView as? BodyKeyboardToolbar {
                toolbar.syncWithTypingAttributes()
            }
        }
    }
}

// MARK: - Workspace Chat Input (UITextView-based)

/// No inputAccessoryView: SwiftUI's keyboard avoidance lifts the safeAreaInset
/// inputBar directly to the top of the keyboard, putting it right above the
/// predictive strip. Deliberately omits @FocusState.Binding — setting
/// @FocusState from UIKit when no .focused() target exists on iOS caused
/// SwiftUI to resign the UITextView mid-typing.
struct WorkspaceChatTextView: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 40
    var maxHeight: CGFloat = 120

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = .preferredFont(forTextStyle: .body)
        tv.textColor = .label
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        tv.textContainer.lineFragmentPadding = 0
        tv.text = text
        tv.setContentHuggingPriority(.required, for: .vertical)
        tv.setContentCompressionResistancePriority(.required, for: .vertical)

        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.numberOfLines = 0
        placeholderLabel.isHidden = !text.isEmpty
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        tv.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: tv.leadingAnchor, constant: 14),
            placeholderLabel.topAnchor.constraint(equalTo: tv.topAnchor, constant: 10),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: tv.trailingAnchor, constant: -14),
        ])
        context.coordinator.placeholderLabel = placeholderLabel

        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            tv.text = text
            context.coordinator.placeholderLabel?.isHidden = !text.isEmpty
            tv.invalidateIntrinsicContentSize()
        }
    }

    /// Tells SwiftUI the chat field's preferred height for a given proposed
    /// width: the content's natural height clamped to [minHeight, maxHeight].
    /// Without this, SwiftUI lets the UITextView fill the screen.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let exceeded = measured.height > maxHeight
        if uiView.isScrollEnabled != exceeded {
            uiView.isScrollEnabled = exceeded
        }
        let h = min(max(measured.height, minHeight), maxHeight)
        return CGSize(width: width, height: h)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: WorkspaceChatTextView
        weak var placeholderLabel: UILabel?

        init(_ parent: WorkspaceChatTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            placeholderLabel?.isHidden = !textView.text.isEmpty
            textView.invalidateIntrinsicContentSize()
        }
    }
}
#else
/// macOS body text editor — wraps the rich-text `EditableTextView` so AI-
/// generated headings / bold / italic are visible and editable inside the
/// AI Workspace. `selectedRange` is accepted for signature compatibility
/// with iOS but not currently driven — Create-Node-from-Selection is an
/// iOS-only affordance.
struct BodyTextEditor: View {
    @Binding var text: String
    @Binding var selectedRange: NSRange?
    var richText: String? = nil
    var onCreateNode: () -> Void
    var onTextChange: (String, String?) -> Void

    @FocusState private var bodyFocused: Bool
    @State private var editorHeight: CGFloat = 22

    var body: some View {
        EditableTextView(
            text: $text,
            isFocused: $bodyFocused,
            richText: richText,
            onContentChange: { newValue, richText in
                onTextChange(newValue, richText)
            },
            onFocusChange: { _ in },
            sectionId: nil,
            dynamicHeight: $editorHeight
        )
        .frame(minHeight: max(22, editorHeight))
    }
}
#endif

// MARK: - Per-section rich-text editor wrapper

/// Each section needs its own `@FocusState`, so this wrapper gives every row
/// an isolated focus target while sharing the same rich-text `EditableTextView`
/// the main editor uses. Ensures AI-generated bold/italic/headings remain
/// visible and editable inside the AI Workspace on both platforms.
struct WorkspaceSectionEditor: View {
    let section: Section
    let appState: AppState
    @Binding var content: String
    @FocusState private var textFieldFocused: Bool
    @State private var editorHeight: CGFloat = 22

    private var handleName: String? {
        section.handleId
            .flatMap { HandleManager.shared.getHandle(id: $0) }
            .map { "@\($0.displayName)" }
    }

    var body: some View {
        if section.sectionType == .fold {
            VStack(alignment: .leading, spacing: 4) {
                if let handleName {
                    Text(handleName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(section.intent.color)
                }
                editor
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(section.intent.backgroundTint))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.vertical, 2)
        } else {
            HStack(alignment: .top, spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(section.intent.color.opacity(0.5))
                    .frame(width: 2, height: 14)
                    .padding(.top, 2)
                editor
            }
            .padding(.vertical, 2)
        }
    }

    private func saveContent(_ newValue: String, _ richText: String?) {
        Task {
            try? await appState.sectionRepository.updateContent(
                section.id,
                content: newValue,
                richText: richText,
                clearRichText: richText == nil
            )
        }
    }

    @ViewBuilder
    private var editor: some View {
        #if os(macOS)
        EditableTextView(
            text: $content,
            isFocused: $textFieldFocused,
            richText: section.richContent,
            onContentChange: saveContent,
            onFocusChange: { _ in },
            sectionId: section.id,
            dynamicHeight: $editorHeight
        )
        .frame(maxWidth: .infinity, minHeight: max(22, editorHeight), alignment: .topLeading)
        #else
        EditableTextView(
            text: $content,
            isFocused: $textFieldFocused,
            richText: section.richContent,
            onContentChange: saveContent,
            onFocusChange: { _ in }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }
}

struct WorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    let handles: [Handle]
    var preselectedPageId: String? = nil
    var preselectedSectionId: String? = nil
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
    @State private var focusedSectionId: String?  // Section-level AI editing target
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @FocusState private var isInputFocused: Bool

    // Streaming state (live preview while AI builds the template page)
    @State private var streamingText: String = ""
    @State private var streamingToolName: String? = nil
    @State private var streamingToolPartialJSON: String = ""
    @State private var streamingCompletedActions: [SuggestedAction] = []

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
        "What's on your mind?",
        "Start with anything…",
        "There's something here—write it",
        "Don't overthink it. Just begin",
        "Capture the spark",
        "What are you trying to figure out?",
        "Put it down before it disappears",
        "This could turn into something",
        "Start messy. We'll shape it later",
    ]

    private static let chatPlaceholders = [
        "What are you exploring?",
        "What do you want to understand?",
        "Let's dig into something",
        "What's the question behind this?",
        "Where should we start?",
        "What's unclear right now?",
        "Let's figure this out",
        "What's interesting about this?",
        "What are you trying to solve?",
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

    private var hasStreamingContent: Bool {
        !streamingText.isEmpty
            || streamingToolName != nil
            || !streamingCompletedActions.isEmpty
    }

    private func resetStreamingState() {
        streamingText = ""
        streamingToolName = nil
        streamingToolPartialJSON = ""
        streamingCompletedActions = []
    }

    private var workspaceContent: some View {
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

                    if hasStreamingContent {
                        StreamingPreviewCard(
                            partialText: streamingText,
                            currentToolName: streamingToolName,
                            currentToolPartialJSON: streamingToolPartialJSON,
                            completedActions: streamingCompletedActions,
                            previewSections: cachedPageSections,
                            mediaRepository: appState.mediaRepository
                        )
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .background(Color.black)
        // safeAreaInset (not VStack) so SwiftUI keyboard avoidance lifts the
        // input above iOS 26's floating accessory toolbar.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if interactionMode != nil {
                inputBar
            }
        }
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

            // Section-level AI editing: pre-focus on a specific section
            if let sectionId = preselectedSectionId {
                focusedSectionId = sectionId
                interactionMode = .edit
            }

            // Background reindex for smart context retrieval
            Task {
                let notes = appState.noteRepository.notes.filter { !$0.isDeleted }
                var sectionsByNote: [String: [Section]] = [:]
                for note in notes {
                    if let sections = try? await appState.sectionRepository.getSections(noteId: note.id) {
                        sectionsByNote[note.id] = sections
                    }
                }
                let handles = HandleManager.shared.handles
                await appState.noteIndexRepository.reindex(
                    notes: notes,
                    sectionsByNote: sectionsByNote,
                    handles: handles
                )
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
                    DispatchQueue.main.async {
                        if editingHandleId == handle.id {
                            contentHasUnsavedChanges = true
                        }
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
                            DispatchQueue.main.async { savePageTitle(noteId: note.id) }
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
                        richText: note.bodyRichText,
                        onCreateNode: { createNodeFromSelection(noteId: note.id) },
                        onTextChange: { body, richText in
                            savePageBody(noteId: note.id, body: body, richText: richText)
                        }
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
            let binding = Binding<String>(
                get: { editableSectionContents[section.id] ?? section.content },
                set: { editableSectionContents[section.id] = $0 }
            )
            WorkspaceSectionEditor(
                section: section,
                appState: appState,
                content: binding
            )
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

    private func savePageBody(noteId: String, body: String, richText: String?) {
        Task {
            try? await appState.noteRepository.updateNoteBody(
                noteId,
                body: body,
                richText: richText,
                clearRichText: richText == nil
            )
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
            // Version ID — tap to copy
            Button {
                #if os(iOS)
                UIPasteboard.general.string = commit.shortId
                #elseif os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(commit.shortId, forType: .string)
                #endif
                haptic(.light)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 8))
                    Text(commit.shortId)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(tint.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(tint.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            if let title = content.note.title, !title.isEmpty {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(intentColor)
                        .frame(width: 3, height: 14)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }

            if !body.isEmpty {
                Text(body)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            ForEach(content.sections, id: \.id) { section in
                commitSectionRow(section: section)
            }

            Divider().opacity(0.3)

            Button {
                let fullText = commitFullText(content: content)
                #if os(iOS)
                UIPasteboard.general.string = fullText
                #elseif os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(fullText, forType: .string)
                #endif
                haptic(.success)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy Page")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
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

    private func commitFullText(content: CommitContent) -> String {
        var parts: [String] = []
        if let title = content.note.title, !title.isEmpty {
            parts.append(title)
        }
        let body = content.note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            parts.append(body)
        }
        for section in content.sections {
            let text = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty && section.contentType != "image" && section.contentType != "audio" {
                if let handleId = section.handleId, section.sectionType == "fold",
                   let handle = HandleManager.shared.getHandle(id: handleId) {
                    parts.append("@\(handle.displayName)\n\(text)")
                } else {
                    parts.append(text)
                }
            }
        }
        return parts.joined(separator: "\n\n")
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
                        .textSelection(.enabled)
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
                        .textSelection(.enabled)
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

    /// Fire-and-forget wrapper for non-critical callers (page selection, onAppear, etc.)
    private func loadSectionsForPage(_ noteId: String) {
        Task { await refreshPageState(noteId) }
    }

    /// Awaitable refresh that reads fresh note + sections from DB and updates all editable state.
    @MainActor
    private func refreshPageState(_ noteId: String) async {
        if let sections = try? await appState.sectionRepository.getSections(noteId: noteId) {
            cachedPageSections = sections
            var contents: [String: String] = [:]
            for section in sections where section.deletedAt == nil {
                contents[section.id] = section.content
            }
            editableSectionContents = contents
        }
        if let note = try? await appState.noteRepository.getNote(id: noteId) {
            editableTitle = note.displayTitle(sections: cachedPageSections)
            editableBody = note.body
            print("[Workspace] refreshPageState: body=\(note.body.prefix(60)) sections=\(cachedPageSections.count)")
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

    private static let loadingPhrases = [
        "Looping...", "Dooping...", "Hooping...",
        "Mooping...", "Zooping...", "Pooping..."
    ]

    @State private var loadingPhraseIndex = 0

    private var loadingIndicator: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text(Self.loadingPhrases[loadingPhraseIndex % Self.loadingPhrases.count])
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .onAppear {
                    DispatchQueue.main.async { loadingPhraseIndex = 0 }
                }
                .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            loadingPhraseIndex += 1
                        }
                    }
                }
            Spacer()
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            #if os(iOS)
            WorkspaceChatTextView(
                text: $inputText,
                placeholder: inputPlaceholder
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            #else
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

        let currentHandles = selectedHandles

        messages.append(ChatMessage(role: .user, content: text))
        inputText = ""
        isLoading = true
        resetStreamingState()

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

                let apiMessages = buildAPIMessages()

                // Smart context assembly — two-stage retrieval replaces brute-force dump
                let focusedNote: Note? = {
                    if let autoPage = autoCreatedPage { return autoPage }
                    if let pageId = selectedPageId {
                        return pages.first(where: { $0.id == pageId })
                    }
                    return nil
                }()

                // Use editable content for selected handles (may have unsaved changes)
                let handlesWithEditableContent = currentHandles.map { handle -> Handle in
                    if handle.id == editingHandleId {
                        var copy = handle
                        copy.content = editableContent
                        return copy
                    }
                    return handle
                }

                // Build version history summaries from cached commits
                let versionHistory: [VersionSummary] = pageCommits.prefix(5).compactMap { commit in
                    guard let content = try? appState.commitModule.getCommitContent(hash: commit.hash) else { return nil }
                    let formatter = RelativeDateTimeFormatter()
                    formatter.unitsStyle = .short
                    let relTime = formatter.localizedString(for: Date(timeIntervalSince1970: Double(commit.createdAt) / 1000), relativeTo: Date())
                    let bodyPreview = String(ContextAssembler.cleanContentForAI(content.note.body, truncate: true).prefix(200))
                    let sectionPreviews: [String] = content.sections
                        .filter { $0.contentType != "image" && $0.contentType != "audio" }
                        .prefix(5).compactMap { section in
                        let text = ContextAssembler.cleanContentForAI(section.content, truncate: true)
                        guard !text.isEmpty else { return nil }
                        return "  - \(text.prefix(150))"
                    }
                    return VersionSummary(
                        name: commit.name ?? commit.shortId,
                        relativeTime: relTime,
                        bodyPreview: bodyPreview,
                        sectionPreviews: sectionPreviews
                    )
                }

                let context: String
                if isProjectWideMode, let moduleId = selectedModuleId {
                    // Project-wide mode: include full project context (all pages in module)
                    context = await appState.contextAssembler.assembleProjectContext(
                        query: text,
                        moduleId: moduleId,
                        selectedHandles: handlesWithEditableContent
                    )
                } else {
                    context = await appState.contextAssembler.assembleContext(
                        query: text,
                        focusedNote: focusedNote,
                        focusedSections: cachedPageSections,
                        selectedHandles: handlesWithEditableContent,
                        focusedSectionId: focusedSectionId,
                        versionHistory: versionHistory
                    )
                }

                switch currentMode {
                case .edit:
                    var finalText: String = ""
                    var streamedActions: [SuggestedAction] = []

                    let stream = ClaudeService.sendWithToolsStream(
                        messages: apiMessages,
                        noteContext: context
                    )
                    for try await event in stream {
                        switch event {
                        case .partialText(let t):
                            await MainActor.run { streamingText = t }
                        case .partialTool(let name, let partial):
                            await MainActor.run {
                                streamingToolName = name
                                streamingToolPartialJSON = partial
                            }
                        case .toolComplete(let action):
                            streamedActions.append(action)
                            await MainActor.run {
                                streamingCompletedActions.append(action)
                                streamingToolName = nil
                                streamingToolPartialJSON = ""
                            }
                        case .done(let text, let actions):
                            finalText = text
                            if streamedActions.isEmpty { streamedActions = actions }
                        }
                    }

                    let finalActions = coalesceMicroActions(streamedActions)

                    let content: String
                    if !finalText.isEmpty {
                        content = finalText
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
                    resetStreamingState()

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
                resetStreamingState()
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
                interstitialContent: [:],
                summary: summary,
                pagePreview: pagePreview
            ))
        )

        return [rewriteAction] + otherActions
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

        // Flip status before spawning the Task so a rapid second click is rejected
        // by the `status == .pending` guard. On failure we revert to .failed below.
        messages[messageIndex].actions[actionIndex] = action.withStatus(.accepted)

        Task {
            do {
                try await action.execute(appState: appState)

                // Fetch fresh data from DB BEFORE any state mutations so we can
                // batch all @State changes in a single synchronous block.
                // Spreading mutations across async boundaries causes multiple
                // layout passes that freeze the ScrollView.
                var freshSections: [Section]?
                var freshNote: Note?
                let needsRefresh: Bool
                if let pageId = selectedPageId {
                    switch action.actionType {
                    case .deleteSection, .updateSectionContent, .addSection, .moveSection,
                         .setSectionIntent, .setNoteIntent:
                        needsRefresh = true
                    case .updatePageBody(let p) where p.noteId == pageId:
                        needsRefresh = true
                    case .updateInterstitialContent(let p) where p.noteId == pageId:
                        needsRefresh = true
                    case .rewritePage(let p) where p.noteId == pageId:
                        needsRefresh = true
                    default:
                        needsRefresh = false
                    }
                    if needsRefresh {
                        freshSections = try? await appState.sectionRepository.getSections(noteId: pageId)
                        freshNote = try? await appState.noteRepository.getNote(id: pageId)
                    }
                } else {
                    needsRefresh = false
                }

                // Batch ALL state mutations in one synchronous block so SwiftUI
                // coalesces them into a single layout pass (prevents freeze).
                if case .updateLoopContent(let p) = action.actionType,
                   p.handleId == editingHandleId {
                    editableContent = p.newContent
                    contentHasUnsavedChanges = false
                }
                if let sections = freshSections {
                    cachedPageSections = sections
                    var contents: [String: String] = [:]
                    for section in sections where section.deletedAt == nil {
                        contents[section.id] = section.content
                    }
                    editableSectionContents = contents
                }
                if let note = freshNote {
                    editableTitle = note.displayTitle(sections: cachedPageSections)
                    editableBody = note.body
                }
                isHistoryExpanded = true

                // Auto-commit the change so it appears in page history
                if let pageId = selectedPageId {
                    autoCommitAction(action, noteId: pageId)

                    // Incremental reindex so next AI turn has fresh context
                    Task {
                        if let note = try? await appState.noteRepository.getNote(id: pageId),
                           let sections = try? await appState.sectionRepository.getSections(noteId: pageId) {
                            await appState.noteIndexRepository.reindexIfNeeded(note: note, sections: sections)
                        }
                    }
                }

                haptic(.success)
            } catch {
                messages[messageIndex].actions[actionIndex] = action.withStatus(.failed(error.localizedDescription))
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
/// Re-posts a plain Return event so the TextField handles the newline
/// natively (proper grow *and* shrink on delete).
struct WorkspaceInputKeyHandler: NSViewRepresentable {
    @Binding var inputText: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Return key = keyCode 36
            if event.keyCode == 36, event.modifierFlags.contains(.shift) {
                // Forge an Option+Return so TextField(axis: .vertical)
                // inserts a newline instead of triggering .onSubmit
                if let newEvent = NSEvent.keyEvent(
                    with: event.type,
                    location: event.locationInWindow,
                    modifierFlags: [.option],
                    timestamp: event.timestamp,
                    windowNumber: event.windowNumber,
                    context: nil,
                    characters: "\n",
                    charactersIgnoringModifiers: "\n",
                    isARepeat: event.isARepeat,
                    keyCode: event.keyCode
                ) {
                    return newEvent
                }
                return nil
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
