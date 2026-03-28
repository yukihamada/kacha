import Foundation

// MARK: - PricingSuggestionService
// 稼働率・曜日・季節要因から推奨価格を算出するサービス。
// Beds24の過去予約データを入力とし、日別の需要スコアと推奨価格を返す。

final class PricingSuggestionService {

    // MARK: - Public Types

    struct DailySuggestion: Identifiable {
        let id = UUID()
        let date: Date
        let occupancyRate: Double        // 0.0 ~ 1.0 (過去の同曜日・同季節での稼働率)
        let demandMultiplier: Double     // 合算需要倍率
        let suggestedPrice: Int          // 推奨価格（円）
        let basePrice: Int               // ベース価格
        let isHighDemand: Bool           // true = 繁忙（強調表示用）
        let demandLabel: String          // "閑散期" / "通常" / "繁忙" / "最繁忙"
    }

    struct WeeklyOccupancy: Identifiable {
        let id = UUID()
        let weekStart: Date
        let rate: Double   // 0.0 ~ 1.0
    }

    // MARK: - Constants

    /// 各曜日のベース需要係数（日=0 ~ 土=6）
    private static let weekdayBaseMultiplier: [Double] = [
        1.1,  // 日: チェックアウト多め、需要やや高
        0.85, // 月: 最低需要
        0.85, // 火
        0.90, // 水
        0.95, // 木
        1.25, // 金: チェックイン集中
        1.30  // 土: 最高需要
    ]

    /// 季節イベント定義
    private struct JapaneseEvent {
        let name: String
        let multiplier: Double
        let rule: (DateComponents) -> Bool
    }

    private static let events: [JapaneseEvent] = [
        // GW（4/29 ~ 5/6）
        JapaneseEvent(name: "GW", multiplier: 1.8) { dc in
            guard let m = dc.month, let d = dc.day else { return false }
            return (m == 4 && d >= 29) || (m == 5 && d <= 6)
        },
        // お盆（8/10 ~ 8/18）
        JapaneseEvent(name: "お盆", multiplier: 1.7) { dc in
            guard let m = dc.month, let d = dc.day else { return false }
            return m == 8 && d >= 10 && d <= 18
        },
        // 年末年始（12/28 ~ 1/4）
        JapaneseEvent(name: "年末年始", multiplier: 1.9) { dc in
            guard let m = dc.month, let d = dc.day else { return false }
            return (m == 12 && d >= 28) || (m == 1 && d <= 4)
        },
        // シルバーウィーク（9月第3週前後 ※可変）
        JapaneseEvent(name: "シルバーウィーク", multiplier: 1.5) { dc in
            guard let m = dc.month, let d = dc.day else { return false }
            return m == 9 && d >= 14 && d <= 23
        },
        // 花火大会シーズン（7月後半〜8月上旬）
        JapaneseEvent(name: "花火大会", multiplier: 1.4) { dc in
            guard let m = dc.month, let d = dc.day else { return false }
            return (m == 7 && d >= 20) || (m == 8 && d <= 10)
        },
        // 春の花見シーズン（3/25 ~ 4/10）
        JapaneseEvent(name: "花見", multiplier: 1.3) { dc in
            guard let m = dc.month, let d = dc.day else { return false }
            return (m == 3 && d >= 25) || (m == 4 && d <= 10)
        },
        // 紅葉シーズン（11月中旬〜下旬）
        JapaneseEvent(name: "紅葉", multiplier: 1.2) { dc in
            guard let m = dc.month, let d = dc.day else { return false }
            return m == 11 && d >= 10 && d <= 30
        },
    ]

    // MARK: - Core Analysis

