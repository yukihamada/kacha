import SwiftUI
import SwiftData

// MARK: - AutoPricingView

struct AutoPricingView: View {
    let home: Home

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var allBookings: [Booking]

    @AppStorage("autoPricingEnabled") private var autoPricingEnabled = false
    @State private var basePrice: Int = 15000
    @State private var weekendMultiplier: Double = 1.3
    @State private var peakMultiplier: Double = 1.5
    @State private var lowMultiplier: Double = 0.8
    @State private var preview: [DayPreview] = []
    @State private var isApplying = false
    @State private var applyResult: ApplyResult?
    @State private var showConfirm = false

    private let service = PricingSuggestionService()

    private var hasBeds24: Bool { !home.beds24ApiKey.isEmpty }

    struct DayPreview: Identifiable {
        let id = UUID()
        let date: Date
        let label: String
        let weekday: String
        let price: Int
        let tag: PriceTag
    }

    enum PriceTag: String {
        case normal = "通常"
        case weekend = "週末"
        case peak = "繁忙期"
        case low = "閑散期"

        var color: Color {
            switch self {
            case .normal:  return .kachaSuccess
            case .weekend: return .kachaWarn
            case .peak:    return .kachaDanger
            case .low:     return .kachaAccent
            }
        }
    }

    enum ApplyResult {
        case success
        case failure(String)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        toggleCard
                        basePriceCard
                        multiplierCards
                        previewCard
                        applySection
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationBarHidden(true)
            .onAppear { computePreview() }
        }
    }

    // MARK: - Toggle Card

    private var toggleCard: some View {
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
                    Text("自動料金設定").font(.headline).bold().foregroundColor(.white)
                    Text(home.name).font(.caption).foregroundColor(.kacha)
                }
                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.bottom, 16)

            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(autoPricingEnabled ? Color.kacha.opacity(0.15) : Color.white.opacity(0.06))
                        .frame(width: 50, height: 50)
                    Image(systemName: autoPricingEnabled ? "bolt.fill" : "bolt.slash")
                        .font(.system(size: 22))
                        .foregroundColor(autoPricingEnabled ? .kacha : .secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("自動料金設定")
                        .font(.subheadline).bold()
                        .foregroundColor(.white)
                    Text(autoPricingEnabled ? "有効 — 価格が自動で最適化されます" : "無効 — 手動で価格を管理しています")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: $autoPricingEnabled)
                    .tint(.kacha)
                    .labelsHidden()
            }
        }
        .padding(16)
        .background(Color.kachaCard)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.kachaCardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Base Price

    private var basePriceCard: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "yensign.circle.fill").foregroundColor(.kacha)
                    Text("基本料金").font(.subheadline).bold().foregroundColor(.white)
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("¥").font(.title3).foregroundColor(.kacha)
                    TextField("15000", value: $basePrice, format: .number)
                        .font(.title).bold().foregroundColor(.white)
                        .keyboardType(.numberPad)
                        .onChange(of: basePrice) { _, _ in computePreview() }
                    Text("/ 泊").font(.caption).foregroundColor(.secondary)
                }

                Text("平日の基準価格です。週末・繁忙期は倍率で自動調整されます。")
                    .font(.caption2).foregroundColor(.secondary)
            }
            .padding(16)
        }
    }

    // MARK: - Multiplier Rules

    private var multiplierCards: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "slider.horizontal.3").foregroundColor(.kacha)
                Text("料金ルール").font(.subheadline).bold().foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 4)

            multiplierCard(
                icon: "calendar.badge.clock",
                title: "週末（金・土）",
                description: "金曜・土曜のチェックイン需要増に対応",
                multiplier: $weekendMultiplier,
                tag: .weekend
            )

            multiplierCard(
                icon: "flame.fill",
                title: "繁忙期（GW・お盆・年末年始）",
                description: "ゴールデンウィーク、お盆、年末年始",
                multiplier: $peakMultiplier,
                tag: .peak
            )

            multiplierCard(
                icon: "snowflake",
                title: "閑散期（1〜2月）",
                description: "需要の低い時期に割引で稼働率アップ",
                multiplier: $lowMultiplier,
                tag: .low
            )
        }
    }

    private func multiplierCard(
        icon: String,
        title: String,
        description: String,
        multiplier: Binding<Double>,
        tag: PriceTag
    ) -> some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(tag.color)
                        .frame(width: 32, height: 32)
                        .background(tag.color.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.subheadline).bold().foregroundColor(.white)
                        Text(description).font(.caption2).foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(formatMultiplier(multiplier.wrappedValue))
                        .font(.headline).bold()
                        .foregroundColor(tag.color)
                }

                HStack(spacing: 8) {
                    Text("¥\(adjustedPrice(multiplier.wrappedValue).formatted())")
                        .font(.caption).foregroundColor(.secondary)

                    Spacer()

                    Slider(value: multiplier, in: sliderRange(for: tag), step: 0.05)
                        .tint(tag.color)
                        .frame(maxWidth: 180)
                }
            }
            .padding(14)
        }
        .onChange(of: multiplier.wrappedValue) { _, _ in computePreview() }
    }

    private func sliderRange(for tag: PriceTag) -> ClosedRange<Double> {
        switch tag {
        case .low:     return 0.5...1.0
        case .normal:  return 0.8...1.2
        case .weekend: return 1.0...2.0
        case .peak:    return 1.0...3.0
        }
    }

    private func formatMultiplier(_ value: Double) -> String {
        if value >= 1.0 {
            return "+\(Int((value - 1.0) * 100))%"
        } else {
            return "\(Int((value - 1.0) * 100))%"
        }
    }

    private func adjustedPrice(_ multiplier: Double) -> Int {
        Int((Double(max(1000, basePrice)) * multiplier / 100).rounded() * 100)
    }

    // MARK: - 7-Day Preview

    private var previewCard: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "eye.fill").foregroundColor(.kacha)
                    Text("今後7日間のプレビュー")
                        .font(.subheadline).bold().foregroundColor(.white)
                }

                ForEach(preview) { day in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.label)
                                .font(.caption).foregroundColor(.white)
                            Text(day.weekday)
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .frame(minWidth: 70, alignment: .leading)

                        Spacer()

                        Text(day.tag.rawValue)
                            .font(.caption2).bold()
                            .foregroundColor(day.tag.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(day.tag.color.opacity(0.15))
                            .clipShape(Capsule())

                        Text("¥\(day.price.formatted())")
                            .font(.subheadline).bold()
                            .foregroundColor(.white)
                            .frame(minWidth: 80, alignment: .trailing)
                    }
                    .padding(.vertical, 4)

                    if day.id != preview.last?.id {
                        Divider().background(Color.white.opacity(0.06))
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Apply

    private var applySection: some View {
        VStack(spacing: 10) {
            if let result = applyResult {
                switch result {
                case .success:
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.kachaSuccess)
                        Text("7日間の料金をBeds24に適用しました")
                            .font(.caption).foregroundColor(.kachaSuccess)
                    }
                case .failure(let message):
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.kachaDanger)
                        Text(message).font(.caption).foregroundColor(.kachaDanger)
                    }
                }
            }

            Button {
                showConfirm = true
            } label: {
                HStack(spacing: 8) {
                    if isApplying {
                        ProgressView().tint(.black).scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 14))
                    }
                    Text("7日間の料金を適用").font(.subheadline).bold()
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.kacha)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isApplying || !hasBeds24)
            .overlay {
                if !hasBeds24 {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.4))
                        .overlay(
                            Text("Beds24 APIキーを設定してください")
                                .font(.caption2).foregroundColor(.white.opacity(0.7))
                        )
                }
            }
            .alert("料金を適用しますか？", isPresented: $showConfirm) {
                Button("適用する") { Task { await applyPrices() } }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("今後7日間の料金をBeds24に反映します。")
            }
        }
    }

    // MARK: - Compute

    private func computePreview() {
        let cal = Calendar.current
        let base = max(1000, basePrice)
        var days: [DayPreview] = []

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP")
        dateFormatter.dateFormat = "M/d"

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "ja_JP")
        weekdayFormatter.dateFormat = "E"

        for offset in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: offset, to: Date()) else { continue }
            let dc = cal.dateComponents([.month, .day, .weekday], from: date)
            let weekday = (dc.weekday ?? 1)

            let tag: PriceTag
            let multiplier: Double

            if isPeakSeason(dc) {
                tag = .peak
                multiplier = peakMultiplier
            } else if isLowSeason(dc) {
                tag = .low
                multiplier = lowMultiplier
            } else if weekday == 6 || weekday == 7 { // Fri or Sat
                tag = .weekend
                multiplier = weekendMultiplier
            } else {
                tag = .normal
                multiplier = 1.0
            }

            let price = Int((Double(base) * multiplier / 100).rounded() * 100)

            days.append(DayPreview(
                date: date,
                label: dateFormatter.string(from: date),
                weekday: weekdayFormatter.string(from: date),
                price: price,
                tag: tag
            ))
        }

        preview = days
    }

    private func isPeakSeason(_ dc: DateComponents) -> Bool {
        guard let m = dc.month, let d = dc.day else { return false }
        // GW
        if (m == 4 && d >= 29) || (m == 5 && d <= 6) { return true }
        // Obon
        if m == 8 && d >= 10 && d <= 18 { return true }
        // Year-end / New Year
        if (m == 12 && d >= 28) || (m == 1 && d <= 4) { return true }
        return false
    }

    private func isLowSeason(_ dc: DateComponents) -> Bool {
        guard let m = dc.month else { return false }
        return m == 1 || m == 2
    }

    private func applyPrices() async {
        guard hasBeds24 else { return }
        isApplying = true
        applyResult = nil

        do {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"

            let entries = preview.map { day in
                Beds24PriceEntry(
                    propertyId: 0,
                    roomId: 0,
                    date: fmt.string(from: day.date),
                    price: Double(day.price)
                )
            }

            try await Beds24Client.shared.setPrices(entries: entries, token: home.beds24ApiKey)

            ActivityLogger.log(
                context: context,
                homeId: home.id,
                action: "auto_pricing_apply",
                detail: "自動料金設定: 7日間の価格をBeds24に適用"
            )
            try? context.save()

            withAnimation { applyResult = .success }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation { applyResult = nil }
        } catch {
            withAnimation { applyResult = .failure(error.localizedDescription) }
        }

        isApplying = false
    }
}
