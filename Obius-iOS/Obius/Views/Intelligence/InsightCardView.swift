import SwiftUI

// MARK: - Category Card (Summary for one insight category)

struct CategoryCardView: View {
    let insightType: InsightType
    let insights: [Insight]
    let onTap: () -> Void

    private var summaryLine: String {
        var counts: [String: Int] = [:]
        for insight in insights {
            counts[insight.displayLabel, default: 0] += 1
        }
        return counts.sorted { $0.key < $1.key }
            .map { "\($0.value) \($0.key.lowercased())" }
            .joined(separator: " · ")
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(insightType.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    if !summaryLine.isEmpty {
                        Text(summaryLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text("\(insights.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Insight Row (for use in CategoryDetailSheet)

struct InsightRowView: View {
    let insight: Insight
    let onTrack: () -> Void
    let onDismiss: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !insight.body.isEmpty {
                    Text(insight.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 16) {
                Button {
                    onTrack()
                } label: {
                    Image(systemName: "star")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Category Detail Sheet

/// Full-screen sheet listing individual insights within a single category.
struct CategoryDetailSheet: View {
    let insightType: InsightType
    let insights: [Insight]
    let onTrack: (Insight) -> Void
    let onDismiss: (Insight) -> Void
    let onSelectInsight: (Insight) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(insights) { insight in
                        InsightRowView(
                            insight: insight,
                            onTrack: { onTrack(insight) },
                            onDismiss: { onDismiss(insight) },
                            onTap: { onSelectInsight(insight) }
                        )
                        .padding(.horizontal)

                        if insight.id != insights.last?.id {
                            Divider()
                                .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(insightType.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Tracked Insight Card (Compact, horizontal scroll)

struct TrackedInsightChip: View {
    let insight: Insight
    let onTap: () -> Void
    let onUntrack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !insight.body.isEmpty {
                    Text(insight.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 16) {
                Button {
                    onUntrack()
                } label: {
                    Image(systemName: "star.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    onUntrack()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Echo Card (Compact, horizontal scroll)

struct UpcomingEchoCard: View {
    let insight: Insight
    let onTap: () -> Void
    let onLongPress: () -> Void

    private var isFiring: Bool {
        insight.body == "Firing now"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Type badge
            HStack(spacing: 4) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 9))
                Text(isFiring ? "Firing" : "Echo")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.orange)

            // Title
            Text(insight.title.replacingOccurrences(of: "Echo: ", with: ""))
                .font(.caption.weight(.medium))
                .lineLimit(2)

            // Body preview
            Text(insight.body.isEmpty ? " " : insight.body)
                .font(.system(size: 11))
                .foregroundStyle(isFiring ? .orange : .secondary)
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .frame(width: 130, height: 50, alignment: .topLeading)
        .padding(5)
        .background(Color(UIColor.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            if isFiring {
                FiringEchoOutline()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture { onLongPress() }
    }
}

/// Separate view so SwiftUI destroys animation state when removed.
private struct FiringEchoOutline: View {
    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(Color.orange, lineWidth: 2)
            .opacity(isAnimating ? 1 : 0.2)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}

// MARK: - Insight Reference

struct InsightReference: Identifiable {
    var id: String { noteId + (sectionId ?? "") }
    let noteId: String
    let title: String
    let sectionId: String?
}

// MARK: - Insight Detail Sheet

struct InsightDetailSheet: View {
    let insight: Insight
    let onTrack: (() -> Void)?
    let onDismiss: (() -> Void)?
    let onUntrack: (() -> Void)?
    var onDeleteNote: (() -> Void)? = nil
    var references: [InsightReference] = []
    var onNavigate: ((InsightReference) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showCreateEcho = false
    @State private var echoCreated = false

    private var isEchoSuggestion: Bool {
        insight.insightType == .reminder && insight.sourceSectionId == "suggested_echo"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Type badge
                    HStack(spacing: 6) {
                        Image(systemName: insight.displayIcon)
                            .font(.subheadline)
                        Text(insight.displayLabel)
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(insight.displayTint.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(insight.displayTint.color.opacity(0.15))
                    .clipShape(Capsule())

                    // Title
                    Text(insight.title)
                        .font(.title3.weight(.semibold))

                    // Body
                    if !insight.body.isEmpty {
                        Text(insight.body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    // Timestamp
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    // References
                    if !references.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("REFERENCED")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(references) { ref in
                                Button {
                                    onNavigate?(ref)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "doc.text")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text(ref.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }

                    // Create Echo button for echo suggestions
                    if isEchoSuggestion {
                        Button {
                            showCreateEcho = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bell.badge")
                                Text("Create Echo")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    Divider()

                    // Actions
                    if insight.status == .surfaced {
                        HStack(spacing: 12) {
                            Button {
                                onTrack?()
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "star")
                                    Text("Track")
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(insight.displayTint.color)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(insight.displayTint.color.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            Button {
                                onDismiss?()
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark")
                                    Text("Dismiss")
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    } else if insight.status == .tracked {
                        HStack(spacing: 12) {
                            Button {
                                onUntrack?()
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "star.slash")
                                    Text("Untrack")
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            Button {
                                onDismiss?()
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark")
                                    Text("Dismiss")
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }

                    // Delete page button for nonsense cleanup insights
                    if insight.insightType == .cleanup && insight.sourceSectionId == "nonsense",
                       let onDeleteNote {
                        Button(role: .destructive) {
                            onDeleteNote()
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("Delete Page")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .sheet(isPresented: $showCreateEcho) {
            CreateEchoFromInsightSheet(insight: insight) {
                echoCreated = true
            }
        }
        .onChange(of: showCreateEcho) { _, isPresented in
            if !isPresented && echoCreated {
                onTrack?()
                dismiss()
            }
        }
    }

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: Double(insight.createdAt) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Create Echo From Insight

struct CreateEchoFromInsightSheet: View {
    let insight: Insight
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var useExistingHandle: Bool
    @State private var selectedHandleId: String?
    @State private var newHandleName: String
    @State private var startDate: Date
    @State private var isRecurring: Bool
    @State private var intervals: [EchoInterval]
    @State private var isCreating = false

    private var handles: [Handle] {
        HandleManager.shared.handles
    }

    private var trimmedHandleName: String {
        newHandleName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        if useExistingHandle {
            return selectedHandleId != nil
        } else {
            return trimmedHandleName.count >= 2
        }
    }

    init(insight: Insight, onCreated: @escaping () -> Void) {
        self.insight = insight
        self.onCreated = onCreated

        let allHandles = HandleManager.shared.handles

        // Defaults
        var initUseExisting = !allHandles.isEmpty
        var initHandleId: String?
        var initHandleName = ""
        var initDate = Date().addingTimeInterval(3600)
        var initRecurring = false
        var initIntervals = [EchoInterval(value: 1, unit: .days)]

        // Pre-fill from AI suggestion config stored in relatedNoteId
        if insight.insightType == .reminder && insight.sourceSectionId == "suggested_echo",
           let json = insight.relatedNoteId,
           let data = json.data(using: .utf8) {
            do {
                let s = try JSONDecoder().decode(ClaudeService.TemporalEchoSuggestion.self, from: data)
                print("[EchoFromInsight] Decoded suggestion — handle: \(s.handleName), date: \(s.fireDateISO), recurring: \(s.isRecurring)")

                // Handle
                let existsInHandles = s.handleId != "new" && s.handleId != "none"
                    && allHandles.contains(where: { $0.id == s.handleId })
                if existsInHandles {
                    initUseExisting = true
                    initHandleId = s.handleId
                } else {
                    initUseExisting = false
                    initHandleName = s.handleName
                }

                // Fire date
                if let date = Self.parseISO8601(s.fireDateISO) {
                    initDate = max(date, Date().addingTimeInterval(60))
                    print("[EchoFromInsight] Parsed date: \(initDate)")
                } else {
                    print("[EchoFromInsight] Failed to parse date: \(s.fireDateISO)")
                }

                // Recurrence
                initRecurring = s.isRecurring
                if s.isRecurring, let unit = EchoIntervalUnit(rawValue: s.intervalUnit) {
                    initIntervals = [EchoInterval(value: max(1, s.intervalValue), unit: unit)]
                }
            } catch {
                print("[EchoFromInsight] JSON decode failed: \(error)\nRaw: \(json)")
            }
        }

        _useExistingHandle = State(initialValue: initUseExisting)
        _selectedHandleId = State(initialValue: initHandleId)
        _newHandleName = State(initialValue: initHandleName)
        _startDate = State(initialValue: initDate)
        _isRecurring = State(initialValue: initRecurring)
        _intervals = State(initialValue: initIntervals)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Context from the AI suggestion
                SwiftUI.Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(insight.title)
                            .font(.subheadline.weight(.medium))
                        if !insight.body.isEmpty {
                            Text(insight.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Handle
                SwiftUI.Section("Loop") {
                    if !handles.isEmpty {
                        Picker("", selection: $useExistingHandle) {
                            Text("Existing").tag(true)
                            Text("New").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .listRowSeparator(.hidden)
                    }

                    if useExistingHandle && !handles.isEmpty {
                        Picker("Loop", selection: $selectedHandleId) {
                            Text("Select a loop...").tag(nil as String?)
                            ForEach(handles) { handle in
                                Text("@\(handle.displayName)").tag(handle.id as String?)
                            }
                        }
                    } else {
                        TextField("Loop name", text: $newHandleName)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if !trimmedHandleName.isEmpty && trimmedHandleName.count < 2 {
                            Text("Name must be at least 2 characters")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                // Schedule
                SwiftUI.Section("Schedule") {
                    DatePicker(
                        "Fire Date",
                        selection: $startDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    Toggle("Recurring", isOn: $isRecurring)

                    if isRecurring {
                        ForEach($intervals) { $interval in
                            HStack {
                                Text("Every")
                                    .font(.subheadline)
                                Stepper(value: $interval.value, in: 1...999) {
                                    Text("\(interval.value)")
                                        .font(.title3.monospacedDigit().weight(.semibold))
                                        .frame(minWidth: 32)
                                }
                                Picker("Unit", selection: $interval.unit) {
                                    ForEach(EchoIntervalUnit.allCases, id: \.self) { unit in
                                        Text(interval.value == 1 ? unit.singularName : unit.displayName)
                                            .tag(unit)
                                    }
                                }
                                .labelsHidden()
                            }
                        }

                        if intervals.count < 5 {
                            Button {
                                withAnimation {
                                    intervals.append(EchoInterval(value: 1, unit: .hours))
                                }
                            } label: {
                                Label("Add Cadence", systemImage: "plus.circle.fill")
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Create Echo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createEcho() }
                        .fontWeight(.semibold)
                        .disabled(!canCreate || isCreating)
                }
            }
        }
        .presentationDetents([.large])
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }

        formatter.formatOptions = [.withFullDate]
        if let date = formatter.date(from: string) { return date }

        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = TimeZone.current
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            fallback.dateFormat = fmt
            if let date = fallback.date(from: string) { return date }
        }

        return nil
    }

    private func createEcho() {
        isCreating = true
        Task {
            do {
                let handleId: String
                if useExistingHandle, let existing = selectedHandleId {
                    handleId = existing
                } else {
                    let handle = try await HandleManager.shared.createHandle(name: trimmedHandleName)
                    handleId = handle.id
                }
                _ = try await EchoManager.shared.createEcho(
                    handleId: handleId,
                    isRecurring: isRecurring,
                    intervals: isRecurring ? intervals : [],
                    fireDate: startDate
                )
                onCreated()
                dismiss()
            } catch {
                isCreating = false
            }
        }
    }
}

// MARK: - Create Insight Sheet

struct CreateInsightSheet: View {
    let onCreate: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section("Title") {
                    TextField("What are you tracking?", text: $title)
                }

                SwiftUI.Section("Details") {
                    TextField("Add details...", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        onCreate(title, details)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
