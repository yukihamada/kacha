import SwiftUI
import WidgetKit

// MARK: - Design tokens

private enum KW {
    static let bgDark   = Color(red: 0.039, green: 0.039, blue: 0.071)   // #0A0A12
    static let bgMid    = Color(red: 0.102, green: 0.102, blue: 0.180)   // #1A1A2E
    static let gold     = Color(red: 0.910, green: 0.659, blue: 0.220)   // #E8A838
    static let blue     = Color(red: 0.231, green: 0.624, blue: 0.910)   // #3B9FE8
    static let red      = Color(red: 0.937, green: 0.267, blue: 0.267)   // #EF4444
    static let green    = Color(red: 0.063, green: 0.725, blue: 0.506)   // #10B981
    static let glass    = Color.white.opacity(0.06)
    static let glassStroke = Color.white.opacity(0.10)
    static let textPrimary = Color.white
    static let textMuted = Color.white.opacity(0.45)

    static func lockColor(isLocked: Bool) -> Color { isLocked ? red : green }
    static func lockIcon(isLocked: Bool) -> String { isLocked ? "lock.fill" : "lock.open.fill" }
    static func lockLabel(isLocked: Bool) -> String { isLocked ? "施錠中" : "解錠中" }
    static func toggleLabel(isLocked: Bool) -> String { isLocked ? "タップで解錠" : "タップで施錠" }
}

// MARK: - Background gradient

struct WidgetBackground: View {
    var body: some View {
        LinearGradient(
            colors: [KW.bgDark, KW.bgMid],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Lock status badge

struct LockBadge: View {
    let isLocked: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(KW.lockColor(isLocked: isLocked).opacity(0.18))
                .frame(width: size, height: size)
            Circle()
                .strokeBorder(KW.lockColor(isLocked: isLocked).opacity(0.4), lineWidth: 1.5)
                .frame(width: size, height: size)
            Image(systemName: KW.lockIcon(isLocked: isLocked))
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(KW.lockColor(isLocked: isLocked))
        }
    }
}

// MARK: - Countdown label

struct CountdownLabel: View {
    let checkInDate: Date?

    var text: String {
        guard let date = checkInDate, date > Date() else { return "" }
        let minutes = Int(date.timeIntervalSinceNow / 60)
        if minutes < 60 { return "\(minutes)分後" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)時間後" }
        return "\(hours / 24)日後"
    }

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(KW.gold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(KW.gold.opacity(0.15), in: Capsule())
        }
    }
}

// MARK: - Glass card

struct GlassCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(10)
            .background(KW.glass)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(KW.glassStroke, lineWidth: 1)
            )
    }
}

// MARK: - Platform dot

struct PlatformDot: View {
    let platform: String

    var color: Color {
        switch platform.lowercased() {
        case "airbnb":      return Color(red: 1.0, green: 0.22, blue: 0.36)
        case "じゃらん":      return Color(red: 1.0, green: 0.5, blue: 0.0)
        case "booking.com": return Color(red: 0.01, green: 0.45, blue: 1.0)
        case "beds24":      return Color(red: 0.4, green: 0.8, blue: 0.4)
        default:            return KW.textMuted
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }
}

// MARK: - Minpaku progress bar

struct MinpakuProgressBar: View {
    let nights: Int
    let cap: Int = 180

    private var ratio: Double { min(1.0, Double(nights) / Double(cap)) }
    private var barColor: Color { ratio >= 0.9 ? KW.red : KW.gold }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("今月 \(nights) / \(cap)泊")
                    .font(.caption2)
                    .foregroundStyle(KW.textMuted)
                Spacer()
                Text("\(Int(ratio * 100))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(barColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: geo.size.width * ratio, height: 3)
                }
            }
            .frame(height: 3)
        }
    }
}

// MARK: - Booking row

struct BookingRow: View {
    let item: BookingItem

    var body: some View {
        HStack(spacing: 6) {
            PlatformDot(platform: item.platform)
            Text(item.guestName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(KW.textPrimary)
                .lineLimit(1)
            Spacer()
            Text(item.timeLabel)
                .font(.caption2)
                .foregroundStyle(KW.gold)
                .lineLimit(1)
        }
    }
}

// MARK: - Small Widget View

struct KachaSmallView: View {
    let entry: KachaWidgetEntry

    private var occupiedCount: Int { entry.propertyCount - entry.vacantCount }

