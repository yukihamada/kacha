import WidgetKit
import SwiftUI

// MARK: - Entry View (dispatcher)

struct KachaWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: KachaWidgetEntry

    var body: some View {
        if entry.isUnconfigured {
            KachaUnconfiguredView()
        } else {
            switch family {
            case .systemSmall:
                KachaSmallView(entry: entry)
            case .systemMedium:
                KachaMediumView(entry: entry)
            case .systemLarge:
                KachaLargeView(entry: entry)
            default:
                KachaSmallView(entry: entry)
            }
        }
    }
}

// MARK: - Widget bundle

@main
struct KachaWidgetBundle: WidgetBundle {
    var body: some Widget {
        KachaMainWidget()
    }
}

// MARK: - Main widget

struct KachaMainWidget: Widget {
    let kind = "KachaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KachaWidgetProvider()) { entry in
            KachaWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.039, green: 0.039, blue: 0.071),
                            Color(red: 0.102, green: 0.102, blue: 0.180)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("KAGI")
        .description("施錠状態・次のゲスト・今日の予約をひと目で確認。ウィジェットから直接施錠/解錠できます。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
