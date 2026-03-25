import SwiftUI
import SwiftData
import Charts

// MARK: - PricingSuggestionView

struct PricingSuggestionView: View {
    let home: Home

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var allBookings: [Booking]

    // ---- State ----
    @State private var suggestions: [PricingSuggestionService.DailySuggestion] = []
    @State private var weeklyOccupancy: [PricingSuggestionService.WeeklyOccupancy] = []
    @State private var selectedDate: Date? = nil
    @State private var isLoading = false
    @State private var applyingDate: Date? = nil
    @State private var applySuccess = false
    @State private var errorMessage: String? = nil
    @State private var calendarMonth = Date()
    @State private var basePrice: Int = 15000

    private let service = PricingSuggestionService()
    // populated via fetchAndAnalyze()
    @State private var beds24Bookings: [Beds24Booking] = []

    // ---- Derived ----
    private var beds24Token: String { home.beds24ApiKey }
    private var hasBeds24: Bool { !beds24Token.isEmpty }

    private var selectedSuggestion: PricingSuggestionService.DailySuggestion? {
        guard let d = selectedDate else { return nil }
        let cal = Calendar.current
        return suggestions.first { cal.isDate($0.date, inSameDayAs: d) }
    }

    private var calendarSuggestions: [PricingSuggestionService.DailySuggestion] {
        let cal = Calendar.current
        return suggestions.filter {
            cal.isDate($0.date, equalTo: calendarMonth, toGranularity: .month)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        headerCard
                        weeklyOccupancyChart
                        calendarSection
                        if let sel = selectedSuggestion {
                            selectedDetailCard(sel)
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationBarHidden(true)
            .task { await fetchAndAnalyze() }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("料金提案").font(.headline).bold().foregroundColor(.white)
                    Text(home.name).font(.caption).foregroundColor(.kacha)
                }
                Spacer()
                // balance button
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.bottom, 16)

            if isLoading {
                ProgressView()
                    .tint(.kacha)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                basePriceRow
            }
        }
        .padding(16)
        .background(Color.kachaCard)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.kachaCardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var basePriceRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ベース価格 (1泊)").font(.caption).foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("¥").font(.caption).foregroundColor(.kacha)
                    TextField("15000", value: $basePrice, format: .number)
                        .font(.title2).bold().foregroundColor(.white)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 120)
                        .onChange(of: basePrice) { _, _ in recompute() }
                }
            }
            Spacer()
            Button {
                Task { await fetchAndAnalyze() }
            } label: {
                Label("再計算", systemImage: "arrow.clockwise")
                    .font(.caption).bold()
                    .foregroundColor(.kacha)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.kacha.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Weekly Occupancy Chart

    private var weeklyOccupancyChart: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "chart.bar.fill").foregroundColor(.kacha)
                    Text("週別稼働率（過去12週）")
                        .font(.subheadline).bold().foregroundColor(.white)
                }

                if weeklyOccupancy.isEmpty {
                    Text("予約データが少ないため稼働率グラフを表示できません")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    Chart {
                        ForEach(weeklyOccupancy) { week in
                            BarMark(
                                x: .value("週", weekLabel(week.weekStart)),
                                y: .value("稼働率", week.rate * 100)
                            )
                            .foregroundStyle(barColor(for: week.rate))
                            .cornerRadius(3)
                        }
                        RuleMark(y: .value("目標", 70))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(Color.kacha.opacity(0.5))
                            .annotation(position: .trailing) {
                                Text("70%").font(.system(size: 9)).foregroundColor(.kacha.opacity(0.7))
                            }
                    }
                    .frame(height: 160)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("\(Int(v))%").font(.system(size: 9)).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel().font(.system(size: 9)).foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "calendar").foregroundColor(.kacha)
                    Text("日別推奨価格")
                        .font(.subheadline).bold().foregroundColor(.white)
                    Spacer()
                    monthStepper
                }

                // Day-of-week header
                let dayNames = ["日", "月", "火", "水", "木", "金", "土"]
                HStack {
                    ForEach(dayNames, id: \.self) { d in
                        Text(d)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                // Calendar grid
                let days = calendarDays(for: calendarMonth)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                        if let date = day {
                            calendarCell(date: date)
                        } else {
                            Color.clear.frame(height: 52)
                        }
                    }
                }

                // Legend
                HStack(spacing: 14) {
                    legendPill(.kachaSuccess, "通常")
                    legendPill(.kachaWarn, "繁忙")
                    legendPill(.kachaDanger, "最繁忙")
                }
                .font(.caption2)
                .padding(.top, 4)
            }
            .padding(16)
        }
    }

    private var monthStepper: some View {
        HStack(spacing: 4) {
            Button {
                calendarMonth = Calendar.current.date(byAdding: .month, value: -1, to: calendarMonth) ?? calendarMonth
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            Text(monthLabel(calendarMonth))
                .font(.caption).bold().foregroundColor(.white)
                .frame(minWidth: 60)
            Button {
                calendarMonth = Calendar.current.date(byAdding: .month, value: 1, to: calendarMonth) ?? calendarMonth
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
        }
    }

    private func calendarCell(date: Date) -> some View {
        let cal = Calendar.current
        let sug = suggestions.first { cal.isDate($0.date, inSameDayAs: date) }
        let isSelected = selectedDate.map { cal.isDate($0, inSameDayAs: date) } ?? false
        let isPast = date < cal.startOfDay(for: Date())

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedDate = (isSelected ? nil : date)
            }
        } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? .black : (isPast ? .secondary.opacity(0.4) : .white))

                if let s = sug {
                    Text("¥\(compactPrice(s.suggestedPrice))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(isSelected ? .black : priceColor(s))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("-")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.3))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(isSelected ? Color.kacha : cellBackground(sug))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.kacha : Color.clear, lineWidth: 1.5)
            )
        }
        .disabled(isPast)
    }

    // MARK: - Selected Day Detail

    private func selectedDetailCard(_ sug: PricingSuggestionService.DailySuggestion) -> some View {
        KachaCard {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "tag.fill").foregroundColor(.kacha)
                    Text(formatDate(sug.date)).font(.subheadline).bold().foregroundColor(.white)
                    Spacer()
                    demandBadge(sug.demandLabel)
                }

                // Price comparison row
                HStack(spacing: 0) {
                    priceColumn(label: "ベース価格", value: sug.basePrice, color: .secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                    priceColumn(label: "推奨価格", value: sug.suggestedPrice, color: .kacha)
                }

                // Multiplier breakdown
                VStack(spacing: 6) {
                    multiplierRow(
                        icon: "chart.line.uptrend.xyaxis",
                        label: "需要倍率",
                        value: String(format: "×%.2f", sug.demandMultiplier),
                        color: .kachaAccent
                    )
                    multiplierRow(
                        icon: "percent",
                        label: "稼働率（過去同曜日）",
                        value: "\(Int(sug.occupancyRate * 100))%",
                        color: .kachaSuccess
                    )
                }

                if let err = errorMessage {
                    Text(err).font(.caption).foregroundColor(.kachaDanger)
                }

                // Apply button
                applyButton(sug)
            }
            .padding(16)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func applyButton(_ sug: PricingSuggestionService.DailySuggestion) -> some View {
        let isApplying = applyingDate.map {
            Calendar.current.isDate($0, inSameDayAs: sug.date)
        } ?? false

        return Button {
            Task { await applyPrice(sug) }
        } label: {
            HStack(spacing: 8) {
                if isApplying {
                    ProgressView().tint(.black).scaleEffect(0.8)
                } else if applySuccess {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                } else {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 14))
                }
                Text(applySuccess ? "適用しました" : "この価格を適用（Beds24）")
                    .font(.subheadline).bold()
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(applySuccess ? Color.kachaSuccess : Color.kacha)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isApplying || !hasBeds24)
        .overlay {
            if !hasBeds24 {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.4))
                    .overlay(
                        Text("Beds24 APIキーを設定してください")
                            .font(.caption2).foregroundColor(.white.opacity(0.7))
                    )
            }
        }
    }

    // MARK: - Data Fetch & Compute

    private func fetchAndAnalyze() async {
        isLoading = true
        defer { isLoading = false }

        // SwiftData bookings → 稼働率分析の元データとして Beds24Booking へ変換
        let converted = allBookings
            .filter { $0.homeId == home.id }
            .map { b -> Beds24Booking in
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                return Beds24Booking(
                    id: Int(b.externalId) ?? 0,
                    propertyId: nil,
                    roomId: nil,
                    status: b.status,
                    arrival: fmt.string(from: b.checkIn),
                    departure: fmt.string(from: b.checkOut),
                    firstName: nil, lastName: nil, email: nil, phone: nil,
                    numAdult: nil, numChild: nil,
                    price: Double(b.totalAmount) / 100.0,
                    commission: nil, referer: nil, channel: b.platform,
                    apiReference: nil, comments: nil, notes: nil
                )
            }

        // Beds24から直接予約取得（API接続がある場合）
        var beds24: [Beds24Booking] = converted
        if hasBeds24 {
            if let fetched = try? await Beds24Client.shared.fetchBookings(token: beds24Token) {
                beds24 = fetched + converted
            }
        }

        await MainActor.run {
            let base = max(1000, basePrice)
            suggestions = service.generateSuggestions(
                from: beds24,
                basePrice: base,
                minPrice: base / 2,
                maxPrice: base * 4,
                days: 90
            )
            weeklyOccupancy = service.weeklyOccupancy(from: beds24, weeks: 12)
        }
    }

    private func recompute() {
        let local = allBookings
            .filter { $0.homeId == home.id }
            .map { b -> Beds24Booking in
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                return Beds24Booking(
                    id: Int(b.externalId) ?? 0,
                    propertyId: nil, roomId: nil,
                    status: b.status,
                    arrival: fmt.string(from: b.checkIn),
                    departure: fmt.string(from: b.checkOut),
                    firstName: nil, lastName: nil, email: nil, phone: nil,
                    numAdult: nil, numChild: nil,
                    price: Double(b.totalAmount) / 100.0,
                    commission: nil, referer: nil, channel: b.platform,
                    apiReference: nil, comments: nil, notes: nil
                )
            }
        let base = max(1000, basePrice)
        suggestions = service.generateSuggestions(
            from: local,
            basePrice: base,
            minPrice: base / 2,
            maxPrice: base * 4,
            days: 90
        )
    }

    private func applyPrice(_ sug: PricingSuggestionService.DailySuggestion) async {
        guard hasBeds24 else { return }
        applyingDate = sug.date
        errorMessage = nil
        applySuccess = false

        do {
            // propertyId / roomId は現時点では0を送信（設定画面で拡張予定）
            try await service.applyPrice(sug, propertyId: 0, roomId: 0, token: beds24Token)
            withAnimation { applySuccess = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { applySuccess = false }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        applyingDate = nil
    }

    // MARK: - UI Helpers

    private func calendarDays(for month: Date) -> [Date?] {
        let cal = Calendar.current
        let range = cal.range(of: .day, in: .month, for: month)!
        let firstDay = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let firstWeekday = cal.component(.weekday, from: firstDay) - 1  // 0=日

        var days: [Date?] = Array(repeating: nil, count: firstWeekday)
        for day in range {
            days.append(cal.date(byAdding: .day, value: day - 1, to: firstDay))
        }
        // Fill trailing nils to complete last row
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    private func cellBackground(_ sug: PricingSuggestionService.DailySuggestion?) -> Color {
        guard let s = sug else { return Color.white.opacity(0.04) }
        switch s.demandLabel {
        case "最繁忙": return Color.kachaDanger.opacity(0.15)
        case "繁忙":   return Color.kachaWarn.opacity(0.12)
        case "閑散期": return Color.white.opacity(0.04)
        default:       return Color.kachaSuccess.opacity(0.08)
        }
    }

    private func priceColor(_ sug: PricingSuggestionService.DailySuggestion) -> Color {
        switch sug.demandLabel {
        case "最繁忙": return .kachaDanger
        case "繁忙":   return .kachaWarn
        case "閑散期": return .secondary
        default:       return .kachaSuccess
        }
    }

    private func barColor(for rate: Double) -> Color {
        if rate >= 0.8 { return .kachaDanger }
        if rate >= 0.6 { return .kachaWarn }
        if rate >= 0.3 { return .kachaSuccess }
        return Color.kachaAccent.opacity(0.5)
    }

    private func compactPrice(_ price: Int) -> String {
        if price >= 10000 {
            return "\(price / 1000)K"
        }
        return "\(price)"
    }

    private func weekLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }

    private func monthLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return f.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日(E)"
        return f.string(from: date)
    }

    // MARK: - Sub-views

    private func priceColumn(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text("¥\(value.formatted())")
                .font(.title3).bold()
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func multiplierRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon).font(.caption).foregroundColor(color)
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption).bold().foregroundColor(color)
        }
    }

    private func demandBadge(_ label: String) -> some View {
        let color: Color = {
            switch label {
            case "最繁忙": return .kachaDanger
            case "繁忙":   return .kachaWarn
            case "閑散期": return .secondary
            default:       return .kachaSuccess
            }
        }()
        return Text(label)
            .font(.caption2).bold()
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func legendPill(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.5))
                .frame(width: 12, height: 8)
            Text(label).foregroundColor(.secondary)
        }
    }
}

