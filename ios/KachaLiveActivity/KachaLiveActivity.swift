import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Design tokens

private let goldAccent   = Color(red: 0.91, green: 0.66, blue: 0.22)   // #E8A838
private let darkBg       = Color(red: 0.04, green: 0.04, blue: 0.07)   // #0A0A12
private let lockedColor  = Color(red: 0.95, green: 0.30, blue: 0.25)   // red
private let unlockedColor = Color(red: 0.27, green: 0.82, blue: 0.49)  // green

// MARK: - Helper views

@available(iOS 16.1, *)
private struct LockIcon: View {
    let isLocked: Bool
    let size: Font

    var body: some View {
        Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
            .font(size)
            .foregroundStyle(isLocked ? lockedColor : unlockedColor)
    }
}

@available(iOS 16.1, *)
private struct BatteryView: View {
    let level: Int

    private var color: Color {
        switch level {
        case ..<20: return .red
        case ..<50: return goldAccent
        default:    return unlockedColor
        }
    }

    var body: some View {
        if level >= 0 {
            HStack(spacing: 2) {
                Image(systemName: batteryIcon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text("\(level)%")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(color)
            }
        }
    }

    private var batteryIcon: String {
        switch level {
        case ..<20: return "battery.0percent"
        case ..<50: return "battery.25percent"
        case ..<75: return "battery.50percent"
        default:    return "battery.100percent"
        }
    }
}

// MARK: - Lock Screen view

@available(iOS 16.1, *)
struct KachaLockScreenView: View {
    let attributes: KachaLockAttributes
    let state: KachaLockAttributes.ContentState

    var body: some View {
        ZStack {
            darkBg
            VStack(spacing: 12) {

                // 施錠状態メインアイコン
                ZStack {
                    Circle()
                        .fill(state.isLocked ? lockedColor.opacity(0.15) : unlockedColor.opacity(0.15))
                        .frame(width: 64, height: 64)
                    LockIcon(isLocked: state.isLocked, size: .system(size: 28, weight: .medium))
                }

                // 状態テキスト + 家名
                VStack(spacing: 4) {
                    Text(state.isLocked ? "施錠中" : "解錠中")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(state.isLocked ? lockedColor : unlockedColor)

                    Text(attributes.homeName)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Divider()
                    .background(.white.opacity(0.1))

                // 次ゲスト情報 + バッテリー
                HStack {
                    if let guestName = state.nextGuestName,
                       let checkIn = state.nextCheckIn {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill")
                                    .font(.caption2)
                                    .foregroundStyle(goldAccent)
                                Text(guestName)
                                    .font(.system(.caption, design: .rounded).weight(.medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.4))
                                Text(checkIn, style: .timer)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(goldAccent)
                                Text("後にチェックイン")
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "moon.zzz.fill")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.3))
                            Text("予約なし")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }

                    Spacer()
                    BatteryView(level: state.batteryLevel)
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Dynamic Island views

// Compact leading (小さなアイコン)
@available(iOS 16.1, *)
struct KachaCompactLeadingView: View {
    let state: KachaLockAttributes.ContentState

    var body: some View {
        LockIcon(isLocked: state.isLocked, size: .system(size: 14, weight: .medium))
            .padding(.leading, 4)
    }
}

// Compact trailing (家名)
@available(iOS 16.1, *)
struct KachaCompactTrailingView: View {
    let attributes: KachaLockAttributes
    let state: KachaLockAttributes.ContentState

    var body: some View {
        Text(attributes.homeName)
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundStyle(state.isLocked ? lockedColor : unlockedColor)
            .lineLimit(1)
            .padding(.trailing, 4)
    }
}

// Minimal (最小: 鍵アイコンのみ)
@available(iOS 16.1, *)
struct KachaMinimalView: View {
    let state: KachaLockAttributes.ContentState

    var body: some View {
        LockIcon(isLocked: state.isLocked, size: .caption)
    }
}

// Expanded (展開: フル情報)
@available(iOS 16.1, *)
struct KachaExpandedView: View {
    let attributes: KachaLockAttributes
    let state: KachaLockAttributes.ContentState

    var body: some View {
        VStack(spacing: 10) {

            // 上段: アイコン + 状態 + バッテリー
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(state.isLocked ? lockedColor.opacity(0.2) : unlockedColor.opacity(0.2))
                        .frame(width: 44, height: 44)
                    LockIcon(isLocked: state.isLocked, size: .system(size: 20, weight: .medium))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.isLocked ? "施錠中" : "解錠中")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(state.isLocked ? lockedColor : unlockedColor)
                    Text(attributes.homeName)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()
                BatteryView(level: state.batteryLevel)
            }

            // 下段: 次ゲスト or カウントダウン
            if let guestName = state.nextGuestName,
               let checkIn = state.nextCheckIn {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.caption2)
                                .foregroundStyle(goldAccent)
                            Text(guestName)
                                .font(.system(.caption, design: .rounded).weight(.medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.4))
                            Text(checkIn, style: .timer)
                                .font(.system(.caption2, design: .rounded).monospacedDigit())
                                .foregroundStyle(goldAccent)
                            Text("後")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    Spacer()

                    // 解錠ボタン（DeepLink経由でアプリに渡す）
                    if state.isLocked {
                        Link(destination: URL(string: "kacha://unlock?homeId=\(attributes.homeId)")!) {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.open.fill")
                                    .font(.caption2.weight(.semibold))
                                Text("解錠")
                                    .font(.system(.caption, design: .rounded).weight(.semibold))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(goldAccent, in: Capsule())
                        }
                    }
                }
            } else {
                HStack {
                    Image(systemName: "moon.zzz.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                    Text("次の予約はありません")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Widget definition

@available(iOS 16.1, *)
struct KachaLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KachaLockAttributes.self) { context in
            // Lock Screen / Notification Center
            KachaLockScreenView(
                attributes: context.attributes,
                state: context.state
            )
            .activityBackgroundTint(Color(red: 0.04, green: 0.04, blue: 0.07))
            .activitySystemActionForegroundColor(goldAccent)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.center) {
                    KachaExpandedView(
                        attributes: context.attributes,
                        state: context.state
                    )
                }
            } compactLeading: {
                KachaCompactLeadingView(state: context.state)
            } compactTrailing: {
                KachaCompactTrailingView(
                    attributes: context.attributes,
                    state: context.state
                )
            } minimal: {
                KachaMinimalView(state: context.state)
            }
            .keylineTint(context.state.isLocked ? lockedColor : unlockedColor)
            .contentMargins(.horizontal, 12, for: .expanded)
            .contentMargins(.all, 8, for: .compactLeading)
        }
    }
}
