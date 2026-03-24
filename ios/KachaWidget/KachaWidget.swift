import WidgetKit
import SwiftUI

// MARK: - Data Model

struct KachaWidgetEntry: TimelineEntry {
    let date: Date
    let todayCheckIns: Int
    let todayCheckOuts: Int
    let isLocked: Bool
    let monthNights: Int
    let upcomingBookings: [(String, String, String)]  // (guestName, checkIn, platform)
}

// MARK: - Provider

struct KachaProvider: TimelineProvider {
    private let suiteName = "group.com.enablerdao.kacha"

    func placeholder(in context: Context) -> KachaWidgetEntry {
        KachaWidgetEntry(
            date: Date(),
            todayCheckIns: 2,
            todayCheckOuts: 1,
            isLocked: true,
            monthNights: 12,
            upcomingBookings: [
                ("田中 様", "16:00 チェックイン", "Airbnb"),
                ("山田 様", "10:00 チェックアウト", "じゃらん")
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (KachaWidgetEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KachaWidgetEntry>) -> Void) {
        let entry = loadEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry() -> KachaWidgetEntry {
        let defaults = UserDefaults(suiteName: suiteName)
        let checkIns = defaults?.integer(forKey: "widget_today_checkins") ?? 0
        let checkOuts = defaults?.integer(forKey: "widget_today_checkouts") ?? 0
        let isLocked = defaults?.bool(forKey: "widget_is_locked") ?? true
        let monthNights = defaults?.integer(forKey: "widget_month_nights") ?? 0

        var upcoming: [(String, String, String)] = []
        if let data = defaults?.data(forKey: "widget_upcoming_bookings"),
           let decoded = try? JSONDecoder().decode([BookingItem].self, from: data) {
            upcoming = decoded.map { ($0.guestName, $0.timeLabel, $0.platform) }
        }

        return KachaWidgetEntry(
            date: Date(),
            todayCheckIns: checkIns,
            todayCheckOuts: checkOuts,
            isLocked: isLocked,
            monthNights: monthNights,
            upcomingBookings: upcoming
        )
    }
}

private struct BookingItem: Codable {
    let guestName: String
    let timeLabel: String
    let platform: String
}

// MARK: - Views

private let amberAccent = Color(red: 1.0, green: 0.75, blue: 0.1)
private let darkBg = Color(red: 0.06, green: 0.06, blue: 0.09)

struct KachaSmallView: View {
    let entry: KachaWidgetEntry

    var body: some View {
        ZStack {
            darkBg
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "house.fill")
                        .font(.caption2)
                        .foregroundStyle(amberAccent)
                    Text("カチャ")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Image(systemName: entry.isLocked ? "lock.fill" : "lock.open.fill")
                        .font(.caption2)
                        .foregroundStyle(entry.isLocked ? amberAccent : .green)
                }

                Spacer()

                Text("今日のスケジュール")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text("\(entry.todayCheckIns)")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        Text("チェックイン")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.left.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(amberAccent)
                            Text("\(entry.todayCheckOuts)")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        Text("チェックアウト")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Text("今月 \(entry.monthNights)/180泊")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(14)
        }
    }
}

struct KachaMediumView: View {
    let entry: KachaWidgetEntry

    private var minpakuRatio: Double {
        min(1.0, Double(entry.monthNights) / 180.0)
    }

    var body: some View {
        ZStack {
            darkBg
            HStack(spacing: 0) {
                // Left column
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "house.fill")
                            .font(.caption2)
                            .foregroundStyle(amberAccent)
                        Text("カチャ")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Image(systemName: entry.isLocked ? "lock.fill" : "lock.open.fill")
                            .font(.caption2)
                            .foregroundStyle(entry.isLocked ? amberAccent : .green)
                        Text(entry.isLocked ? "施錠中" : "解錠中")
                            .font(.caption2)
                            .foregroundStyle(entry.isLocked ? amberAccent : .green)
                    }

                    Spacer()

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                                Text("\(entry.todayCheckIns)")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                            Text("IN")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.left.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(amberAccent)
                                Text("\(entry.todayCheckOuts)")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                            Text("OUT")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("今月 \(entry.monthNights)泊 / 180泊")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            Text("\(Int(minpakuRatio * 100))%")
                                .font(.caption2)
                                .foregroundStyle(minpakuRatio >= 0.9 ? .red : amberAccent)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.white.opacity(0.1))
                                    .frame(height: 3)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(minpakuRatio >= 0.9 ? Color.red : amberAccent)
                                    .frame(width: geo.size.width * minpakuRatio, height: 3)
                            }
                        }
                        .frame(height: 3)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(14)

                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1)

                // Right column: upcoming bookings
                VStack(alignment: .leading, spacing: 0) {
                    Text("今日の予定")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.bottom, 6)

                    if entry.upcomingBookings.isEmpty {
                        Spacer()
                        Text("予定なし")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.3))
                        Spacer()
                    } else {
                        ForEach(Array(entry.upcomingBookings.prefix(3).enumerated()), id: \.offset) { _, booking in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(booking.0)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                HStack {
                                    Text(booking.1)
                                        .font(.caption2)
                                        .foregroundStyle(amberAccent)
                                    Spacer()
                                    Text(booking.2)
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(14)
            }
        }
    }
}

// MARK: - Widget

@main
struct KachaWidget: Widget {
    let kind = "KachaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KachaProvider()) { entry in
            KachaWidgetEntryView(entry: entry)
                .containerBackground(darkBg, for: .widget)
        }
        .configurationDisplayName("カチャ")
        .description("今日のチェックイン/アウトと施錠状態")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct KachaWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: KachaWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            KachaSmallView(entry: entry)
        case .systemMedium:
            KachaMediumView(entry: entry)
        default:
            KachaSmallView(entry: entry)
        }
    }
}
