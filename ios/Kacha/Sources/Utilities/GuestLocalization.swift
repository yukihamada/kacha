import Foundation

// MARK: - ゲスト向けメッセージ多言語化
// 対応言語: 日本語(ja) / 英語(en) / 中国語簡体字(zh) / 韓国語(ko)
//
// テンプレート変数:
//   {guestName}    — ゲスト氏名
//   {homeName}     — 物件名
//   {wifiSSID}     — Wi-Fi ネットワーク名
//   {wifiPassword} — Wi-Fi パスワード
//   {doorCode}     — ドアコード
//   {checkInTime}  — チェックイン日時
//   {checkOutTime} — チェックアウト日時
//
// TODO: 将来的に Booking モデルに `guestLanguage: String` を追加し、
//       予約ごとに言語を設定できるようにする。
//       現在はデフォルト "ja" を使用。

enum GuestLocalization {

    // MARK: - テンプレートキー

    enum TemplateKey: String, CaseIterable {
        case wifiGuide      = "wifi_guide"
        case doorCodeGuide  = "door_code_guide"
        case checkInGuide   = "check_in_guide"
        case checkOutGuide  = "check_out_guide"
    }

    // MARK: - テンプレート定義（言語別）

    /// 各テンプレートキーと言語コードに対応するメッセージ。
    /// 変数プレースホルダーは {変数名} 形式で埋め込む。
    private static let templates: [String: [String: String]] = [

        TemplateKey.checkInGuide.rawValue: [
            "ja": """
                {guestName}様

                明日のチェックインのご案内です。

                【{homeName}】
                チェックイン: {checkInTime}
                チェックアウト: {checkOutTime}

                ドアコード: {doorCode}

                Wi-Fi
                ネットワーク名: {wifiSSID}
                パスワード: {wifiPassword}

                ご不明な点はお気軽にご連絡ください。
                お待ちしております。
                """,

            "en": """
                Dear {guestName},

                Here is your check-in information for tomorrow.

                [{homeName}]
                Check-in:  {checkInTime}
                Check-out: {checkOutTime}

                Door Code: {doorCode}

                Wi-Fi
                Network: {wifiSSID}
                Password: {wifiPassword}

                Please feel free to contact us if you have any questions.
                We look forward to welcoming you!
                """,

            "zh": """
                尊敬的{guestName}，

                以下是您明天入住的相关信息。

                【{homeName}】
                入住时间：{checkInTime}
                退房时间：{checkOutTime}

                门锁密码：{doorCode}

                Wi-Fi
                网络名称：{wifiSSID}
                密码：{wifiPassword}

                如有任何疑问，请随时联系我们。
                期待您的到来！
                """,

            "ko": """
                안녕하세요, {guestName}님,

                내일 체크인 안내를 드립니다.

                [{homeName}]
                체크인: {checkInTime}
                체크아웃: {checkOutTime}

                도어 코드: {doorCode}

                Wi-Fi
                네트워크 이름: {wifiSSID}
                비밀번호: {wifiPassword}

                궁금하신 사항이 있으시면 언제든지 연락해 주세요.
                기다리겠습니다!
                """,
        ],

        TemplateKey.checkOutGuide.rawValue: [
            "ja": """
                {guestName}様

                チェックアウトのご案内です。

                【{homeName}】
                チェックアウト: {checkOutTime}

                - 鍵はドアの内側に置いてお出かけください
                - 照明・エアコンをお切りください

                またのご利用をお待ちしております。
                """,

            "en": """
                Dear {guestName},

                Check-out information for [{homeName}].

                Check-out: {checkOutTime}

                - Please leave the key inside on the door
                - Please turn off all lights and air conditioning

                We hope to see you again soon!
                """,

            "zh": """
                尊敬的{guestName}，

                以下是【{homeName}】的退房信息。

                退房时间：{checkOutTime}

                - 请将钥匙放在门内侧后离开
                - 请关闭所有灯光和空调

                期待您的再次光临！
                """,

            "ko": """
                안녕하세요, {guestName}님,

                [{homeName}] 체크아웃 안내입니다.

                체크아웃: {checkOutTime}

                - 열쇠는 문 안쪽에 놓고 나가주세요
                - 조명과 에어컨을 꺼주세요

                또 방문해 주시기를 기다리겠습니다!
                """,
        ],

        TemplateKey.wifiGuide.rawValue: [
            "ja": """
                【Wi-Fi接続情報】
                ネットワーク名: {wifiSSID}
                パスワード: {wifiPassword}
                """,

            "en": """
                [Wi-Fi Information]
                Network: {wifiSSID}
                Password: {wifiPassword}
                """,

            "zh": """
                【Wi-Fi信息】
                网络名称：{wifiSSID}
                密码：{wifiPassword}
                """,

            "ko": """
                [Wi-Fi 정보]
                네트워크 이름: {wifiSSID}
                비밀번호: {wifiPassword}
                """,
        ],

        TemplateKey.doorCodeGuide.rawValue: [
            "ja": """
                【ドアコード】
                {homeName} のドアコード: {doorCode}
                """,

            "en": """
                [Door Code]
                Door code for {homeName}: {doorCode}
                """,

            "zh": """
                【门锁密码】
                {homeName} 的门锁密码：{doorCode}
                """,

            "ko": """
                [도어 코드]
                {homeName} 도어 코드: {doorCode}
                """,
        ],
    ]

    // MARK: - 対応言語

    static let supportedLanguages: [(code: String, label: String)] = [
        ("ja", "日本語"),
        ("en", "English"),
        ("zh", "中文（简体）"),
        ("ko", "한국어"),
    ]

    // MARK: - メイン API

    /// テンプレートキーと言語コードを指定してメッセージを生成する。
    /// - Parameters:
    ///   - template: テンプレートキー（TemplateKey.rawValue を推奨）
    ///   - language: 言語コード ("ja" / "en" / "zh" / "ko")。未対応の場合は "ja" にフォールバック。
    ///   - vars: 変数辞書。例: ["guestName": "田中様", "doorCode": "1234"]
    /// - Returns: 変数を展開した完成メッセージ文字列
    static func localizedMessage(
        template: String,
        language: String,
        vars: [String: String]
    ) -> String {
        let lang = supportedLanguages.map(\.code).contains(language) ? language : "ja"
        var message = templates[template]?[lang]
            ?? templates[template]?["ja"]
            ?? template

        for (key, value) in vars {
            message = message.replacingOccurrences(of: "{\(key)}", with: value)
        }

        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// TemplateKey 型を使った型安全バージョン
    static func localizedMessage(
        template: TemplateKey,
        language: String,
        vars: [String: String]
    ) -> String {
        localizedMessage(template: template.rawValue, language: language, vars: vars)
    }
}

// MARK: - 日付フォーマットヘルパー

extension GuestLocalization {
    /// 言語に合わせた日付文字列を返す
    static func formattedDate(_ date: Date, language: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier(for: language))
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func localeIdentifier(for language: String) -> String {
        switch language {
        case "en": return "en_US"
        case "zh": return "zh_Hans_CN"
        case "ko": return "ko_KR"
        default:   return "ja_JP"
        }
    }
}
