import SwiftUI
import SwiftData

// MARK: - CalendarAvailabilityView
// 物件ごとの稼働状況を月カレンダーで可視化。
// 予約済み・ブロック済み・空室を色分けし、稼働率を表示する。

struct CalendarAvailabilityView: View {
    @Query private var bookings: [Booking]
    @Query(sort: \Home.sortOrder) private var homes: [Home]
    @AppStorage("activeHomeId") private var activeHomeId = ""

    @State private var displayMonth: Date = Calendar.current.startOfMonth(for: Date())
    @State private var selectedHomeId: String?

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    private var filteredHomes: [Home] {
        if let id = selectedHomeId {
            return homes.filter { $0.id == id }
        }
        return Array(homes)
    }

    private var activeBookings: [Booking] {
        bookings.filter { $0.status != "cancelled" }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        monthHeader
                        if homes.count > 1 {
                            homeFilter
                        }
                        occupancyStats
                        weekdayRow
                        availabilityGrid
                        legend
                        Spacer(minLength: 40)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("稼働カレンダー")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.kachaBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            Button {
                displayMonth = calendar.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
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
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3).bold()
                    .foregroundColor(.kacha)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Home Filter

    private var homeFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "全物件", isSelected: selectedHomeId == nil) {
                    selectedHomeId = nil
                }
                ForEach(homes) { home in
                    filterChip(label: home.name, isSelected: selectedHomeId == home.id) {
                        selectedHomeId = home.id
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption).bold()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.kacha : Color.kachaCard)
                .foregroundColor(isSelected ? .black : .white)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? Color.kacha : Color.kachaCardBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Occupancy Stats

    private var occupancyStats: some View {
        let days = daysInMonth(displayMonth).compactMap { $0 }
        let totalDays = days.count * max(filteredHomes.count, 1)
        let bookedDays = days.reduce(0) { count, day in
            count + filteredHomes.filter { home in
                dayAvailability(for: day, homeId: home.id) == .fullyBooked
            }.count
        }
        let occupancyRate = totalDays > 0 ? Double(bookedDays) / Double(totalDays) * 100 : 0

        return KachaCard {
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text(String(format: "%.0f%%", occupancyRate))
                        .font(.title2).bold()
                        .foregroundColor(.kacha)
                    Text("稼働率")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 36)
                    .background(Color.kachaCardBorder)

                VStack(spacing: 4) {
                    Text("\(bookedDays)")
                        .font(.title2).bold()
                        .foregroundColor(.kachaWarn)
                    Text("予約日数")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 36)
                    .background(Color.kachaCardBorder)

                let vacantDays = totalDays - bookedDays
                VStack(spacing: 4) {
                    Text("\(vacantDays)")
                        .font(.title2).bold()
                        .foregroundColor(.kachaSuccess)
                    Text("空室日数")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 16)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Weekday Row

    private var weekdayRow: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, sym in
                Text(sym)
                    .font(.caption2).bold()
                    .foregroundColor(index == 0 ? .kachaDanger : index == 6 ? .kachaAccent : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Availability Grid

    private var availabilityGrid: some View {
        let days = daysInMonth(displayMonth)
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(days.indices, id: \.self) { index in
                if let day = days[index] {
                    AvailabilityDayCell(
                        day: day,
                        availability: aggregatedAvailability(for: day),
                        homeColors: homeColorsForDay(day)
                    )
                } else {
                    Color.clear.frame(height: 52)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Legend

    private var legend: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.kacha)
                    Text("凡例")
                        .font(.caption).bold()
                        .foregroundColor(.white)
                }

                HStack(spacing: 16) {
                    legendItem(color: .kachaSuccess, label: "空室")
                    legendItem(color: .kachaWarn, label: "予約あり")
                    legendItem(color: .kachaDanger.opacity(0.7), label: "全室予約")
                    legendItem(color: .secondary, label: "過去")
                }
            }
            .padding(14)
        }
        .padding(.horizontal, 16)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 14, height: 14)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Availability Logic

