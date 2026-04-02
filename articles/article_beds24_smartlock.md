---
title: "Beds24 × スマートロックで民泊の鍵管理を完全自動化した話"
emoji: "🔐"
type: "tech"
topics: ["beds24", "smartlock", "minpaku", "switchbot", "swift"]
published: false
---

## はじめに：キーボックスの限界

民泊を運営していると、鍵の受け渡しが最大のストレスポイントになります。

キーボックスを使っている方も多いと思いますが、実際に運用してみると問題が山積みです。

- ゲストが暗証番号を間違えて深夜に電話が来る
- 前のゲストが番号を知っているのでチェックアウト後にセキュリティリスク
- 毎回手動で番号を変更→ゲストに通知→対応漏れ
- 物件が増えるとキーボックスの管理だけで月10時間以上

こうした課題を解決するために、Beds24の予約管理とスマートロックAPIを連携させて、鍵管理を完全自動化する仕組みを構築しました。この記事では、その技術的な仕組みを解説します。

## 全体アーキテクチャ

```
Beds24 API v2 (予約データ)
    ↓ ポーリング (30分間隔)
iOS App (KAGI)
    ↓ 新予約検知
スマートロック API (SwitchBot / Sesame / Nuki)
    ↓ ドアコード発行 or 解錠
ゲストへ通知 (LINE / メール / 共有リンク)
```

ポイントは、Beds24がWebhookを公式提供していないため、APIポーリングで新規予約を検知する方式を採用している点です。iOSのBGAppRefreshTaskを使って、アプリがバックグラウンドでも30分間隔で同期し続けます。

## Beds24 API v2 の認証フロー

Beds24 API v2はOAuthライクなトークン方式を採用しています。Invite Codeから始まる3ステップの認証フローです。

### Step 1: Invite Code → Refresh Token

Beds24の管理画面でInvite Codeを発行し、`/authentication/setup` エンドポイントに送ります。

```swift
final class Beds24Client: Sendable {
    static let shared = Beds24Client()
    private let base = "https://api.beds24.com/v2"

    /// Step 1: Invite Code → Refresh Token
    func setupWithInviteCode(_ inviteCode: String, deviceName: String = "カチャ") async throws -> String {
        guard !inviteCode.isEmpty else { throw Beds24Error.missingCode }
        guard let setupURL = URL(string: "\(base)/authentication/setup") else {
            throw Beds24Error.apiError(0)
        }
        var req = URLRequest(url: setupURL)
        req.httpMethod = "GET"
        req.addValue(inviteCode, forHTTPHeaderField: "code")
        req.addValue(deviceName, forHTTPHeaderField: "deviceName")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw Beds24Error.apiError((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let refreshToken = json["refreshToken"] as? String, !refreshToken.isEmpty else {
            throw Beds24Error.invalidCode
        }
        return refreshToken
    }
}
```

### Step 2: Refresh Token → API Token

```swift
/// Step 2: Refresh Token → API Token
func getToken(refreshToken: String) async throws -> String {
    guard !refreshToken.isEmpty else { throw Beds24Error.missingCode }
    guard let tokenURL = URL(string: "\(base)/authentication/token") else {
        throw Beds24Error.apiError(0)
    }
    var req = URLRequest(url: tokenURL)
    req.httpMethod = "GET"
    req.addValue(refreshToken, forHTTPHeaderField: "refreshToken")
    req.timeoutInterval = 15
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
        throw Beds24Error.apiError((resp as? HTTPURLResponse)?.statusCode ?? 0)
    }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let token = json["token"] as? String, !token.isEmpty else {
        throw Beds24Error.apiError(0)
    }
    return token
}
```

ここで注意点があります。Beds24 API v2のトークンは **ヘッダー方式** です。Authorizationヘッダーではなく、`token` という独自ヘッダーにAPIトークンをセットします。最初Bearerトークンだと思って実装したら全部401になりました。

```swift
// NG: req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
// OK:
req.addValue(token, forHTTPHeaderField: "token")
```

## 予約のポーリングと新規予約検知

バックグラウンドで30分おきにBeds24をポーリングし、新規予約を検知したらプッシュ通知を送ります。

```swift
struct BackgroundRefresh {
    static let taskIdentifier = "com.enablerdao.kacha.refresh"

    static func register(container: ModelContainer) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier, using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handleRefresh(refreshTask, container: container)
        }
    }

    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
```

予約ポーリングの核心部分は `BookingPoller` です。Beds24から取得した予約を `externalId` (`beds24-{bookId}`) で既存データと突合し、新規/更新/削除を判定します。

```swift
struct BookingPoller {
    static func pollAndNotify(context: ModelContext, home: Home, allHomes: [Home] = []) async -> Int {
        guard !home.beds24RefreshToken.isEmpty else { return 0 }
        guard let token = try? await Beds24Client.shared.getToken(
            refreshToken: home.beds24RefreshToken
        ) else { return 0 }
        guard let b24Bookings = try? await Beds24Client.shared.fetchBookings(
            token: token
        ) else { return 0 }

        // 既存予約を externalId で索引化
        let existingByExtId: [String: Booking] = ...

        for b24 in b24Bookings {
            let extId = "beds24-\(b24.effectiveId)"
            if let existing = existingByExtId[extId] {
                // 既存予約の更新（ステータス、金額、ゲスト情報等）
            } else {
                // 新規予約 → ローカルDB挿入 + プッシュ通知
                sendNewBookingNotification(
                    guestName: b24.guestFullName,
                    homeName: homeName,
                    checkIn: b24.arrival ?? "",
                    platform: b24.platformKey
                )
            }
        }
        // Beds24に存在しない予約はローカルからも削除
        return imported
    }
}
```

