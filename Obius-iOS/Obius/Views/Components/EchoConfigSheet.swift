import SwiftUI

// MARK: - Echo Config Sheet

struct EchoConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var config: EchoConfig?

    @State private var startDate: Date
    @State private var isRecurring: Bool
    @State private var intervals: [EchoInterval]
    @State private var minimumDate: Date

    init(config: Binding<EchoConfig?>) {
        _config = config
        let now = Date()
        _minimumDate = State(initialValue: now)
        if let existing = config.wrappedValue {
            _startDate = State(initialValue: existing.startDate)
            _isRecurring = State(initialValue: existing.isRecurring)
            _intervals = State(initialValue: existing.intervals)
        } else {
            _startDate = State(initialValue: now.addingTimeInterval(300))
            _isRecurring = State(initialValue: false)
            _intervals = State(initialValue: [EchoInterval(value: 1, unit: .days)])
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Start Date
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Start Date")
                            .font(.headline)
                            .padding(.horizontal)

                        DatePicker(
                            "Start Date",
                            selection: $startDate,
                            in: minimumDate...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(.horizontal)
                    }

                    Divider()
                        .padding(.horizontal)

                    // Recurring toggle
                    Toggle("Recurring", isOn: $isRecurring)
                        .font(.headline)
                        .padding(.horizontal)

                    // Cadence list (visible when recurring)
                    if isRecurring {
                        VStack(spacing: 12) {
                            ForEach($intervals) { $interval in
                                intervalRow(interval: $interval)
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
                                .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Preview text
                    Text(previewText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, 4)

                    Spacer(minLength: 20)
                }
                .padding(.top)
            }
            .navigationTitle("Configure Echo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Remove") {
                        config = nil
                        dismiss()
                    }
                    .foregroundStyle(.red)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        config = EchoConfig(
                            startDate: startDate,
                            isRecurring: isRecurring,
                            intervals: intervals
                        )
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func intervalRow(interval: Binding<EchoInterval>) -> some View {
        HStack(spacing: 8) {
            Text("Every")
                .font(.subheadline)

            Stepper(value: interval.value, in: 1...999) {
                Text("\(interval.wrappedValue.value)")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 32)
            }

            Picker("Unit", selection: interval.unit) {
                ForEach(EchoIntervalUnit.allCases, id: \.self) { unit in
                    Text(interval.wrappedValue.value == 1 ? unit.singularName : unit.displayName)
                        .tag(unit)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            if intervals.count > 1 {
                Button {
                    withAnimation {
                        intervals.removeAll { $0.id == interval.wrappedValue.id }
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var previewText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let dateStr = formatter.string(from: startDate)

        if !isRecurring {
            return "Fires on \(dateStr)"
        }

        let cadences = intervals.map { interval -> String in
            if interval.value == 1 {
                return "every \(interval.unit.singularName.lowercased())"
            }
            return "every \(interval.value) \(interval.unit.displayName.lowercased())"
        }

        return "Starts \(dateStr), repeats \(cadences.joined(separator: " and "))"
    }
}

// MARK: - Echo Row View

struct EchoRowView: View {
    let echo: Echo
    @StateObject private var echoManager = EchoManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 3) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 8))
                    Text("Echo")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.yellow)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Color.yellow.opacity(0.15))
                .clipShape(Capsule())

                Spacer()

                if let nextDate = echo.computedNextFireDate, !echo.isAlerted {
                    Text(nextDate, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Text("@\(echoManager.getHandleName(for: echo))")
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)

            Text(echo.cadenceDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if echo.isAlerted {
                Button {
                    Task {
                        try? await echoManager.completeEcho(id: echo.id)
                        HapticFeedback.notification(.success)
                    }
                } label: {
                    Text("Done")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(Color(red: 0.06, green: 0.06, blue: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(echo.isAlerted ? Color.yellow.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

// Separate view so SwiftUI destroys animation state when removed
private struct EchoAlertGlow: View {
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(Color.yellow, lineWidth: 2)
            .opacity(pulse ? 0.5 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Echo Detail Sheet

struct EchoDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var echoManager = EchoManager.shared
    @StateObject private var handleManager = HandleManager.shared
    let echo: Echo

    @State private var content: String = ""
    @State private var startDate: Date
    @State private var isRecurring: Bool
    @State private var intervals: [EchoInterval]

    private var handle: Handle? {
        handleManager.getHandle(id: echo.handleId)
    }

    init(echo: Echo) {
        self.echo = echo
        _startDate = State(initialValue: echo.fireDateAsDate)
        _isRecurring = State(initialValue: echo.isRecurring)
        _intervals = State(initialValue: echo.intervals.isEmpty ? [EchoInterval(value: 1, unit: .days)] : echo.intervals)
    }

    var body: some View {
        NavigationStack {
            List {
                // Loop content section
                if let handle = handle {
                    SwiftUI.Section {
                        Text(handle.formattedName)
                            .font(.headline)
                            .foregroundStyle(handle.intent.color)

                        TextEditor(text: $content)
                            .frame(minHeight: 80)
                    } header: {
                        Text("Loop Content")
                    }
                }

                // Schedule section
                SwiftUI.Section("Schedule") {
                    DatePicker(
                        "Start Date",
                        selection: $startDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    Toggle("Recurring", isOn: $isRecurring)

                    if isRecurring {
                        ForEach($intervals) { $interval in
                            intervalRow(interval: $interval)
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

                // Status section
                SwiftUI.Section("Status") {
                    if echo.isAlerted {
                        LabeledContent("Status") {
                            Text("Alerted")
                                .foregroundStyle(.yellow)
                        }
                    } else if !echo.isRecurring && echo.fireDateAsDate <= Date() {
                        LabeledContent("Status") {
                            Text("Complete")
                                .foregroundStyle(.green)
                        }
                    }

                    if let nextDate = echo.computedNextFireDate {
                        LabeledContent("Next Fire") {
                            Text(nextDate, style: .relative)
                        }
                    }
                }

                // Complete action
                if echo.isAlerted {
                    SwiftUI.Section {
                        Button {
                            Task {
                                try? await echoManager.completeEcho(id: echo.id)
                                HapticFeedback.notification(.success)
                            }
                            dismiss()
                        } label: {
                            Label("Complete", systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                        }
                    }
                }

                SwiftUI.Section {
                    Button(role: .destructive) {
                        Task {
                            try? await echoManager.deleteEcho(id: echo.id)
                            dismiss()
                        }
                    } label: {
                        Label("Delete Echo", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Echo Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }
            }
            .onAppear {
                content = handle?.content ?? ""
            }
        }
    }

    @ViewBuilder
    private func intervalRow(interval: Binding<EchoInterval>) -> some View {
        HStack(spacing: 8) {
            Text("Every")
                .font(.subheadline)

            Stepper(value: interval.value, in: 1...999) {
                Text("\(interval.wrappedValue.value)")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 32)
            }

            Picker("Unit", selection: interval.unit) {
                ForEach(EchoIntervalUnit.allCases, id: \.self) { unit in
                    Text(interval.wrappedValue.value == 1 ? unit.singularName : unit.displayName)
                        .tag(unit)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            if intervals.count > 1 {
                Button {
                    withAnimation {
                        intervals.removeAll { $0.id == interval.wrappedValue.id }
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func save() {
        Task {
            // Save loop content if changed
            if let handle = handle, content != handle.content {
                try? await handleManager.updateContent(handleId: handle.id, content: content)
            }

            // Save echo schedule
            try? await echoManager.updateEcho(
                id: echo.id,
                isRecurring: isRecurring,
                intervals: isRecurring ? intervals : [],
                fireDate: startDate
            )

            dismiss()
        }
    }
}

// MARK: - Manage Echoes Sheet

struct ManageEchoesSheet: View {
    @ObservedObject var echoManager: EchoManager
    let onSelect: (Echo) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingCreateEcho = false
    @StateObject private var handleManager = HandleManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(echoManager.activeEchoes) { echo in
                        EchoRowView(echo: echo)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(echo)
                            }
                    }
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Echoes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreateEcho = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if echoManager.activeEchoes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)

                        Text("No Echoes")
                            .font(.subheadline.weight(.medium))

                        Text("Create an echo to get reminders")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            showingCreateEcho = true
                        } label: {
                            Text("New Echo")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(red: 0.06, green: 0.06, blue: 0.06))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreateEcho) {
            CreateEchoSheet()
        }
        .presentationDetents([.large])
    }
}

// MARK: - Create Echo Sheet

struct CreateEchoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var handleManager = HandleManager.shared

    @State private var useExistingHandle = true
    @State private var selectedHandleId: String?
    @State private var newHandleName = ""
    @State private var startDate = Date().addingTimeInterval(3600)
    @State private var isRecurring = false
    @State private var intervals = [EchoInterval(value: 1, unit: .days)]
    @State private var isCreating = false

    private var handles: [Handle] { handleManager.handles }

    private var trimmedName: String {
        newHandleName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        if useExistingHandle {
            return selectedHandleId != nil
        } else {
            return trimmedName.count >= 2
        }
    }

    var body: some View {
        NavigationStack {
            Form {
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
                    }
                }

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
                    }
                }
            }
            .navigationTitle("New Echo")
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
        .onAppear {
            if handles.isEmpty { useExistingHandle = false }
        }
    }

    private func createEcho() {
        isCreating = true
        Task {
            do {
                let handleId: String
                if useExistingHandle, let existing = selectedHandleId {
                    handleId = existing
                } else {
                    let handle = try await HandleManager.shared.createHandle(name: trimmedName)
                    handleId = handle.id
                }
                _ = try await EchoManager.shared.createEcho(
                    handleId: handleId,
                    isRecurring: isRecurring,
                    intervals: isRecurring ? intervals : [],
                    fireDate: startDate
                )
                dismiss()
            } catch {
                isCreating = false
            }
        }
    }
}
