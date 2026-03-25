import SwiftUI
import SwiftData

// MARK: - Data model

struct DayRevenue: Identifiable {
    let id: Date
    let date: Date
    let amount: Int          // 円（日別按分後）
    let bookings: [Booking]  // その日にまたがる予約

    var hasRevenue: Bool { amount > 0 }
}

// MARK: - Main View

struct RevenueHeatmapView: View {
    // nil = 全物件
    let homes: [Home]
    let selectedHomeId: String?

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Booking.checkIn) private var allBookings: [Booking]

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var tappedDay: DayRevenue? = nil
    @State private var popupOffset: CGPoint = .zero

    // キャッシュ済み計算結果 — selectedYear または allBookings 変更時のみ再計算
    @State private var cachedDayMap: [Date: DayRevenue] = [:]
    @State private var cachedWeekColumns: [[Date?]] = []

    private var cal: Calendar { Calendar.current }

    // MARK: - Filtered bookings

    private var filteredBookings: [Booking] {
        let active = allBookings.filter { $0.status != "cancelled" }
        if let homeId = selectedHomeId {
            return active.filter { $0.homeId == homeId }
        }
        let ids = Set(homes.map { $0.id })
        return active.filter { ids.contains($0.homeId) }
    }

    // MARK: - Day map: 日別収益計算（キャッシュ用）

    private func buildDayMap() -> [Date: DayRevenue] {
        var map: [Date: (amount: Int, bookings: [Booking])] = [:]

        for booking in filteredBookings {
            let nights = max(booking.nights, 1)
            let perNight = booking.totalAmount / nights

            var cursor = cal.startOfDay(for: booking.checkIn)
            let checkOutDay = cal.startOfDay(for: booking.checkOut)
            while cursor < checkOutDay {
                if map[cursor] == nil {
                    map[cursor] = (0, [])
                }
                map[cursor]?.amount += perNight
                map[cursor]?.bookings.append(booking)
                guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }

        var result: [Date: DayRevenue] = [:]
        for (date, data) in map {
            result[date] = DayRevenue(id: date, date: date, amount: data.amount, bookings: data.bookings)
        }
        return result
    }

    private var dayMap: [Date: DayRevenue] { cachedDayMap }

    // MARK: - Year grid

    private var yearStart: Date {
        var comps = DateComponents()
        comps.year = selectedYear
        comps.month = 1
        comps.day = 1
        return cal.date(from: comps) ?? Date()
    }

    // 年間の全日（365 or 366日）を週単位に並べたグリッド
    private func buildWeekColumns() -> [[Date?]] {
        let start = yearStart
        var comps = DateComponents(); comps.year = selectedYear; comps.month = 12; comps.day = 31
        guard let end = cal.date(from: comps) else { return [] }

        let startWeekday = cal.component(.weekday, from: start)
        let mondayOffset = (startWeekday + 5) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -mondayOffset, to: start) else { return [] }

        var columns: [[Date?]] = []
        var cursor = gridStart
        while cursor <= end || columns.isEmpty {
            var week: [Date?] = []
            for _ in 0..<7 {
                let inYear = cal.component(.year, from: cursor) == selectedYear
                week.append(inYear ? cursor : nil)
                guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            columns.append(week)
            if cursor > end && cal.component(.year, from: cursor) > selectedYear { break }
        }
        return columns
    }

    private var weekColumns: [[Date?]] { cachedWeekColumns }

    // MARK: - Cache refresh

    private func refreshCache() {
        cachedDayMap = buildDayMap()
        cachedWeekColumns = buildWeekColumns()
    }

    // MARK: - Stats

    private var allDayRevenues: [DayRevenue] {
        dayMap.values.filter { cal.component(.year, from: $0.date) == selectedYear }
    }

    private var totalRevenue: Int { allDayRevenues.reduce(0) { $0 + $1.amount } }

    private var occupiedDays: Int { allDayRevenues.filter { $0.amount > 0 }.count }

    private var totalDaysInYear: Int { cal.range(of: .day, in: .year, for: yearStart)?.count ?? 365 }

    private var avgDailyRevenue: Int {
        occupiedDays > 0 ? totalRevenue / occupiedDays : 0
    }

    private var peakDay: DayRevenue? { allDayRevenues.max(by: { $0.amount < $1.amount }) }

    private var maxAmount: Int { allDayRevenues.max(by: { $0.amount < $1.amount })?.amount ?? 1 }

    private var longestStreak: Int {
        let sorted = allDayRevenues.filter { $0.amount > 0 }.sorted { $0.date < $1.date }
        var best = 0, cur = 0
        var prev: Date? = nil
        for d in sorted {
            if let p = prev, cal.dateComponents([.day], from: p, to: d.date).day == 1 {
                cur += 1
            } else {
                cur = 1
            }
            best = max(best, cur)
            prev = d.date
        }
        return best
    }

    // MARK: - Color

    private func heatColor(for amount: Int) -> Color {
        guard amount > 0 else { return Color.kachaCard }
        let ratio = Double(amount) / Double(max(maxAmount, 1))
        switch ratio {
        case ..<0.25: return Color.kacha.opacity(0.2)
        case ..<0.5:  return Color.kacha.opacity(0.45)
        case ..<0.75: return Color.kacha.opacity(0.7)
        default:      return Color.kacha
        }
    }

    // MARK: - Layout constants

    private let cellSize: CGFloat = 12
    private let gap: CGFloat = 2
    private let labelWidth: CGFloat = 22

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        yearPicker
                        summaryGrid
                        heatmapSection
                        legendRow
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 48)
                }

                // Popup overlay
                if let day = tappedDay {
                    dayPopup(day)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .navigationTitle("収益ヒートマップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.25)) { tappedDay = nil }
            }
            .onAppear { refreshCache() }
            .onChange(of: selectedYear) { refreshCache() }
            .onChange(of: allBookings.count) { refreshCache() }
        }
    }

    // MARK: - Year Picker

    private var yearPicker: some View {
        HStack(spacing: 20) {
            Button {
                withAnimation { selectedYear -= 1; tappedDay = nil }
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.kachaCard)
                    .clipShape(Circle())
            }

            Text("\(selectedYear)年")
                .font(.title3).bold().foregroundColor(.white)

            Button {
                withAnimation { selectedYear += 1; tappedDay = nil }
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(selectedYear < cal.component(.year, from: Date()) ? .secondary : Color.secondary.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .background(Color.kachaCard)
                    .clipShape(Circle())
            }
            .disabled(selectedYear >= cal.component(.year, from: Date()))
        }
        .padding(.top, 8)
    }

    // MARK: - Summary Grid

    private var summaryGrid: some View {
        let peakLabel: String = {
            guard let p = peakDay else { return "—" }
            let f = DateFormatter(); f.dateFormat = "M/d"; f.locale = Locale(identifier: "ja_JP")
            return f.string(from: p.date)
        }()

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2),
            spacing: 10
        ) {
            statCard(icon: "yensign.circle.fill", color: .kacha,
                     label: "年間収益", value: "¥\(totalRevenue.formatted())")
            statCard(icon: "bed.double.fill", color: .kachaAccent,
                     label: "稼働日 / \(totalDaysInYear)日", value: "\(occupiedDays)日")
            statCard(icon: "chart.bar.fill", color: .kachaSuccess,
                     label: "平均日次収益", value: "¥\(avgDailyRevenue.formatted())")
            statCard(icon: "flame.fill", color: .kachaDanger,
                     label: "最高収益日", value: peakLabel)
            statCard(icon: "link", color: Color.purple,
                     label: "連続稼働記録", value: "\(longestStreak)泊")
            statCard(icon: "percent", color: Color.teal,
                     label: "稼働率", value: occupiedDays > 0 ? "\(Int(Double(occupiedDays)/Double(totalDaysInYear)*100))%" : "0%")
        }
    }

    private func statCard(icon: String, color: Color, label: String, value: String) -> some View {
        KachaCard {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(.subheadline).bold().foregroundColor(.white)
                    Text(label).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
        }
    }

    // MARK: - Heatmap

    private var heatmapSection: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("日別収益カレンダー")
                    .font(.subheadline).bold().foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        monthLabels
                        HStack(alignment: .top, spacing: gap) {
                            weekdayLabels
                            heatmapGrid
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var monthLabels: some View {
        HStack(alignment: .top, spacing: gap) {
            // 曜日ラベル幅分のスペーサー
            Color.clear.frame(width: labelWidth, height: 14)

            ForEach(0..<weekColumns.count, id: \.self) { col in
                let week = weekColumns[col]
                let firstDay = week.compactMap { $0 }.first

                // その列に月初がある場合だけ月名を表示
                let label: String = {
                    guard let d = firstDay else { return "" }
                    let dayNum = cal.component(.day, from: d)
                    if dayNum <= 7 {
                        let f = DateFormatter(); f.dateFormat = "M月"
                        f.locale = Locale(identifier: "ja_JP")
                        return f.string(from: d)
                    }
                    return ""
                }()

                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(label.isEmpty ? .clear : .secondary)
                    .frame(width: cellSize, alignment: .leading)
            }
        }
    }

    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: gap) {
            let labels = ["月", "", "水", "", "金", "", "日"]
            ForEach(0..<7, id: \.self) { i in
                Text(labels[i])
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: labelWidth - gap, height: cellSize, alignment: .trailing)
            }
        }
    }

    private var heatmapGrid: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(0..<weekColumns.count, id: \.self) { col in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        let date = weekColumns[col][row]
                        cellView(for: date)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cellView(for date: Date?) -> some View {
        if let date = date {
            let day = dayMap[cal.startOfDay(for: date)]
            let amount = day?.amount ?? 0
            let isSelected = tappedDay?.date.timeIntervalSinceReferenceDate == cal.startOfDay(for: date).timeIntervalSinceReferenceDate
            let isToday = cal.isDateInToday(date)

            RoundedRectangle(cornerRadius: 2)
                .fill(heatColor(for: amount))
                .frame(width: cellSize, height: cellSize)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(
                            isToday ? Color.white.opacity(0.6) :
                            (amount > 0 ? Color.kacha.opacity(0.3) : Color.clear),
                            lineWidth: isToday ? 1 : 0.5
                        )
                )
                .scaleEffect(isSelected ? 1.5 : 1.0)
                .shadow(
                    color: amount > 0 ? Color.kacha.opacity(0.4) : .clear,
                    radius: amount > 0 ? 2 : 0
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        if isSelected {
                            tappedDay = nil
                        } else {
                            tappedDay = day ?? DayRevenue(
                                id: cal.startOfDay(for: date),
                                date: cal.startOfDay(for: date),
                                amount: 0,
                                bookings: []
                            )
                        }
                    }
                }
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.clear)
                .frame(width: cellSize, height: cellSize)
        }
    }

    // MARK: - Legend

    private var legendRow: some View {
        HStack(spacing: 6) {
            Text("少ない")
                .font(.caption2).foregroundColor(.secondary)
            ForEach([0, 1, 2, 3, 4], id: \.self) { level in
                let colors: [Color] = [
                    Color.kachaCard,
                    Color.kacha.opacity(0.2),
                    Color.kacha.opacity(0.45),
                    Color.kacha.opacity(0.7),
                    Color.kacha
                ]
                RoundedRectangle(cornerRadius: 2)
                    .fill(colors[level])
                    .frame(width: 12, height: 12)
            }
            Text("多い")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Day Popup

    private func dayPopup(_ day: DayRevenue) -> some View {
        let df = DateFormatter()
        df.dateFormat = "yyyy年M月d日(E)"
        df.locale = Locale(identifier: "ja_JP")

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(df.string(from: day.date))
                        .font(.caption).foregroundColor(.secondary)
                    Text(day.amount > 0 ? "¥\(day.amount.formatted())" : "収益なし")
                        .font(.title3).bold()
                        .foregroundColor(day.amount > 0 ? Color.kacha : .secondary)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.25)) { tappedDay = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
            }
            .padding(.bottom, 10)

            if day.bookings.isEmpty {
                Text("予約なし")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Divider().background(Color.white.opacity(0.1))
                    .padding(.bottom, 8)
                ForEach(Array(day.bookings.enumerated()), id: \.offset) { _, booking in
                    bookingRow(booking, dayAmount: booking.nights > 0 ? booking.totalAmount / booking.nights : booking.totalAmount)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.1))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: 300)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(true)
        .onTapGesture { }  // バブルアップ防止
    }

    private func bookingRow(_ booking: Booking, dayAmount: Int) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: booking.platformColor))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(booking.guestName.isEmpty ? "ゲスト" : booking.guestName)
                    .font(.subheadline).foregroundColor(.white)
                HStack(spacing: 6) {
                    Text(booking.platformLabel)
                        .font(.caption2).foregroundColor(.secondary)
                    Text("・")
                        .font(.caption2).foregroundColor(.secondary)
                    Text("\(booking.nights)泊")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            Text("¥\(dayAmount.formatted())/日")
                .font(.caption).foregroundColor(Color.kacha)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Mini Heatmap (Dashboard用 3ヶ月版)

struct MiniRevenueHeatmapView: View {
    let homes: [Home]
    let selectedHomeId: String?
    var onTapExpand: (() -> Void)? = nil

    @Query(
        filter: #Predicate<Booking> { $0.status != "cancelled" },
        sort: \Booking.checkIn
    ) private var allBookings: [Booking]

    @State private var cachedDayMap: [Date: Int] = [:]
    @State private var cachedWeekColumns: [[Date]] = []
    @State private var cachedDays90: [Date] = []

    private var cal: Calendar { Calendar.current }

    private var rangeStart: Date {
        cal.date(byAdding: .day, value: -89, to: cal.startOfDay(for: Date())) ?? cal.startOfDay(for: Date())
    }

    private var filteredBookings: [Booking] {
        if let homeId = selectedHomeId {
            return allBookings.filter { $0.homeId == homeId }
        }
        let ids = Set(homes.map { $0.id })
        return allBookings.filter { ids.contains($0.homeId) }
    }

    private func buildDayMap() -> [Date: Int] {
        let rs = rangeStart
        var map: [Date: Int] = [:]
        for booking in filteredBookings {
            let nights = max(booking.nights, 1)
            let perNight = booking.totalAmount / nights
            var cursor = cal.startOfDay(for: booking.checkIn)
            let checkOutDay = cal.startOfDay(for: booking.checkOut)
            while cursor < checkOutDay {
                if cursor >= rs {
                    map[cursor, default: 0] += perNight
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }
        return map
    }

    private func buildDays90() -> [Date] {
        let rs = rangeStart
        return (0..<90).compactMap { cal.date(byAdding: .day, value: $0, to: rs) }
    }

    private func buildWeekColumns(days90: [Date]) -> [[Date]] {
        let rs = rangeStart
        let startWeekday = cal.component(.weekday, from: rs)
        let mondayOffset = (startWeekday + 5) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -mondayOffset, to: rs) else { return [] }

        var columns: [[Date]] = []
        var cursor = gridStart
        let end = days90.last ?? Date()

        while cursor <= end {
            var week: [Date] = []
            for _ in 0..<7 {
                week.append(cursor)
                guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            columns.append(week)
        }
        return columns
    }

    private func refreshCache() {
        let d = buildDays90()
        cachedDays90 = d
        cachedDayMap = buildDayMap()
        cachedWeekColumns = buildWeekColumns(days90: d)
    }

    private var dayMap: [Date: Int] { cachedDayMap }
    private var weekColumns: [[Date]] { cachedWeekColumns }
    private var days90: [Date] { cachedDays90 }

    private var maxAmount: Int { dayMap.values.max() ?? 1 }

    private func heatColor(for amount: Int) -> Color {
        guard amount > 0 else { return Color.kachaCard }
        let ratio = Double(amount) / Double(max(maxAmount, 1))
        switch ratio {
        case ..<0.25: return Color.kacha.opacity(0.2)
        case ..<0.5:  return Color.kacha.opacity(0.45)
        case ..<0.75: return Color.kacha.opacity(0.7)
        default:      return Color.kacha
        }
    }

    private let cellSize: CGFloat = 10
    private let gap: CGFloat = 2

    var body: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("直近90日 収益")
                        .font(.subheadline).bold().foregroundColor(.white)
                    Spacer()
                    if onTapExpand != nil {
                        Button {
                            onTapExpand?()
                        } label: {
                            Text("年間表示")
                                .font(.caption2)
                                .foregroundColor(Color.kacha)
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(0..<weekColumns.count, id: \.self) { col in
                            VStack(spacing: gap) {
                                ForEach(0..<7, id: \.self) { row in
                                    let date = weekColumns[col][row]
                                    let inRange = date >= rangeStart && date <= (days90.last ?? Date())
                                    let amount = inRange ? (dayMap[date] ?? 0) : -1
                                    let isToday = cal.isDateInToday(date)

                                    if amount >= 0 {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(heatColor(for: amount))
                                            .frame(width: cellSize, height: cellSize)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 2)
                                                    .strokeBorder(
                                                        isToday ? Color.white.opacity(0.6) : Color.clear,
                                                        lineWidth: 1
                                                    )
                                            )
                                    } else {
                                        Color.clear.frame(width: cellSize, height: cellSize)
                                    }
                                }
                            }
                        }
                    }
                }

                // 簡易サマリー
                let total90 = dayMap.values.reduce(0, +)
                let occupied90 = dayMap.values.filter { $0 > 0 }.count
                HStack(spacing: 16) {
                    miniStat("90日収益", "¥\(total90.formatted())")
                    miniStat("稼働日数", "\(occupied90)日")
                    miniStat("稼働率", "\(Int(Double(occupied90)/90*100))%")
                }
            }
            .padding(14)
        }
        .onAppear { refreshCache() }
        .onChange(of: allBookings.count) { refreshCache() }
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.caption).bold().foregroundColor(.white)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }
}

// MARK: - Int formatting helper (カンマ区切り)
// NumberFormatter はスレッドセーフではないが MainActor 上でのみ使用するため問題なし

private let _jpDecimalFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "ja_JP")
    return f
}()

private extension Int {
    func formatted() -> String {
        _jpDecimalFormatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
