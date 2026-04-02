import Foundation
import SwiftData

/// Analyzes past sent messages and generates 3 reply suggestions
/// based on the incoming guest message context.
struct ReplySuggestionService {

    /// Categorize an incoming guest message by keywords.
    static func categorize(_ message: String) -> String {
        let lower = message.lowercased()

        // Check-in related
        if lower.contains("チェックイン") || lower.contains("check in") || lower.contains("到着")
            || lower.contains("何時") || lower.contains("アクセス") || lower.contains("行き方")
            || lower.contains("場所") || lower.contains("住所") || lower.contains("道")
        {
            return "checkin"
        }

        // Wi-Fi related
        if lower.contains("wifi") || lower.contains("wi-fi") || lower.contains("ネット")
            || lower.contains("インターネット") || lower.contains("パスワード")
        {
            return "wifi"
        }

        // Check-out related
        if lower.contains("チェックアウト") || lower.contains("check out") || lower.contains("checkout")
            || lower.contains("退室") || lower.contains("鍵") || lower.contains("返却")
        {
            return "checkout"
        }

        // Trouble / issue
        if lower.contains("故障") || lower.contains("壊れ") || lower.contains("動かない")
            || lower.contains("使えない") || lower.contains("困って") || lower.contains("問題")
            || lower.contains("トラブル") || lower.contains("broken") || lower.contains("not work")
            || lower.contains("エアコン") || lower.contains("お湯") || lower.contains("シャワー")
        {
            return "trouble"
        }

        // Thanks / positive
        if lower.contains("ありがとう") || lower.contains("thank") || lower.contains("素晴らしい")
            || lower.contains("良かった") || lower.contains("最高") || lower.contains("great")
            || lower.contains("wonderful") || lower.contains("amazing")
        {
            return "thanks"
        }

        // Late arrival
        if lower.contains("遅れ") || lower.contains("遅く") || lower.contains("late")
            || lower.contains("delay")
        {
            return "late"
        }

        return "general"
    }

    /// Generate 3 reply suggestions based on past sent messages and the incoming message.
    static func suggest(
        incomingMessage: String,
        guestName: String,
        booking: (checkIn: Date, checkOut: Date, nights: Int),
        pastMessages: [SentMessage]
    ) -> [ReplySuggestion] {
        let category = categorize(incomingMessage)

        // Find past replies in the same category
        let sameCategoryReplies = pastMessages
            .filter { $0.category == category }
            .sorted { $0.sentAt > $1.sentAt }

        // If we have past replies, adapt them
        if sameCategoryReplies.count >= 2 {
            return buildFromHistory(sameCategoryReplies, guestName: guestName, category: category)
        }

        // Fall back to default templates
        return defaultSuggestions(category: category, guestName: guestName, booking: booking)
    }

    // MARK: - Build from history

    private static func buildFromHistory(
        _ pastReplies: [SentMessage],
        guestName: String,
        category: String
    ) -> [ReplySuggestion] {
        // Take up to 3 unique past replies, replacing guest names
        var seen = Set<String>()
        var suggestions: [ReplySuggestion] = []

        for reply in pastReplies {
            // Normalize: replace old guest name with current guest name
            let adapted = reply.text
                .replacingOccurrences(of: reply.guestName, with: guestName)

            let normalized = adapted.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = String(normalized.prefix(50))
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            let label: String
            switch suggestions.count {
            case 0: label = "前回と同じ返信"
            case 1: label = "別パターン"
            default: label = "簡潔な返信"
            }

            suggestions.append(ReplySuggestion(
                label: label,
                text: normalized,
                category: category,
                source: .history
            ))

            if suggestions.count >= 3 { break }
        }

        // Fill remaining slots with defaults if needed
        if suggestions.count < 3 {
            let defaults = defaultSuggestionsForCategory(category, guestName: guestName)
            for d in defaults {
                if suggestions.count >= 3 { break }
                let key = String(d.text.prefix(50))
                if !seen.contains(key) {
                    suggestions.append(d)
                    seen.insert(key)
                }
            }
        }

        return Array(suggestions.prefix(3))
    }

    // MARK: - Default templates

    private static func defaultSuggestions(
        category: String,
        guestName: String,
        booking: (checkIn: Date, checkOut: Date, nights: Int)
    ) -> [ReplySuggestion] {
        return defaultSuggestionsForCategory(category, guestName: guestName)
    }