// MARK: - PricingSuggestionCard (HomeView埋め込み用サマリーカード)

struct PricingSuggestionCard: View {
    let home: Home
    @Query private var allBookings: [Booking]
    @State private var showDetail = false
    @State private var summaryText = "料金分析中..."

    private let service = PricingSuggestionService()

    var body: some View {
        Button { showDetail = true } label: {
            KachaCard {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.kacha.opacity(0.15))
                            .frame(width: 50, height: 50)
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 22))
                            .foregroundColor(.kacha)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("料金提案").font(.subheadline).bold().foregroundColor(.white)
                        Text(summaryText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(16)
            }
        }
        .sheet(isPresented: $showDetail) {
            PricingSuggestionView(home: home)
        }
        .task { await buildSummary() }
    }

    private func buildSummary() async {
        let bookings = allBookings
            .filter { $0.homeId == home.id }
            .map { b -> Beds24Booking in
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                return Beds24Booking(
                    id: Int(b.externalId) ?? 0,
                    propertyId: nil, roomId: nil,
                    status: b.status,
                    arrival: fmt.string(from: b.checkIn),
                    departure: fmt.string(from: b.checkOut),
                    firstName: nil, lastName: nil, email: nil, phone: nil,
                    numAdult: nil, numChild: nil, price: nil,
                    commission: nil, referer: nil, channel: nil,
                    apiReference: nil, comments: nil, notes: nil
                )
            }

        let base = 15000
        let text = service.nextWeekendSummary(from: bookings, basePrice: base)
        await MainActor.run { summaryText = text }
    }
}