    enum Availability {
        case vacant
        case partiallyBooked
        case fullyBooked
        case past
    }

    private func dayAvailability(for day: Date, homeId: String) -> Availability {
        let start = calendar.startOfDay(for: day)
        if start < calendar.startOfDay(for: Date()) {
            let hasBooking = activeBookings.contains { booking in
                booking.homeId == homeId &&
                calendar.startOfDay(for: booking.checkIn) <= start &&
                calendar.startOfDay(for: booking.checkOut) > start
            }
            return hasBooking ? .fullyBooked : .past
        }

        let isBooked = activeBookings.contains { booking in
            booking.homeId == homeId &&
            calendar.startOfDay(for: booking.checkIn) <= start &&
            calendar.startOfDay(for: booking.checkOut) > start
        }
        return isBooked ? .fullyBooked : .vacant
    }

    private func aggregatedAvailability(for day: Date) -> Availability {
        let start = calendar.startOfDay(for: day)
        if start < calendar.startOfDay(for: Date()) {
            return .past
        }

        let relevantHomes = filteredHomes
        guard !relevantHomes.isEmpty else { return .vacant }

        let bookedCount = relevantHomes.filter { home in
            activeBookings.contains { booking in
                booking.homeId == home.id &&
                calendar.startOfDay(for: booking.checkIn) <= start &&
                calendar.startOfDay(for: booking.checkOut) > start
            }
        }.count

        if bookedCount == 0 { return .vacant }
        if bookedCount >= relevantHomes.count { return .fullyBooked }
        return .partiallyBooked
    }

    private func homeColorsForDay(_ day: Date) -> [Color] {
        let start = calendar.startOfDay(for: day)
        return filteredHomes.compactMap { home in
            let isBooked = activeBookings.contains { booking in
                booking.homeId == home.id &&
                calendar.startOfDay(for: booking.checkIn) <= start &&
                calendar.startOfDay(for: booking.checkOut) > start
            }
            guard isBooked else { return nil }
            return homeColor(for: home)
        }
    }

    private func homeColor(for home: Home) -> Color {
        let colors: [Color] = [.kacha, .kachaAccent, .kachaDanger, .kachaSuccess, .kachaWarn]
        guard let index = homes.firstIndex(where: { $0.id == home.id }) else { return .kacha }
        return colors[index % colors.count]
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
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }
}

// MARK: - AvailabilityDayCell

struct AvailabilityDayCell: View {
    let day: Date
    let availability: CalendarAvailabilityView.Availability
    let homeColors: [Color]

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 2) {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(textColor)

            if !homeColors.isEmpty {
                HStack(spacing: 2) {
                    ForEach(homeColors.prefix(3).indices, id: \.self) { i in
                        Circle()
                            .fill(homeColors[i])
                            .frame(width: 5, height: 5)
                    }
                    if homeColors.count > 3 {
                        Text("+")
                            .font(.system(size: 7))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 6)
            } else {
                Spacer().frame(height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(cellBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(todayBorder)
    }

    private var cellBackground: Color {
        switch availability {
        case .vacant:          return Color.kachaSuccess.opacity(0.10)
        case .partiallyBooked: return Color.kachaWarn.opacity(0.15)
        case .fullyBooked:     return Color.kachaDanger.opacity(0.12)
        case .past:            return Color.clear
        }
    }

    private var textColor: Color {
        if calendar.isDateInToday(day) { return .kacha }
        if availability == .past { return .secondary.opacity(0.5) }
        let weekday = calendar.component(.weekday, from: day)
        if weekday == 1 { return .kachaDanger }
        if weekday == 7 { return .kachaAccent }
        return .white
    }

    @ViewBuilder
    private var todayBorder: some View {
        if calendar.isDateInToday(day) {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.kacha, lineWidth: 1.5)
        }
    }
}