## スマートロック3社の比較

KAGIアプリでは3つのスマートロックに対応しています。民泊用途で実際に使った所感をまとめます。

### SwitchBot Lock

| 項目 | 内容 |
|------|------|
| 価格 | 約11,980円 |
| API | v1.1 REST API, HMAC-SHA256認証 |
| 利点 | 安い、API安定、ハブ経由で遠隔操作可能 |
| 欠点 | ハブ（約5,480円）が別途必要 |
| 民泊適性 | ★★★★★ |

SwitchBotのAPI認証はHMAC-SHA256で、CryptoKitを使ってクライアント側で署名を生成します。

```swift
private func makeHeaders(token: String, secret: String) -> [String: String] {
    let nonce = UUID().uuidString
    let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
    let stringToSign = token + timestamp + nonce
    let hmac = HMAC<SHA256>.authenticationCode(
        for: Data(stringToSign.utf8),
        using: SymmetricKey(data: Data(secret.utf8))
    )
    let sign = Data(hmac).base64EncodedString().uppercased()
    return [
        "Authorization": token,
        "sign": sign,
        "nonce": nonce,
        "t": timestamp,
        "Content-Type": "application/json"
    ]
}
```

施錠・解錠はシンプルなPOSTリクエストです。

```swift
func lock(deviceId: String, token: String, secret: String) async throws {
    try await sendCommand(deviceId: deviceId, command: "lock", token: token, secret: secret)
}

func unlock(deviceId: String, token: String, secret: String) async throws {
    try await sendCommand(deviceId: deviceId, command: "unlock", token: token, secret: secret)
}
```

### Sesame (CANDY HOUSE)

| 項目 | 内容 |
|------|------|
| 価格 | 約5,980円 (Sesame 5) |
| API | REST API, APIキー認証 |
| 利点 | 最安、Wi-Fi モジュール内蔵（Sesame 5 Pro）|
| 欠点 | APIドキュメントがやや不親切 |
| 民泊適性 | ★★★★☆ |

Sesameの認証は単純なAPIキー方式で実装が楽です。

```swift
func sendCommand(_ command: Command, uuid: String, apiKey: String, historyTag: String = "カチャ") async throws {
    guard let cmdURL = URL(string: "\(base)/\(uuid)") else { throw SesameError.apiError(0) }
    var req = URLRequest(url: cmdURL)
    req.httpMethod = "POST"
    req.addValue(apiKey, forHTTPHeaderField: "x-api-key")
    req.addValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: [
        "cmd": command.rawValue,   // 82=lock, 83=unlock, 88=toggle
        "history": historyTag
    ])
    let (_, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        throw SesameError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
```

操作履歴が取得できるのも民泊運用で便利です。「誰が、いつ、解錠したか」がAPI経由で分かります。

### Nuki Smart Lock

| 項目 | 内容 |
|------|------|
| 価格 | 約35,000円 |
| API | REST API (Web API), Bearer Token認証 |
| 利点 | キーパッドでPINコード入力対応、欧州で人気 |
| 欠点 | 高い、日本での入手がやや困難 |
| 民泊適性 | ★★★★☆ |

NukiはBearer Token認証でREST APIがきれいに設計されています。

```swift
func lock(smartlockId: Int, token: String) async throws {
    _ = try await request("/smartlock/\(smartlockId)/action/lock", method: "POST", token: token)
}

func unlock(smartlockId: Int, token: String) async throws {
    _ = try await request("/smartlock/\(smartlockId)/action/unlock", method: "POST", token: token)
}
```

キーパッドを組み合わせると、予約ごとにPINコードを発行→チェックアウト時に自動無効化、という運用が可能です。

## チェックイン時の自動化シーン

新規予約を検知したら、チェックイン30分前に「ウェルカム」シーンを自動実行します。スマートロック解錠だけでなく、照明やエアコンも連動させます。

```swift
func runPreCheckInIfNeeded(bookings: [Booking], ...) async {
    let now = Date()
    let threshold: TimeInterval = 30 * 60   // 30分前

    let upcoming = bookings.filter { booking in
        guard booking.status == "upcoming" else { return false }
        let diff = booking.checkIn.timeIntervalSince(now)
        return diff > 0 && diff <= threshold
    }

    guard !upcoming.isEmpty else { return }

    if let welcomeScene = AutomationScene.presets.first(where: { $0.id == "welcome" }) {
        await executeScene(welcomeScene, ...)
    }
}
```

チェックアウト時は逆に全デバイスOFF + 施錠を自動実行します。

```swift
// チェックアウトシーンのプリセット
AutomationScene(
    id: "checkout",
    name: "チェックアウト",
    icon: "figure.walk.departure",
    trigger: .checkOut,
    actions: [.lightsOff, .lockDoor, .setAC(temp: 26, mode: "off")],
    isEnabled: true
)
```

## まとめ：自動化の効果

この仕組みを導入してから、鍵関連の作業時間が大幅に削減されました。

| 作業 | 以前 | 自動化後 |
|------|------|----------|
| 鍵コード変更 | 15分/件 | 0分（自動） |
| ゲストへのコード通知 | 10分/件 | 0分（自動） |
| チェックアウト後の施錠確認 | 5分/件 | 0分（自動） |
| 月間（20件の場合） | 約10時間 | ほぼ0 |

この自動化の仕組みは [KAGI](https://github.com/enablerdao/kacha) というOSSの民泊管理アプリとして公開しています。Beds24と各種スマートロックの連携が組み込まれているので、セットアップだけで使い始められます。