    /// 予約履歴から稼働率を分析し、指定期間の日別推奨価格を生成する。
    ///
    /// - Parameters:
    ///   - bookings: Beds24から取得した過去の予約一覧
    ///   - basePrice: 1泊ベース価格（円）
    ///   - minPrice: 最低価格（円）
    ///   - maxPrice: 最高価格（円）
    ///   - startDate: 生成開始日（省略時: 今日）
    ///   - days: 生成日数（省略時: 60日）
    /// - Returns: 日別推奨価格のリスト
    func generateSuggestions(
        from bookings: [Beds24Booking],
        basePrice: Int,
        minPrice: Int,
        maxPrice: Int,
        startDate: Date = Date(),
        days: Int = 60
    ) -> [DailySuggestion] {
        let occupancyMap = buildOccupancyMap(from: bookings)
        var suggestions: [DailySuggestion] = []
        let cal = Calendar.current

        for offset in 0..<days {
            guard let date = cal.date(byAdding: .day, value: offset, to: startDate) else { continue }
            let dc = cal.dateComponents([.month, .day, .weekday], from: date)
            let weekday = (dc.weekday ?? 1) - 1  // 0=日 ~ 6=土

            // 1. 曜日係数
            let weekdayMul = Self.weekdayBaseMultiplier[weekday]

            // 2. 季節・イベント係数（複数イベントが重なる場合は最大値を採用）
            let seasonMul = Self.events
                .filter { $0.rule(dc) }
                .map { $0.multiplier }
                .max() ?? 1.0

            // 3. 過去稼働率からの需要補正（データが少ない場合は中性値1.0）
            let occupancyKey = weekdayOccupancyKey(weekday: weekday, month: dc.month ?? 1)
            let historicalOccupancy = occupancyMap[occupancyKey] ?? 0.5
            let occupancyMul = occupancyMultiplier(from: historicalOccupancy)

            // 4. 合算倍率（小数点2桁で丸め）
            let combined = (weekdayMul * seasonMul * occupancyMul * 100).rounded() / 100

            // 5. 推奨価格を算出しクランプ
            let raw = Double(basePrice) * combined
            let suggested = max(minPrice, min(maxPrice, Int(raw.rounded(-2))))

            suggestions.append(DailySuggestion(
                date: date,
                occupancyRate: historicalOccupancy,
                demandMultiplier: combined,
                suggestedPrice: suggested,
                basePrice: basePrice,
                isHighDemand: combined >= 1.4,
                demandLabel: demandLabel(for: combined)
            ))
        }
        return suggestions
    }

    /// 週別稼働率サマリーを生成する（グラフ表示用）
    func weeklyOccupancy(from bookings: [Beds24Booking], weeks: Int = 12) -> [WeeklyOccupancy] {
        let cal = Calendar.current
        guard let earliestMonday = cal.date(
            byAdding: .weekOfYear, value: -(weeks - 1),
            to: cal.startOfWeek(for: Date())
        ) else { return [] }

        var result: [WeeklyOccupancy] = []

        for w in 0..<weeks {
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: w, to: earliestMonday),
                  let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart)
            else { continue }

            // この週に1泊でも重なる確定予約をカウント
            let bookedNights = bookings.filter { booking in
                guard let arr = booking.arrivalDate, let dep = booking.departureDate else { return false }
                let status = booking.status ?? ""
                guard status != "cancelled" else { return false }
                return arr < weekEnd && dep > weekStart
            }.reduce(0) { total, booking -> Int in
                guard let arr = booking.arrivalDate, let dep = booking.departureDate else { return total }
                let start = max(arr, weekStart)
                let end = min(dep, weekEnd)
                let nights = cal.dateComponents([.day], from: start, to: end).day ?? 0
                return total + max(0, nights)
            }