    private static func defaultSuggestionsForCategory(
        _ category: String,
        guestName: String
    ) -> [ReplySuggestion] {
        switch category {
        case "checkin":
            return [
                ReplySuggestion(
                    label: "丁寧な案内",
                    text: "\(guestName) 様\n\nご連絡ありがとうございます。チェックインの詳細をお送りします。ドアのキーパッドにコードを入力して解錠してください。ご不明な点があればお気軽にどうぞ。",
                    category: category, source: .default
                ),
                ReplySuggestion(
                    label: "簡潔に",
                    text: "\(guestName) 様\n\nチェックイン情報をお送りしました。何かあればいつでもご連絡ください。",
                    category: category, source: .default
                ),
                ReplySuggestion(
                    label: "詳しく",
                    text: "\(guestName) 様\n\nお問い合わせありがとうございます。チェックインは15時以降となります。ドアコードは別途お送りいたします。アクセス方法についてもご案内できますので、お気軽にお問い合わせください。",
                    category: category, source: .default
                ),
            ]

        case "wifi":
            return [
                ReplySuggestion(
                    label: "Wi-Fi情報",
                    text: "\(guestName) 様\n\nWi-Fi情報をお知らせします。接続にお困りの場合はルーターの再起動をお試しください。それでも解決しない場合はご連絡ください。",
                    category: category, source: .default
                ),
                ReplySuggestion(
                    label: "簡潔に",
                    text: "\(guestName) 様\n\nWi-Fiパスワードをお送りします。お困りの際はご連絡ください。",
                    category: category, source: .default
                ),
                ReplySuggestion(
                    label: "トラブル対応",
                    text: "\(guestName) 様\n\nWi-Fiが繋がりにくい場合は、ルーター（リビングの白い箱）の電源を一度抜いて30秒後に差し直してみてください。改善しない場合はすぐに対応いたします。",
                    category: category, source: .default
                ),
            ]

        case "checkout":
            return [
                ReplySuggestion(
                    label: "お礼付き",
                    text: "\(guestName) 様\n\nご滞在ありがとうございました。チェックアウトの際はドアの施錠をお願いいたします。またのご利用をお待ちしております。",
                    category: category, source: .default
                ),
                ReplySuggestion(
                    label: "簡潔に",
                    text: "\(guestName) 様\n\nチェックアウトは11時までです。鍵の返却は不要です。ありがとうございました。",
                    category: category, source: .default
                ),
                ReplySuggestion(
                    label: "詳しく",
                    text: "\(guestName) 様\n\nチェックアウトのご案内です。お帰りの際は窓の施錠、エアコンのOFF、ゴミの分別をお願いします。忘れ物がございましたらご連絡ください。",
                    category: category, source: .default
                ),
            ]

        case "trouble":
            return [
                ReplySuggestion(
                    label: "迅速対応",
                    text: "\(guestName) 様\n\nご不便をおかけして申し訳ございません。すぐに確認いたします。状況を詳しく教えていただけますか？",
                    category: category, source: .default
                ),
                ReplySuggestion(
                    label: "対処法提案",
                    text: "\(guestName) 様\n\nご連絡ありがとうございます。まずは電源の入れ直しをお試しいただけますか？それでも改善しない場合は、スタッフが対応に伺います。",
                    category: category, source: .default
                ),
                ReplySuggestion(
                    label: "訪問対応",
                    text: "\(guestName) 様\n\n大変申し訳ございません。スタッフが確認に伺いますので、ご都合の良い時間を教えていただけますか？",
                    category: category, source: .default
                ),
            ]

        case "thanks":
            return [
                ReplySuggestion(
                    label: "お礼返し",
                    text: "\(guestName) 様\n\n嬉しいお言葉ありがとうございます！快適にお過ごしいただけて何よりです。引き続き素敵なご滞在をお楽しみください。",
                    category: category, source: .default
                ),
                ReplySuggestion(
                    label: "簡潔に",
                    text: "\(guestName) 様\n\nありがとうございます！何かあればいつでもご連絡ください。",
                    category: category, source: .default
                ),
                ReplySuggestion(
                    label: "レビューお願い",
                    text: "\(guestName) 様\n\nありがとうございます！よろしければレビューを書いていただけると嬉しいです。またのご利用を心よりお待ちしております。",
                    category: category, source: .default
                ),
            ]

        case "late":
            return [
                ReplySuggestion(
                    label: "柔軟対応",
                    text: "\(guestName) 様\n\nご連絡ありがとうございます。遅い時間でも問題ございません。スマートロックですので、いつでもチェックインいただけます。お気をつけてお越しください。",
                    category: category, source: .default
                ),
                ReplySuggestion(
                    label: "簡潔に",
                    text: "\(guestName) 様\n\n承知しました。お気をつけてお越しください。",
                    category: category, source: .default
                ),
                ReplySuggestion(
                    label: "注意事項付き",
                    text: "\(guestName) 様\n\n承知しました。22時以降は共用部のお静かにお願いいたします。ドアコードはそのままお使いいただけます。",
                    category: category, source: .default
                ),
            ]

        default: // general
            return [
                ReplySuggestion(
                    label: "丁寧に",
                    text: "\(guestName) 様\n\nご連絡ありがとうございます。ご質問について確認いたします。少々お待ちください。",
                    category: category, source: .default
                ),
                ReplySuggestion(
                    label: "簡潔に",
                    text: "\(guestName) 様\n\n承知しました。確認して折り返しご連絡いたします。",
                    category: category, source: .default
                ),
                ReplySuggestion(
                    label: "即答",
                    text: "\(guestName) 様\n\nお問い合わせありがとうございます。何かお困りのことがあればお気軽にご連絡ください。",
                    category: category, source: .default
                ),
            ]
        }
    }
}

// MARK: - Suggestion Model

struct ReplySuggestion: Identifiable {
    let id = UUID()
    let label: String
    let text: String
    let category: String
    let source: Source

    enum Source {
        case history  // based on past replies
        case `default`  // template fallback
        case ai       // generated by Gemini AI
    }
}
