import SwiftUI
import SwiftData
import Charts

struct RevenueDashboardView: View {
    @Query(sort: \Booking.checkIn) private var allBookings: [Booking]
    @Query(sort: \Home.sortOrder) private var homes: [Home]
    @State private var selectedDate = Date()
    @ObservedObject private var subscription = SubscriptionManager.shared

    private var calendar: Calendar { Calendar.current }

    private var activeBookings: [Booking] {
        allBookings.filter { $0.status != "cancelled" }
    }

    private var monthBookings: [Booking] {
        activeBookings.filter { booking in
            let start = Self.monthStart(for: selectedDate)
            guard let end = calendar.date(byAdding: .month, value: 1, to: start) else { return false }
            return booking.checkIn >= start && booking.checkIn < end
        }
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: selectedDate)?.count ?? 30
    }

    private var totalRevenue: Int {
        monthBookings.reduce(0) { $0 + $1.totalAmount }
    }

    private var totalCommission: Int {
        monthBookings.reduce(0) { $0 + $1.commission }
    }

    private var totalBookedNights: Int {
        monthBookings.reduce(0) { $0 + $1.nights }
    }

    private var occupancyRate: Double {
        guard !homes.isEmpty else { return 0 }
        let capacity = homes.count * daysInMonth
        return min(Double(totalBookedNights) / Double(capacity) * 100, 100)
    }

    private var adr: Int {
        guard totalBookedNights > 0 else { return 0 }
        return totalRevenue / totalBookedNights
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月"
        f.locale = Locale(identifier: "ja_JP")
        return f.string(from: selectedDate)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        monthPicker
                        summaryCards
                        propertyBreakdown
                        trendChart
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
                .blur(radius: subscription.isPro ? 0 : 6)
                .allowsHitTesting(subscription.isPro)

                if !subscription.isPro {
                    ProFeatureOverlay(featureName: "収益ダッシュボード")
                }
            }
            .navigationTitle("収益ダッシュボード")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Month Picker

    private var monthPicker: some View {
        HStack {
            Button {
                withAnimation { shiftMonth(by: -1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.bold())
                    .foregroundColor(.kacha)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Text(monthLabel)
                .font(.title3.bold())
                .foregroundColor(.white)

            Spacer()

            Button {
                withAnimation { shiftMonth(by: 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.bold())
                    .foregroundColor(.kacha)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                summaryCard(
                    icon: "yensign.circle.fill",
                    title: "売上",
                    value: formatYen(totalRevenue),
                    color: .kachaSuccess
                )
                summaryCard(
                    icon: "bed.double.fill",
                    title: "稼働率",
                    value: String(format: "%.1f%%", occupancyRate),
                    color: .kachaAccent
                )
                summaryCard(
                    icon: "chart.bar.fill",
                    title: "ADR",
                    value: formatYen(adr),
                    color: .kacha
                )
                summaryCard(
                    icon: "calendar.badge.checkmark",
                    title: "予約数",
                    value: "\(monthBookings.count)件",
                    color: .white
                )
                summaryCard(
                    icon: "arrow.left.arrow.right",
                    title: "手数料",
                    value: formatYen(totalCommission),
                    color: .kachaDanger
                )
            }
            .padding(.horizontal, 4)
        }
    }

    private func summaryCard(icon: String, title: String, value: String, color: Color) -> some View {
        KachaCard {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(value)
                    .font(.headline.monospacedDigit())
                    .foregroundColor(.white)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 100)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Per-Property Breakdown

    private var propertyBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("物件別")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.leading, 4)

            LazyVStack(spacing: 10) {
                ForEach(homes, id: \.id) { home in
                    propertyRow(home: home)
                }
            }
        }
    }

    private func propertyRow(home: Home) -> some View {
        let homeBookings = monthBookings.filter { $0.homeId == home.id }
        let revenue = homeBookings.reduce(0) { $0 + $1.totalAmount }
        let nights = homeBookings.reduce(0) { $0 + $1.nights }
        let rate = min(Double(nights) / Double(daysInMonth) * 100, 100)

        return KachaCard {
            VStack(spacing: 10) {
                HStack {
                    Text(home.name)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Spacer()
                    Text(formatYen(revenue))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundColor(.kacha)
                }

                HStack(spacing: 16) {
                    Label(String(format: "%.0f%%", rate), systemImage: "bed.double")
                        .font(.caption)
                        .foregroundColor(.kachaAccent)
                    Label("\(homeBookings.count)件", systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Label("\(nights)泊", systemImage: "moon.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(Color.kachaAccent)
                            .frame(width: geo.size.width * CGFloat(rate / 100))
                    }
                }
                .frame(height: 4)
            }
            .padding(14)
        }
    }

    // MARK: - Trend Chart

    private var trendChart: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("月別推移（6ヶ月）")
                    .font(.headline)
                    .foregroundColor(.white)

                Chart {
                    ForEach(trendData, id: \.month) { item in
                        BarMark(
                            x: .value("月", item.label),
                            y: .value("売上", item.revenue)
                        )
                        .foregroundStyle(Color.kachaSuccess.opacity(0.7))

                        LineMark(
                            x: .value("月", item.label),
                            y: .value("稼働率", item.occupancy * Double(trendRevenueMax) / 100)
                        )
                        .foregroundStyle(Color.kachaAccent)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        PointMark(
                            x: .value("月", item.label),
                            y: .value("稼働率", item.occupancy * Double(trendRevenueMax) / 100)
                        )
                        .foregroundStyle(Color.kachaAccent)
                        .symbolSize(30)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                            .foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text(abbreviateYen(v))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(String.self) {
                                Text(v)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 220)

                HStack(spacing: 16) {
                    legendDot(.kachaSuccess.opacity(0.7), "売上")
                    legendDot(.kachaAccent, "稼働率")
                }
                .font(.caption2)
            }
            .padding(16)
        }
    }

    // MARK: - Trend Data

    private struct TrendItem {
        let month: String
        let label: String
        let revenue: Int
        let occupancy: Double
    }

    private var trendData: [TrendItem] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        let labelF = DateFormatter()
        labelF.dateFormat = "M月"

        return (0..<6).reversed().compactMap { offset -> TrendItem? in
            guard let date = calendar.date(byAdding: .month, value: -offset, to: selectedDate) else { return nil }
            let key = f.string(from: date)
            let start = Self.monthStart(for: date)
            guard let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            let days = calendar.range(of: .day, in: .month, for: date)?.count ?? 30

            let monthBookings = activeBookings.filter { b in
                b.checkIn >= start && b.checkIn < end
            }
            let revenue = monthBookings.reduce(0) { $0 + $1.totalAmount }
            let nights = monthBookings.reduce(0) { $0 + $1.nights }
            let capacity = max(homes.count, 1) * days
            let occ = min(Double(nights) / Double(capacity) * 100, 100)

            return TrendItem(month: key, label: labelF.string(from: date), revenue: revenue, occupancy: occ)
        }
    }

    private var trendRevenueMax: Int {
        max(trendData.map(\.revenue).max() ?? 1, 1)
    }

    // MARK: - Helpers

    private func shiftMonth(by value: Int) {
        if let d = calendar.date(byAdding: .month, value: value, to: selectedDate) {
            selectedDate = d
        }
    }

    private func formatYen(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        return "\u{00A5}\(formatted)"
    }

    private func abbreviateYen(_ amount: Int) -> String {
        if amount >= 10000 {
            return "\(amount / 10000)万"
        }
        return formatYen(amount)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundColor(.secondary)
        }
    }
}

// Calendar helper (scoped to avoid redeclaration with CalendarView)
extension RevenueDashboardView {
    static func monthStart(for date: Date, calendar: Calendar = .current) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }
}

#Preview {
    RevenueDashboardView()
        .modelContainer(for: [Booking.self, Home.self], inMemory: true)
}