    var body: some View {
        ZStack {
            WidgetBackground()
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 5) {
                    Image(systemName: "house.fill")
                        .font(.caption2)
                        .foregroundStyle(KW.gold)
                    Text("KAGI")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(KW.textMuted)
                    Spacer()
                    // Lock status indicator
                    Image(systemName: KW.lockIcon(isLocked: entry.isLocked))
                        .font(.caption2)
                        .foregroundStyle(KW.lockColor(isLocked: entry.isLocked))
                }

                Spacer()

                // Stats grid: 3 metrics
                HStack(spacing: 8) {
                    // Property count
                    SmallStatItem(
                        value: "\(entry.propertyCount)",
                        label: "物件",
                        icon: "building.2.fill",
                        color: KW.blue
                    )
                    // Today's check-ins
                    SmallStatItem(
                        value: "\(entry.todayCheckIns)",
                        label: "IN",
                        icon: "arrow.right.circle.fill",
                        color: KW.green
                    )
                    // Vacancy
                    SmallStatItem(
                        value: "\(entry.vacantCount)",
                        label: "空室",
                        icon: "checkmark.circle.fill",
                        color: KW.green
                    )
                }

                Spacer()

                // Bottom: check-out count + occupancy bar
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(KW.gold)
                    Text("OUT \(entry.todayCheckOuts)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(KW.gold)
                    Spacer()
                    if entry.propertyCount > 0 {
                        Text("稼働 \(occupiedCount)/\(entry.propertyCount)")
                            .font(.caption2)
                            .foregroundStyle(KW.textMuted)
                    }
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Small stat item

private struct SmallStatItem: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(KW.textPrimary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(KW.textMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Medium Widget View

struct KachaMediumView: View {
    let entry: KachaWidgetEntry

    private var occupiedCount: Int { entry.propertyCount - entry.vacantCount }

    var body: some View {
        ZStack {
            WidgetBackground()
            HStack(spacing: 0) {
                // Left: summary stats + lock
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "house.fill")
                            .font(.caption2)
                            .foregroundStyle(KW.gold)
                        Text("KAGI")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(KW.textMuted)
                        Spacer()
                        Button(intent: LockToggleIntent()) {
                            HStack(spacing: 4) {
                                Image(systemName: KW.lockIcon(isLocked: entry.isLocked))
                                    .font(.caption2)
                                Text(KW.lockLabel(isLocked: entry.isLocked))
                                    .font(.caption2.weight(.medium))
                            }
                            .foregroundStyle(KW.lockColor(isLocked: entry.isLocked))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Stats: property / check-in / check-out / vacancy
                    HStack(spacing: 6) {
                        MediumStatPill(value: "\(entry.propertyCount)", label: "物件", color: KW.blue)
                        MediumStatPill(value: "\(entry.todayCheckIns)", label: "IN", color: KW.green)
                        MediumStatPill(value: "\(entry.todayCheckOuts)", label: "OUT", color: KW.gold)
                        MediumStatPill(value: "\(entry.vacantCount)", label: "空室", color: KW.green)
                    }

                    Spacer()

                    MinpakuProgressBar(nights: entry.monthNights)
                }
                .frame(maxWidth: .infinity)
                .padding(14)

                // Divider
                Rectangle()
                    .fill(KW.glassStroke)
                    .frame(width: 1)

                // Right: today's events list
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日のイベント")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(KW.textMuted)
                        .padding(.bottom, 2)

                    if entry.todayEvents.isEmpty {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(spacing: 4) {
                                Image(systemName: "checkmark.circle")
                                    .font(.title3)
                                    .foregroundStyle(KW.green.opacity(0.5))
                                Text("予定なし")
                                    .font(.caption2)
                                    .foregroundStyle(KW.textMuted)
                            }
                            Spacer()
                        }
                        Spacer()
                    } else {
                        ForEach(Array(entry.todayEvents.prefix(4).enumerated()), id: \.offset) { _, event in
                            TodayEventRow(event: event)
                        }
                        if entry.todayEvents.count > 4 {
                            Text("他 \(entry.todayEvents.count - 4) 件")
                                .font(.caption2)
                                .foregroundStyle(KW.textMuted)
                        }
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(14)
            }
        }
    }
}

// MARK: - Medium stat pill

private struct MediumStatPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(KW.textPrimary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(KW.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(KW.glass)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Today event row

private struct TodayEventRow: View {
    let event: TodayEvent

    private var isCheckIn: Bool { event.eventType == "checkin" }
    private var eventColor: Color { isCheckIn ? KW.green : KW.gold }
    private var eventIcon: String { isCheckIn ? "arrow.right.circle.fill" : "arrow.left.circle.fill" }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: eventIcon)
                .font(.system(size: 8))
                .foregroundStyle(eventColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.guestName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(KW.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Text(event.propertyName)
                        .font(.system(size: 9))
                        .foregroundStyle(KW.textMuted)
                        .lineLimit(1)
                    Text(event.time)
                        .font(.system(size: 9).weight(.medium))
                        .foregroundStyle(eventColor)
                }
            }
            Spacer()
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Large Widget View

struct KachaLargeView: View {
    let entry: KachaWidgetEntry

    var body: some View {
        ZStack {
            WidgetBackground()
            VStack(alignment: .leading, spacing: 12) {
                // Header row
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "house.fill")
                            .font(.subheadline)
                            .foregroundStyle(KW.gold)
                        Text(entry.homeName.isEmpty ? "KAGI" : entry.homeName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KW.textPrimary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(KW.lockColor(isLocked: entry.isLocked).opacity(0.8))
                            .frame(width: 7, height: 7)
                        Text(KW.lockLabel(isLocked: entry.isLocked))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(KW.lockColor(isLocked: entry.isLocked))
                    }
                }

                // Lock + quick actions row
                HStack(spacing: 12) {
                    // Lock toggle
                    Button(intent: LockToggleIntent()) {
                        GlassCard {
                            HStack(spacing: 10) {
                                LockBadge(isLocked: entry.isLocked, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(KW.lockLabel(isLocked: entry.isLocked))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(KW.lockColor(isLocked: entry.isLocked))
                                    Text(KW.toggleLabel(isLocked: entry.isLocked))
                                        .font(.caption2)
                                        .foregroundStyle(KW.textMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(KW.textMuted)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }

                // Stats row
                HStack(spacing: 8) {
                    StatTile(
                        icon: "building.2.fill",
                        value: "\(entry.propertyCount)",
                        label: "物件",
                        color: KW.blue
                    )
                    StatTile(
                        icon: "arrow.right.circle.fill",
                        value: "\(entry.todayCheckIns)",
                        label: "チェックイン",
                        color: KW.green
                    )
                    StatTile(
                        icon: "arrow.left.circle.fill",
                        value: "\(entry.todayCheckOuts)",
                        label: "チェックアウト",
                        color: KW.gold
                    )
                    StatTile(
                        icon: "checkmark.circle.fill",
                        value: "\(entry.vacantCount)",
                        label: "空室",
                        color: KW.green
                    )
                }

                // Minpaku bar
                MinpakuProgressBar(nights: entry.monthNights)

                // Divider
                Rectangle()
                    .fill(KW.glassStroke)
                    .frame(height: 1)

                // Today's schedule
                VStack(alignment: .leading, spacing: 6) {
                    Text("今日の予約")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KW.textMuted)

                    if entry.upcomingBookings.isEmpty {
                        Text("予定なし")
                            .font(.caption2)
                            .foregroundStyle(KW.textMuted)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(Array(entry.upcomingBookings.prefix(5).enumerated()), id: \.offset) { index, item in
                            if index == 0 {
                                // Highlight first entry
                                GlassCard {
                                    HStack(spacing: 8) {
                                        PlatformDot(platform: item.platform)
                                        Text(item.guestName)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(KW.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        CountdownLabel(checkInDate: entry.nextCheckInDate)
                                        Text(item.timeLabel)
                                            .font(.caption2)
                                            .foregroundStyle(KW.gold)
                                    }
                                }
                            } else {
                                BookingRow(item: item)
                                    .padding(.vertical, 1)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(16)
        }
    }
}

// MARK: - Stat tile

private struct StatTile: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        GlassCard {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 0) {
                    Text(value)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KW.textPrimary)
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(KW.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Unconfigured placeholder

struct KachaUnconfiguredView: View {
    var body: some View {
        ZStack {
            WidgetBackground()
            VStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(KW.gold)
                Text("KAGIアプリを開いて\n設定を完了してください")
                    .font(.caption2)
                    .foregroundStyle(KW.textMuted)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}
