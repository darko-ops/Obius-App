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
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(echoManager.getHandleName(for: echo))")
                        .font(.subheadline.weight(.medium))

                    Text(echo.cadenceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !echo.isRecurring && echo.fireDateAsDate <= Date() {
                    Text("Complete")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else if let nextDate = echo.computedNextFireDate {
                    Text(nextDate, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if echo.isAlerted {
                Button {
                    Task {
                        try? await echoManager.completeEcho(id: echo.id)
                        HapticFeedback.notification(.success)
                    }
                } label: {
                    Label("Complete", systemImage: "checkmark.circle")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color.yellow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            if echo.isAlerted {
                EchoAlertGlow()
            }
        }
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

    var body: some View {
        NavigationStack {
            List {
                ForEach(echoManager.activeEchoes) { echo in
                    EchoRowView(echo: echo)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(echo)
                        }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Echoes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if echoManager.activeEchoes.isEmpty {
                    ContentUnavailableView {
                        Label("No Echoes", systemImage: "dot.radiowaves.left.and.right")
                    } description: {
                        Text("Active echoes will appear here")
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}
