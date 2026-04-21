import SwiftUI

struct EchoCalendarView: View {
    @StateObject private var echoManager = EchoManager.shared
    @ObservedObject var calendarMemoRepository: CalendarMemoRepository

    enum CalendarMode: String {
        case month = "Month"
        case week = "Week"
    }

    @State private var mode: CalendarMode = .month
    @State private var displayedMonth: Date = {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }()
    @State private var selectedDate: Date?
    @State private var editingMemo: String = ""
    @State private var displayedWeekStart: Date = {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: Date()) else { return Date() }
        return interval.start
    }()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private let weekdaySymbols = Calendar.current.veryShortWeekdaySymbols

    // MARK: - Memo Storage

    private var memos: [String: String] {
        calendarMemoRepository.memos
    }

    private func saveMemo(_ text: String, for date: Date) {
        let key = dayKey(date)
        Task { await calendarMemoRepository.saveMemo(text, for: key) }
    }

    // MARK: - Computed

    private var visibleRange: (start: Date, end: Date) {
        let cal = Calendar.current
        if mode == .month {
            let start = displayedMonth
            let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
            return (start, end)
        } else {
            let end = cal.date(byAdding: .day, value: 7, to: displayedWeekStart) ?? displayedWeekStart
            return (displayedWeekStart, end)
        }
    }

    private var echoDays: Set<String> {
        let cal = Calendar.current
        let range = visibleRange
        var days = Set<String>()
        for echo in echoManager.activeEchoes {
            for date in echo.fireDatesInRange(start: range.start, end: range.end) {
                let comps = cal.dateComponents([.year, .month, .day], from: date)
                days.insert("\(comps.year!)-\(comps.month!)-\(comps.day!)")
            }
        }
        return days
    }

    private func dayKey(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(comps.year!)-\(comps.month!)-\(comps.day!)"
    }

    private func echoHandleNames(for date: Date) -> [String] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        var names: [String] = []
        var seen = Set<String>()
        for echo in echoManager.activeEchoes {
            if !echo.fireDatesInRange(start: dayStart, end: dayEnd).isEmpty, !seen.contains(echo.id) {
                seen.insert(echo.id)
                names.append(echoManager.getHandleName(for: echo))
            }
        }
        return names
    }

    private var selectedDayEchoes: [(echo: Echo, fireDate: Date)] {
        guard let selected = selectedDate else { return [] }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: selected)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        var results: [(Echo, Date)] = []
        for echo in echoManager.activeEchoes {
            let dates = echo.fireDatesInRange(start: dayStart, end: dayEnd)
            for d in dates {
                results.append((echo, d))
            }
        }
        return results.sorted { $0.1 < $1.1 }
    }

    // MARK: - Month Grid

    private var weeksInMonth: [[Date?]] {
        let cal = Calendar.current
        let firstOfMonth = displayedMonth
        guard let monthRange = cal.range(of: .day, in: .month, for: firstOfMonth) else { return [] }

        let firstWeekday = cal.component(.weekday, from: firstOfMonth)
        let leadingBlanks = firstWeekday - cal.firstWeekday
        let adjusted = (leadingBlanks + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: adjusted)

        for day in monthRange {
            if let date = cal.date(bySetting: .day, value: day, of: firstOfMonth) {
                cells.append(date)
            }
        }

        while cells.count % 7 != 0 {
            cells.append(nil)
        }

        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0+7, cells.count)]) }
    }

    private var currentWeekDates: [Date] {
        let cal = Calendar.current
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: displayedWeekStart) }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow

            navRow

            weekdayHeaders

            if mode == .month {
                monthGrid
            } else {
                weekRow
            }

            dayDetail
        }
        .padding(12)
        .background(Color(red: 0.06, green: 0.06, blue: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack {
            Text("CALENDAR")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mode = .month
                        selectedDate = nil
                    }
                } label: {
                    Text("Month")
                        .font(.caption2)
                        .foregroundColor(mode == .month ? .white : Color.gray)
                }
                .buttonStyle(.plain)

                Text(" / ")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mode = .week
                        selectedDate = nil
                    }
                } label: {
                    Text("Week")
                        .font(.caption2)
                        .foregroundColor(mode == .week ? .white : Color.gray)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var navRow: some View {
        HStack(spacing: 12) {
            Button {
                navigate(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if mode == .month {
                Text(displayedMonth, format: .dateTime.month(.wide).year())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: displayedWeekStart) ?? displayedWeekStart
                Text("\(displayedWeekStart, format: .dateTime.month(.abbreviated).day()) – \(weekEnd, format: .dateTime.month(.abbreviated).day())")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Button {
                navigate(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            if !isShowingCurrentPeriod {
                Button {
                    returnToToday()
                } label: {
                    Text("Today")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.yellow)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var isShowingCurrentPeriod: Bool {
        let cal = Calendar.current
        if mode == .month {
            return cal.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
        } else {
            guard let currentWeekInterval = cal.dateInterval(of: .weekOfYear, for: Date()) else { return false }
            return cal.isDate(displayedWeekStart, inSameDayAs: currentWeekInterval.start)
        }
    }

    private func returnToToday() {
        withAnimation(.easeInOut(duration: 0.2)) {
            let cal = Calendar.current
            if mode == .month {
                displayedMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
            } else {
                guard let interval = cal.dateInterval(of: .weekOfYear, for: Date()) else { return }
                displayedWeekStart = interval.start
            }
            selectedDate = Date()
            editingMemo = memos[dayKey(Date())] ?? ""
        }
    }

    private var weekdayHeaders: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(height: 16)
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(weeksInMonth.joined().enumerated()), id: \.offset) { _, date in
                if let date = date {
                    dayCell(date)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.clear)
                        .frame(height: 64)
                }
            }
        }
    }

    private var weekRow: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(currentWeekDates, id: \.timeIntervalSince1970) { date in
                dayCell(date)
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(date)
        let isSelected = selectedDate.map { cal.isDate($0, inSameDayAs: date) } ?? false
        let dayNum = cal.component(.day, from: date)
        let memo = memos[dayKey(date)]
        let hasMemo = memo != nil && !memo!.isEmpty
        let handles = echoHandleNames(for: date)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected {
                    selectedDate = nil
                } else {
                    selectedDate = date
                    editingMemo = memos[dayKey(date)] ?? ""
                }
            }
        } label: {
            VStack(spacing: 1) {
                // Day number
                Text("\(dayNum)")
                    .font(.system(size: 10, weight: isToday ? .bold : .regular))
                    .foregroundColor(isSelected ? .yellow : isToday ? .blue : .blue.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                    .padding(.top, 3)

                // Echo handle bubbles
                if !handles.isEmpty {
                    VStack(spacing: 1) {
                        ForEach(handles.prefix(mode == .week ? 4 : 2), id: \.self) { name in
                            Text("@\(name)")
                                .font(.system(size: 6))
                                .foregroundColor(.yellow)
                                .lineLimit(1)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Color.yellow.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 2)
                }

                // Memo preview
                if hasMemo {
                    Text(memo!)
                        .font(.system(size: 7))
                        .foregroundColor(.white)
                        .lineLimit(mode == .week ? 6 : 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 3)
                }

                Spacer(minLength: 0)
            }
            .frame(height: mode == .week ? 120 : 64)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.yellow.opacity(0.1) : Color(white: 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        isSelected ? Color.yellow.opacity(0.4) :
                        isToday ? Color(white: 0.15) :
                        Color(white: 0.08),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var dayDetail: some View {
        if let selected = selectedDate {
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                    .padding(.top, 4)

                // Date label
                Text(selected, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                // Memo editor
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.35))
                        .padding(.top, 6)

                    ZStack(alignment: .topLeading) {
                        if editingMemo.isEmpty {
                            Text("Add a note...")
                                .font(.system(size: 12))
                                .foregroundColor(Color(white: 0.25))
                                .padding(.top, 1)
                        }
                        TextEditor(text: $editingMemo)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 20, maxHeight: 80)
                            .fixedSize(horizontal: false, vertical: true)
                            #if os(iOS)
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button {
                                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    } label: {
                                        Image(systemName: "keyboard.chevron.compact.down")
                                    }
                                }
                            }
                            #endif
                            .onChange(of: editingMemo) { _, newValue in
                                saveMemo(newValue, for: selected)
                            }
                    }
                }
                .padding(8)
                .background(Color(white: 0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Echoes for this day
                let echoes = selectedDayEchoes
                if !echoes.isEmpty {
                    ForEach(Array(echoes.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(.yellow)
                                    .frame(width: 5, height: 5)

                                Text("@\(echoManager.getHandleName(for: item.echo))")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Spacer()

                                Text(item.fireDate, format: .dateTime.hour().minute())
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            // Echo content
                            if let handle = HandleManager.shared.getHandle(id: item.echo.handleId),
                               !handle.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(handle.content)
                                    .font(.caption2)
                                    .foregroundColor(Color(white: 0.5))
                                    .lineLimit(3)
                                    .padding(.leading, 13)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func navigate(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            let cal = Calendar.current
            if mode == .month {
                if let next = cal.date(byAdding: .month, value: delta, to: displayedMonth) {
                    displayedMonth = next
                    selectedDate = nil
                }
            } else {
                if let next = cal.date(byAdding: .weekOfYear, value: delta, to: displayedWeekStart) {
                    displayedWeekStart = next
                    selectedDate = nil
                }
            }
        }
    }
}

#Preview {
    EchoCalendarView(calendarMemoRepository: CalendarMemoRepository(database: try! DatabaseManager()))
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}
