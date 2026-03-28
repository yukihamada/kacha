import XCTest
@testable import Kacha

// MARK: - PricingSuggestionService Unit Tests
// 季節係数・曜日係数・価格レンジクランプ・エッジケースをテストする。
// ネットワーク不要の純粋なロジックテスト。

final class PricingSuggestionTests: XCTestCase {

    private let service = PricingSuggestionService()
    private let basePrice = 10_000   // 1泊1万円
    private let minPrice  = 5_000
    private let maxPrice  = 30_000

    // MARK: - テスト用日付ヘルパー

    /// 指定年月日のDateを返す (日本標準時のローカルカレンダー基準)
    private func date(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps)!
    }

    // MARK: - 季節係数: GW

    func testGWPeriodHasHighMultiplier() {
        // GW: 4/29 ~ 5/6 は multiplier 1.8
        let gwDates = [
            date(year: 2026, month: 4, day: 29),
            date(year: 2026, month: 5, day: 1),
            date(year: 2026, month: 5, day: 6),
        ]
        for gwDate in gwDates {
            let suggestions = service.generateSuggestions(
                from: [],
                basePrice: basePrice,
                minPrice: minPrice,
                maxPrice: maxPrice,
                startDate: gwDate,
                days: 1
            )
            guard let s = suggestions.first else {
                XCTFail("GW日付 \(gwDate) のサジェストが生成されない")
                continue
            }
            // GW係数(1.8) x 最低曜日係数(0.85) x 占有率デフォルト補正(0.7+0.5*0.7=1.05) = ~1.60
            // 少なくとも 1.0 を超えることを保証
            XCTAssertGreaterThan(s.demandMultiplier, 1.0,
                "GW期間の需要倍率は1.0を超えるべき: \(gwDate), multiplier=\(s.demandMultiplier)")
        }
    }

    func testGWDateIsHighDemand() {
        let gw = date(year: 2026, month: 5, day: 3)
        let suggestions = service.generateSuggestions(
            from: [],
            basePrice: basePrice,
            minPrice: 0,
            maxPrice: Int.max,
            startDate: gw,
            days: 1
        )
        let s = try! XCTUnwrap(suggestions.first)
        // GW x 平日係数でもisHighDemand (combined >= 1.4) になる
        XCTAssertTrue(s.isHighDemand, "GW期間はisHighDemandであるべき: multiplier=\(s.demandMultiplier)")
    }

    func testNonHolidayJanuaryHasNoSeasonMultiplier() {
        // 1/10 は年末年始(1/4まで)を過ぎており、季節イベントなし
        let midJan = date(year: 2026, month: 1, day: 10)
        let suggestions = service.generateSuggestions(
            from: [],
            basePrice: basePrice,
            minPrice: 0,
            maxPrice: Int.max,
            startDate: midJan,
            days: 1
        )
        let s = try! XCTUnwrap(suggestions.first)
        // 季節係数が1.0のため合算倍率は曜日係数 x 稼働率補正のみ
        // 最大でも 1.3(土) x 1.05(稼働率デフォルト) = 1.365 程度
        XCTAssertLessThan(s.demandMultiplier, 1.5,
            "平常1月の需要倍率は1.5未満であるべき: \(s.demandMultiplier)")
    }

    // MARK: - 曜日係数: 金土は平日より高い

    func testFridaySaturdayHigherThanWeekday() {
        // 2026-03-23 = 月曜, 2026-03-27 = 金曜, 2026-03-28 = 土曜
        // 季節イベントなし期間で比較
        let monday   = date(year: 2026, month: 3, day: 23)
        let friday   = date(year: 2026, month: 3, day: 27)
        let saturday = date(year: 2026, month: 3, day: 28)

        func multiplier(for d: Date) -> Double {
            service.generateSuggestions(
                from: [],
                basePrice: basePrice,
                minPrice: 0,
                maxPrice: Int.max,
                startDate: d,
                days: 1
            ).first!.demandMultiplier
        }

        let monMul = multiplier(for: monday)
        let friMul = multiplier(for: friday)
        let satMul = multiplier(for: saturday)

        XCTAssertGreaterThan(friMul, monMul,
            "金曜(\(friMul))は月曜(\(monMul))より高い需要倍率であるべき")
        XCTAssertGreaterThan(satMul, monMul,
            "土曜(\(satMul))は月曜(\(monMul))より高い需要倍率であるべき")
        XCTAssertGreaterThanOrEqual(satMul, friMul,
            "土曜(\(satMul))は金曜(\(friMul))以上であるべき")
    }

    func testMondayTuesdayLowestWeekdays() {
        // 月曜・火曜の係数(0.85)は他の平日より低い
        let monday  = date(year: 2026, month: 3, day: 23)
        let tuesday = date(year: 2026, month: 3, day: 24)
        let thursday = date(year: 2026, month: 3, day: 26)

        func multiplier(for d: Date) -> Double {
            service.generateSuggestions(
                from: [],
                basePrice: basePrice,
                minPrice: 0,
                maxPrice: Int.max,
                startDate: d,
                days: 1
            ).first!.demandMultiplier
        }

        XCTAssertLessThanOrEqual(multiplier(for: monday), multiplier(for: thursday))
        XCTAssertLessThanOrEqual(multiplier(for: tuesday), multiplier(for: thursday))
    }

    // MARK: - 推奨価格が min/max 範囲内

    func testSuggestedPriceWithinMinMax() {
        let startDate = date(year: 2026, month: 1, day: 1)
        let suggestions = service.generateSuggestions(
            from: [],
            basePrice: basePrice,
            minPrice: minPrice,
            maxPrice: maxPrice,
            startDate: startDate,
            days: 60
        )

        XCTAssertEqual(suggestions.count, 60)
        for s in suggestions {
            XCTAssertGreaterThanOrEqual(s.suggestedPrice, minPrice,
                "推奨価格 \(s.suggestedPrice) が最低価格 \(minPrice) を下回っている: \(s.date)")
            XCTAssertLessThanOrEqual(s.suggestedPrice, maxPrice,
                "推奨価格 \(s.suggestedPrice) が最高価格 \(maxPrice) を超えている: \(s.date)")
        }
    }

    func testMaxPriceClampDuringPeakSeason() {
        // GW x 土曜: 最も高い倍率でも maxPrice にクランプされる
        let gwSaturday = date(year: 2026, month: 5, day: 2) // 土曜
        let suggestions = service.generateSuggestions(
            from: [],
            basePrice: basePrice,
            minPrice: minPrice,
            maxPrice: 12_000,  // 厳しい上限
            startDate: gwSaturday,
            days: 1
        )
        let s = try! XCTUnwrap(suggestions.first)
        XCTAssertLessThanOrEqual(s.suggestedPrice, 12_000)
    }

    func testMinPriceClampDuringOffSeason() {
        // 月曜の閑散期: basePrice x 低倍率でも minPrice を下回らない
        let monday = date(year: 2026, month: 6, day: 1)
        let suggestions = service.generateSuggestions(
            from: [],
            basePrice: 1_000,      // 非常に低いベース価格
            minPrice: 5_000,       // 高い最低価格
            maxPrice: 50_000,
            startDate: monday,
            days: 1
        )
        let s = try! XCTUnwrap(suggestions.first)
        XCTAssertGreaterThanOrEqual(s.suggestedPrice, 5_000)
    }

    // MARK: - 空の予約データでクラッシュしない

    func testEmptyBookingsDoesNotCrash() {
        let suggestions = service.generateSuggestions(
            from: [],
            basePrice: basePrice,
            minPrice: minPrice,
            maxPrice: maxPrice,
            days: 60
        )
        XCTAssertEqual(suggestions.count, 60)
        // 全てのサジェストが有効な値を持つ
        for s in suggestions {
            XCTAssertFalse(s.demandLabel.isEmpty)
            XCTAssertGreaterThan(s.basePrice, 0)
            XCTAssertGreaterThan(s.demandMultiplier, 0)
        }
    }

    func testZeroDaysReturnsEmpty() {
        let suggestions = service.generateSuggestions(
            from: [],
            basePrice: basePrice,
            minPrice: minPrice,
            maxPrice: maxPrice,
            days: 0
        )
        XCTAssertTrue(suggestions.isEmpty)
    }

    func testWeeklyOccupancyWithEmptyBookings() {
        let result = service.weeklyOccupancy(from: [], weeks: 12)
        XCTAssertEqual(result.count, 12)
        for week in result {
            XCTAssertEqual(week.rate, 0.0)
        }
    }

    // MARK: - DemandLabel ロジック

    func testDemandLabelForHighMultiplier() {
        // GW期間(x1.8) x 土曜(x1.3) で "最繁忙" になる
        let gwSat = date(year: 2026, month: 5, day: 2)
        let suggestions = service.generateSuggestions(
            from: [],
            basePrice: basePrice,
            minPrice: 0,
            maxPrice: Int.max,
            startDate: gwSat,
            days: 1
        )
        let s = try! XCTUnwrap(suggestions.first)
        XCTAssertEqual(s.demandLabel, "最繁忙",
            "GW土曜は '最繁忙' であるべき: multiplier=\(s.demandMultiplier)")
    }

    func testDemandLabelForLowMultiplier() {
        // 月曜の通常期: 閑散期 or 通常
        let monday = date(year: 2026, month: 6, day: 1)
        let suggestions = service.generateSuggestions(
            from: [],
            basePrice: basePrice,
            minPrice: 0,
            maxPrice: Int.max,
            startDate: monday,
            days: 1
        )
        let s = try! XCTUnwrap(suggestions.first)
        XCTAssertTrue(["閑散期", "通常"].contains(s.demandLabel),
            "月曜通常期は '閑散期' か '通常' であるべき: \(s.demandLabel)")
    }

    // MARK: - 過去予約データからの稼働率反映

    func testHistoricalBookingsAffectMultiplier() {
        // 金曜に多数の予約がある場合、需要倍率が上昇する
        let cal = Calendar.current
        var bookings: [Beds24Booking] = []

        // 過去12ヶ月の毎週金曜に予約を追加
        for week in 0..<20 {
            guard let friday = cal.date(byAdding: .weekOfYear, value: -week,
                                        to: date(year: 2026, month: 3, day: 27)) else { continue }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let arrStr = formatter.string(from: friday)
            let dep = cal.date(byAdding: .day, value: 1, to: friday)!
            let depStr = formatter.string(from: dep)
            bookings.append(Beds24Booking(
                id: week,
                propertyId: nil, roomId: nil,
                status: "confirmed",
                arrival: arrStr,
                departure: depStr,
                firstName: "Test", lastName: nil,
                email: nil, phone: nil,
                numAdult: 2, numChild: nil,
                price: 10000, commission: nil,
                referer: nil, channel: nil,
                apiReference: nil, comments: nil, notes: nil
            ))
        }

        // 予約なしバージョンと比較
        let withHistory = service.generateSuggestions(
            from: bookings,
            basePrice: basePrice,
            minPrice: 0,
            maxPrice: Int.max,
            startDate: date(year: 2026, month: 4, day: 3), // 金曜
            days: 1
        ).first!

        let withoutHistory = service.generateSuggestions(
            from: [],
            basePrice: basePrice,
            minPrice: 0,
            maxPrice: Int.max,
            startDate: date(year: 2026, month: 4, day: 3),
            days: 1
        ).first!

        XCTAssertGreaterThanOrEqual(withHistory.demandMultiplier, withoutHistory.demandMultiplier,
            "高稼働率履歴あり(\(withHistory.demandMultiplier)) >= なし(\(withoutHistory.demandMultiplier))")
    }
}