            result.append(WeeklyOccupancy(
                weekStart: weekStart,
                rate: min(1.0, Double(bookedNights) / 7.0)
            ))
        }
        return result
    }

    /// 来週末の需要変化サマリー文字列（HomeViewカード用）
    func nextWeekendSummary(from bookings: [Beds24Booking], basePrice: Int) -> String {
        let suggestions = generateSuggestions(from: bookings, basePrice: basePrice,
                                              minPrice: 0, maxPrice: Int.max, days: 14)
        let cal = Calendar.current
        let weekendSuggestions = suggestions.filter {
            let weekday = cal.component(.weekday, from: $0.date)
            return weekday == 6 || weekday == 7  // 金・土
        }.prefix(2)

        guard !weekendSuggestions.isEmpty else { return "来週末のデータがありません" }

        let avgMul = weekendSuggestions.map { $0.demandMultiplier }.reduce(0, +) / Double(weekendSuggestions.count)
        let change = Int((avgMul - 1.0) * 100)

        if change >= 30 {
            return "来週末は需要+\(change)% — 価格を上げましょう"
        } else if change >= 10 {
            return "来週末は需要+\(change)%の見込みです"
        } else if change <= -10 {
            return "来週末は需要\(change)% — 値下げを検討してください"
        } else {
            return "来週末は通常需要の見込みです"
        }
    }

    // MARK: - Beds24 Price Update

    /// Beds24に推奨価格を反映する
    /// - Note: Beds24 API v2 の `/prices` エンドポイントへPOSTする
    func applyPrice(_ suggestion: DailySuggestion, propertyId: Int, roomId: Int, token: String) async throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: suggestion.date)

        let payload: [[String: Any]] = [[
            "propertyId": propertyId,
            "roomId": roomId,
            "date": dateStr,
            "price": suggestion.suggestedPrice
        ]]

        guard let pricesURL = URL(string: "https://api.beds24.com/v2/prices") else { throw PricingError.apiError(0) }
        var req = URLRequest(url: pricesURL)
        req.httpMethod = "POST"
        req.addValue(token, forHTTPHeaderField: "token")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        req.timeoutInterval = 15

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode < 300 else {
            throw PricingError.apiError((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    // MARK: - Private Helpers

    /// 予約一覧から (曜日, 月) キーで稼働率マップを構築する
    private func buildOccupancyMap(from bookings: [Beds24Booking]) -> [String: Double] {
        let cal = Calendar.current
        var nightsByKey: [String: Int] = [:]
        var totalByKey: [String: Int] = [:]

        // 過去12ヶ月を対象とする
        let cutoff = cal.date(byAdding: .month, value: -12, to: Date()) ?? Date.distantPast

        for booking in bookings {
            guard let arr = booking.arrivalDate, let dep = booking.departureDate,
                  arr > cutoff, (booking.status ?? "") != "cancelled"
            else { continue }

            var cursor = arr
            while cursor < dep {
                let dc = cal.dateComponents([.weekday, .month], from: cursor)
                let weekday = (dc.weekday ?? 1) - 1
                let month = dc.month ?? 1
                let key = weekdayOccupancyKey(weekday: weekday, month: month)
                nightsByKey[key, default: 0] += 1
                cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? dep
            }
        }

        // 同じキーが過去12ヶ月に存在する週数を分母にする
        for key in nightsByKey.keys {
            // 概算: 12ヶ月 ÷ 7 ≒ 52週、同曜日は約52回
            totalByKey[key] = 52
        }

        return nightsByKey.reduce(into: [:]) { result, pair in
            let total = totalByKey[pair.key] ?? 52
            result[pair.key] = min(1.0, Double(pair.value) / Double(total))
        }
    }

    private func weekdayOccupancyKey(weekday: Int, month: Int) -> String {
        "w\(weekday)m\(month)"
    }

    /// 稼働率 → 需要倍率（線形補間）
    /// 稼働率0% → 0.7倍, 50% → 1.0倍, 100% → 1.4倍
    private func occupancyMultiplier(from rate: Double) -> Double {
        let clamped = max(0, min(1, rate))
        return 0.7 + clamped * 0.7
    }

    private func demandLabel(for multiplier: Double) -> String {
        switch multiplier {
        case ..<0.9:  return "閑散期"
        case ..<1.2:  return "通常"
        case ..<1.5:  return "繁忙"
        default:      return "最繁忙"
        }
    }
}

// MARK: - Beds24Booking Extension (Date parsing)

extension Beds24Booking {
    private static let dateParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var arrivalDate: Date? {
        guard let s = arrival else { return nil }
        return Self.dateParser.date(from: s)
    }

    var departureDate: Date? {
        guard let s = departure else { return nil }
        return Self.dateParser.date(from: s)
    }
}

// MARK: - Calendar Extension

private extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? date
    }
}

// MARK: - Int rounding helper (round to nearest N)

private extension Int {
    /// 指定した桁（負の値は10の累乗）で丸める
    /// e.g. 12345.rounded(-2) → 12300
    func rounded(_ decimals: Int) -> Int {
        guard decimals < 0 else { return self }
        let factor = Int(pow(10.0, Double(-decimals)))
        return (self / factor) * factor
    }
}

private extension Double {
    func rounded(_ decimals: Int) -> Double {
        let factor = pow(10.0, Double(-decimals))
        return (self / factor).rounded() * factor
    }
}

// MARK: - PricingError

enum PricingError: Error, LocalizedError {
    case apiError(Int)
    var errorDescription: String? {
        switch self {
        case .apiError(let code): return "価格更新エラー: HTTP \(code)"
        }
    }
}
