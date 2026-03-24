import Foundation
import SwiftData

// MARK: - DeviceIntegration
// 拡張可能なデバイス統合モデル。SwitchBot/Hue/Sesame以外の新プラットフォームに使用。

@Model
final class DeviceIntegration {
    var id: String = UUID().uuidString
    var homeId: String = ""
    var platform: String = ""       // DevicePlatform.rawValue
    var name: String = ""           // ユーザーが設定した表示名
    var credentialsJSON: String = "{}"
    var isEnabled: Bool = true
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(homeId: String, platform: String, name: String, credentials: [String: String] = [:]) {
        self.id = UUID().uuidString
        self.homeId = homeId
        self.platform = platform
        self.name = name
        self.credentials = credentials
        self.createdAt = Date()
    }

    var credentials: [String: String] {
        get {
            guard let data = credentialsJSON.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data)
            else { return [:] }
            return dict
        }
        set {
            credentialsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "{}"
        }
    }

    subscript(key: String) -> String {
        get { credentials[key] ?? "" }
        set {
            var c = credentials; c[key] = newValue; credentials = c
        }
    }
}

// MARK: - Supported Platforms

struct DevicePlatform {
    let id: String
    let name: String
    let icon: String
    let description: String
    let colorHex: String
    let fields: [Field]
    let apiGuideURL: String
    let isAvailable: Bool   // falseは「近日対応」表示

    struct Field {
        let key: String
        let label: String
        let placeholder: String
        var isSecure: Bool = false
        var isOptional: Bool = false
    }

