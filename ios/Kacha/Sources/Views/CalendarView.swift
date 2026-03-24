import SwiftUI
import SwiftData

struct CalendarView: View {
    @Query private var bookings: [Booking]
    @State private var displayMonth: Date = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDay: Date? = nil

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        calendarHeader
                        weekdayRow
                        calendarGrid
                        Divider().background(Color.kachaCardBorder).padding(.horizontal, 16)
                        monthBookingsList
                        Spacer(minLength: 40)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("カレンダー")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.kachaBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Header

    private var calendarHeader: some View {
        HStack {
            Button {
                displayMonth = calendar.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
                selectedDay = nil
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3).bold()
                    .foregroundColor(.kacha)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Text(monthTitle(displayMonth))
                .font(.title2).bold()
                .foregroundColor(.white)

            Spacer()

            Button {
                displayMonth = calendar.date(byAdding: .month, value: 1, to: displayMonth) ?? displayMonth
                selectedDay = nil
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3).bold()
                    .foregroundColor(.kacha)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 16)
    }

    private var weekdayRow: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, sym in
                Text(sym)
                    .font(.caption2).bold()
                    .foregroundColor(index == 0 ? .kachaDanger : index == 6 ? .kachaAccent : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Grid

    private var calendarGrid: some View {
        let days = daysInMonth(displayMonth)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.self) { day in
                if let day = day {
                    DayCell(
                        day: day,
                        state: dayState(for: day),
                        isSelected: selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
                    )
                    .onTapGesture {
                        selectedDay = calendar.isDate(day, inSameDayAs: selectedDay ?? Date.distantPast) ? nil : day
                    }
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Month Bookings List

    private var monthBookingsList: some View {
        let monthBookings = bookingsForMonth(displayMonth)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(.kacha)
                Text(selectedDay != nil ? selectedDayTitle : "\(monthTitle(displayMonth))の予約")
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
                Spacer()
                Text("\(displayedBookings.count)件")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)

            if displayedBookings.isEmpty {
                Text("予約はありません")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(displayedBookings) { booking in
                    NavigationLink(destination: BookingDetailView(booking: booking)) {
                        CalendarBookingRow(booking: booking)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var selectedDayTitle: String {
        guard let day = selectedDay else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ja_JP")
        fmt.dateFormat = "M月d日(EEE)"
        return fmt.string(from: day)
    }

    private var displayedBookings: [Booking] {
        if let day = selectedDay {
            return bookings.filter { isBookingOnDay($0, day: day) }
                .sorted { $0.checkIn < $1.checkIn }
        }
        return bookingsForMonth(displayMonth)
    }

    // MARK: - Helpers

    private func monthTitle(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ja_JP")
        fmt.dateFormat = "yyyy年M月"
        return fmt.string(from: date)
    }

    private func daysInMonth(_ month: Date) -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }

        let weekday = (calendar.component(.weekday, from: firstDay) - 1 + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: weekday)

        for day in range {
            if let d = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(d)
            }
        }
        // Pad to complete weeks
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }

    enum DayState {
        case empty, booked, checkIn, checkOut, multiEvent
    }

    private func dayState(for day: Date) -> DayState {
        let checkIns = bookings.filter { calendar.isDate($0.checkIn, inSameDayAs: day) && $0.status != "cancelled" }
        let checkOuts = bookings.filter { calendar.isDate($0.checkOut, inSameDayAs: day) && $0.status != "cancelled" }
        let occupied = bookings.filter { isBookingOccupying(day: day, booking: $0) }

        if !checkIns.isEmpty && !checkOuts.isEmpty { return .multiEvent }
        if !checkIns.isEmpty { return .checkIn }
        if !checkOuts.isEmpty { return .checkOut }
        if !occupied.isEmpty { return .booked }
        return .empty
    }

    private func isBookingOnDay(_ booking: Booking, day: Date) -> Bool {
        let start = calendar.startOfDay(for: booking.checkIn)
        let end = calendar.startOfDay(for: booking.checkOut)
        let d = calendar.startOfDay(for: day)
        return d >= start && d <= end && booking.status != "cancelled"
    }

    private func isBookingOccupying(day: Date, booking: Booking) -> Bool {
        guard booking.status != "cancelled" else { return false }
        let start = calendar.startOfDay(for: booking.checkIn)
        let end = calendar.startOfDay(for: booking.checkOut)
        let d = calendar.startOfDay(for: day)
        return d > start && d < end
    }

    private func bookingsForMonth(_ month: Date) -> [Booking] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let lastDay = calendar.date(byAdding: .day, value: range.count - 1, to: firstDay)
        else { return [] }

        let monthStart = calendar.startOfDay(for: firstDay)
        let monthEnd = calendar.startOfDay(for: lastDay)

        return bookings.filter { booking in
            guard booking.status != "cancelled" else { return false }
            let checkIn = calendar.startOfDay(for: booking.checkIn)
            let checkOut = calendar.startOfDay(for: booking.checkOut)
            return checkOut >= monthStart && checkIn <= monthEnd
        }.sorted { $0.checkIn < $1.checkIn }
    }
}

// MARK: - Day Cell

struct DayCell: View {
    let day: Date
    let state: CalendarView.DayState
    let isSelected: Bool

    private let calendar = Calendar.current

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.kacha : cellBgColor)

            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .black : textColor)

                if state != .empty {
                    Circle()
                        .fill(isSelected ? Color.black.opacity(0.5) : dotColor)
                        .frame(width: 5, height: 5)
                } else {
                    Spacer().frame(height: 5)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(height: 44)
    }

    private var cellBgColor: Color {
        switch state {
        case .empty: return Color.clear
        case .booked: return Color.kachaWarn.opacity(0.18)
        case .checkIn: return Color.kachaSuccess.opacity(0.20)
        case .checkOut: return Color.kachaAccent.opacity(0.20)
        case .multiEvent: return Color.kacha.opacity(0.15)
        }
    }

    private var textColor: Color {
        if calendar.isDateInToday(day) { return .kacha }
        let weekday = calendar.component(.weekday, from: day)
        if weekday == 1 { return .kachaDanger }
        if weekday == 7 { return .kachaAccent }
        return .white
    }

    private var dotColor: Color {
        switch state {
        case .booked: return .kachaWarn
        case .checkIn: return .kachaSuccess
        case .checkOut: return .kachaAccent
        case .multiEvent: return .kacha
        case .empty: return .clear
        }
    }
}

// MARK: - Calendar Booking Row

struct CalendarBookingRow: View {
    let booking: Booking

    var body: some View {
        KachaCard {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: booking.platformColor))
                    .frame(width: 4, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(booking.guestName)
                        .font(.subheadline).bold()
                        .foregroundColor(.white)
                    Text("\(booking.checkIn.formatted(date: .abbreviated, time: .omitted)) → \(booking.checkOut.formatted(date: .abbreviated, time: .omitted))  \(booking.nights)泊")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(booking.platformLabel)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(hex: booking.platformColor).opacity(0.2))
                        .foregroundColor(Color(hex: booking.platformColor))
                        .clipShape(Capsule())

                    Text(booking.statusLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
        }
    }
}

// MARK: - Calendar extension

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}