    static let all: [DevicePlatform] = [
        // ── 日本向け ──
        DevicePlatform(
            id: "nature_remo",
            name: "Nature Remo",
            icon: "wind",
            description: "エアコン・テレビ・照明をIRリモコンで制御",
            colorHex: "10B981",
            fields: [
                Field(key: "token", label: "アクセストークン", placeholder: "長い英数字のトークン", isSecure: true)
            ],
            apiGuideURL: "https://home.nature.global/",
            isAvailable: true
        ),
        DevicePlatform(
            id: "nuki",
            name: "Nuki Smart Lock",
            icon: "key.horizontal.fill",
            description: "Nukiスマートロックをクラウド経由で施錠・解錠",
            colorHex: "F59E0B",
            fields: [
                Field(key: "token", label: "APIトークン", placeholder: "Nuki Web APIトークン", isSecure: true),
                Field(key: "deviceIds", label: "デバイスID", placeholder: "IDをカンマ区切りで（任意）", isOptional: true)
            ],
            apiGuideURL: "https://developer.nuki.io/",
            isAvailable: true
        ),
        DevicePlatform(
            id: "igloohome",
            name: "igloohome",
            icon: "lock.badge.clock.fill",
            description: "暗証番号・カードキー対応のスマートロック",
            colorHex: "3B9FE8",
            fields: [
                Field(key: "token", label: "APIトークン", placeholder: "igloohome APIトークン", isSecure: true)
            ],
            apiGuideURL: "https://developer.igloohome.co/",
            isAvailable: false
        ),
        DevicePlatform(
            id: "sadiot",
            name: "SADIOT Lock",
            icon: "lock.fill",
            description: "GOALの日本製スマートロック",
            colorHex: "EF4444",
            fields: [
                Field(key: "token", label: "APIキー", placeholder: "SADIOT APIキー", isSecure: true)
            ],
            apiGuideURL: "https://sadiot.com/",
            isAvailable: false
        ),
        // ── グローバル・スマートホーム ──
        DevicePlatform(
            id: "tuya",
            name: "Tuya / Smart Life",
            icon: "bolt.circle.fill",
            description: "世界シェアNo.1のIoTプラットフォーム。スマートプラグ・ライト・センサー等",
            colorHex: "FF6D00",
            fields: [
                Field(key: "clientId",     label: "Client ID",     placeholder: "Tuya IoT Platform Client ID"),
                Field(key: "clientSecret", label: "Client Secret", placeholder: "Client Secret", isSecure: true),
                Field(key: "region",       label: "リージョン",     placeholder: "us / eu / cn / in")
            ],
            apiGuideURL: "https://developer.tuya.com/en/docs/iot/quick-start1",
            isAvailable: true
        ),
        DevicePlatform(
            id: "homeassistant",
            name: "Home Assistant",
            icon: "house.and.flag.fill",
            description: "ローカル自己ホスト型スマートホームHub。あらゆるデバイスを統合",
            colorHex: "18BCF2",
            fields: [
                Field(key: "url",   label: "URL",           placeholder: "http://homeassistant.local:8123"),
                Field(key: "token", label: "Long-Lived Token", placeholder: "プロフィール → 長期アクセストークン", isSecure: true)
            ],
            apiGuideURL: "https://developers.home-assistant.io/docs/api/rest/",
            isAvailable: true
        ),
        DevicePlatform(
            id: "shelly",
            name: "Shelly",
            icon: "powerplug.portrait.fill",
            description: "欧州製スマートリレー。壁スイッチや電力計を直接クラウド連携",
            colorHex: "4CAF50",
            fields: [
                Field(key: "token", label: "Cloud Auth Key", placeholder: "Shelly Cloud APIトークン", isSecure: true),
                Field(key: "server", label: "Cloud Server", placeholder: "shelly-xx-eu.shelly.cloud", isOptional: true)
            ],
            apiGuideURL: "https://shelly-api-docs.shelly.cloud/",
            isAvailable: true
        ),
        DevicePlatform(
            id: "smartthings",
            name: "Samsung SmartThings",
            icon: "star.circle.fill",
            description: "Samsung製スマートホームHub。多ブランド統合",
            colorHex: "1428A0",
            fields: [
                Field(key: "token", label: "Personal Access Token", placeholder: "account.smartthings.com でトークン発行", isSecure: true)
            ],
            apiGuideURL: "https://developer.smartthings.com/",
            isAvailable: false
        ),
        DevicePlatform(
            id: "august",
            name: "August / Yale",
            icon: "door.left.hand.closed",
            description: "米国・欧州で人気のスマートロック。Wi-Fiモジュール対応モデルが必要",
            colorHex: "B0860A",
            fields: [
                Field(key: "apiKey", label: "API Key", placeholder: "August Developer API Key", isSecure: true)
            ],
            apiGuideURL: "https://developer.august.com/",
            isAvailable: false
        ),
        DevicePlatform(
            id: "tedee",
            name: "Tedee",
            icon: "key.radiowaves.forward.fill",
            description: "欧州製Bluetooth/Wi-Fiスマートシリンダー錠",
            colorHex: "2E4057",
            fields: [
                Field(key: "token", label: "Personal Token", placeholder: "Tedee Portalで発行", isSecure: true)
            ],
            apiGuideURL: "https://tedee.com/api-documentation/",
            isAvailable: false
        ),
        DevicePlatform(
            id: "somfy",
            name: "Somfy TaHoma",
            icon: "blinds.horizontal.closed",
            description: "欧州製ロールシャッター・ブラインド・ゲート自動化",
            colorHex: "E63946",
            fields: [
                Field(key: "token", label: "Developer Token", placeholder: "developer.somfy.com でトークン発行", isSecure: true)
            ],
            apiGuideURL: "https://developer.somfy.com/",
            isAvailable: false
        ),
        DevicePlatform(
            id: "kasa",
            name: "TP-Link Kasa",
            icon: "powerplug.fill",
            description: "スマートプラグ・スマートスイッチの操作",
            colorHex: "10B981",
            fields: [
                Field(key: "token", label: "クラウドトークン", placeholder: "TP-Link クラウドトークン", isSecure: true)
            ],
            apiGuideURL: "https://www.tp-link.com/",
            isAvailable: false
        ),
        DevicePlatform(
            id: "meross",
            name: "Meross",
            icon: "powerplug.portrait.fill",
            description: "スマートプラグ・電球の一括管理",
            colorHex: "8B5CF6",
            fields: [
                Field(key: "token", label: "APIキー", placeholder: "Meross APIキー", isSecure: true)
            ],
            apiGuideURL: "https://www.meross.com/",
            isAvailable: false
        ),
        // ── 汎用連携 ──
        DevicePlatform(
            id: "ifttt",
            name: "IFTTT Webhook",
            icon: "arrow.triangle.2.circlepath",
            description: "IFTTTアプレットをトリガーしてあらゆるデバイスを制御",
            colorHex: "FF6B35",
            fields: [
                Field(key: "webhookKey", label: "Webhook Key", placeholder: "IFTTTのWebhook Key", isSecure: true),
                Field(key: "eventName",  label: "イベント名", placeholder: "例: kacha_lock")
            ],
            apiGuideURL: "https://ifttt.com/maker_webhooks",
            isAvailable: true
        ),
        DevicePlatform(
            id: "custom",
            name: "カスタムWebhook",
            icon: "network",
            description: "HTTPリクエストで任意のデバイスを操作",
            colorHex: "6366F1",
            fields: [
                Field(key: "actionURL", label: "実行URL",      placeholder: "https://..."),
                Field(key: "method",    label: "メソッド",      placeholder: "POST または GET"),
                Field(key: "body",      label: "Body (JSON)", placeholder: "{\"command\":\"on\"}", isOptional: true),
                Field(key: "token",     label: "Bearer Token", placeholder: "認証トークン（任意）", isSecure: true, isOptional: true)
            ],
            apiGuideURL: "",
            isAvailable: true
        ),
    ]

    static func find(_ id: String) -> DevicePlatform? {
        all.first { $0.id == id }
    }
}
