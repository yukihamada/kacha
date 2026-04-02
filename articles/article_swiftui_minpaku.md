---
title: "SwiftUIで民泊管理アプリを作った技術スタック全公開"
emoji: "🏠"
type: "tech"
topics: ["swiftui", "swiftdata", "rust", "minpaku", "ios"]
published: false
---

## はじめに

民泊管理は意外と技術的に面白い領域です。予約管理、スマートロック制御、ゲスト通知、光熱費トラッキング、E2E暗号化共有など、一つのアプリに多様な技術が詰まっています。

KAGI (カチャ) は、Beds24チャネルマネージャーとスマートロックを統合した民泊管理iOSアプリです。この記事では、KAGIの技術スタックとアーキテクチャの設計判断を全て公開します。

## 技術スタック概要

| レイヤー | 技術 |
|---------|------|
| UI | SwiftUI (iOS 17+) |
| ローカルDB | SwiftData |
| 暗号化 | CryptoKit (AES-256-GCM) |
| バックグラウンド同期 | BGAppRefreshTask |
| サーバー | Rust (axum 0.7) + SQLite |
| ホスティング | Fly.io (Tokyo region) |
| 外部API | Beds24 v2, SwitchBot v1.1, Sesame, Nuki, Philips Hue, Nature Remo |

## SwiftDataで複数モデルを管理する

KAGIでは15個のSwiftDataモデルを扱っています。

```swift
@main
struct KachaApp: App {
    let container: ModelContainer

    init() {
        let models: [any PersistentModel.Type] = [
            Home.self, Booking.self, SmartDevice.self, DeviceIntegration.self,
            ShareRecord.self, ChecklistItem.self, UtilityRecord.self,
            MaintenanceTask.self, NearbyPlace.self, ActivityLog.self,
            HouseManual.self, SecureItem.self, PropertyExpense.self,
            GuestReview.self, SentMessage.self,
        ]
        do {
            container = try ModelContainer(
                for: Schema(models),
                configurations: ModelConfiguration()
            )
        } catch {
            // スキーマ変更時はDBを削除してリトライ
            // Keychainバックアップからデータ復元される
            let dbURL = URL.applicationSupportDirectory.appending(path: "default.store")
            try? FileManager.default.removeItem(at: dbURL)
            container = try! ModelContainer(for: Schema(models))
        }
    }
}
```

### 主要モデルの設計

**Home** は物件を表すモデルです。各種スマートデバイスの認証情報、Beds24トークン、iCal URL、ジオフェンス設定、民泊届出番号まで、物件に紐づく全情報を持ちます。

```swift
@Model
final class Home {
    var id: String
    var name: String
    var address: String

    // スマートロック認証情報
    var switchBotToken: String
    var switchBotSecret: String
    var sesameApiKey: String
    var sesameDeviceUUIDs: String   // カンマ区切り

    // Beds24連携
    var beds24ApiKey: String        // プロパティID
    var beds24RefreshToken: String

    // iCal (Airbnb/じゃらん)
    var airbnbICalURL: String
    var jalanICalURL: String

    // ジオフェンス
    var latitude: Double
    var longitude: Double
    var geofenceRadius: Double
    var geofenceEnabled: Bool

    // 民泊届出
    var businessType: String       // "none" | "minpaku" | "ryokan"
    var minpakuNumber: String
    var minpakuNights: Int

    // シェアされた物件のロール
    var sharedRole: String         // "owner" | "admin" | "manager" | "cleaner" | "guest"
}
```

**Booking** は予約モデルです。Beds24からインポートされた予約は `externalId` に `beds24-{bookId}` が入り、ローカルで手動作成した予約と区別できます。

```swift
@Model
final class Booking {
    var id: String
    var guestName: String
    var guestEmail: String
    var guestPhone: String
    var platform: String     // "airbnb" | "jalan" | "beds24" | "booking" | "direct"
    var homeId: String
    var externalId: String   // "beds24-12345"
    var checkIn: Date
    var checkOut: Date
    var totalAmount: Int
    var numAdults: Int
    var numChildren: Int
    var status: String       // "upcoming" | "active" | "completed" | "cancelled"
    var autoUnlock: Bool     // チェックイン時に自動解錠するか
    var autoLight: Bool      // チェックイン時に照明をオンにするか

    /// Beds24のステータスをアプリ内ステータスに変換
    static func mapBeds24Status(_ beds24Status: String?, checkIn: Date, checkOut: Date) -> String {
        let now = Date()
        if beds24Status == "cancelled" { return "cancelled" }
        if now >= checkIn && now < checkOut { return "active" }
        if now >= checkOut { return "completed" }
        if beds24Status == "confirmed" || beds24Status == "new" { return "confirmed" }
        return "upcoming"
    }
}
```

**SmartDevice** は統一的なデバイスモデルで、複数プラットフォームのデバイスを抽象化します。

```swift
@Model
final class SmartDevice {
    var id: String
    var deviceId: String
    var name: String
    var type: String      // "lock" | "light" | "switch" | "hub"
    var platform: String  // "switchbot" | "hue" | "sesame" | "qrio" | "nuki" | "igloohome"
    var homeId: String
    var isOn: Bool
    var isLocked: Bool
    var brightness: Int
    var colorTemp: Int
    var lastSeen: Date
}
```

## ローカルファースト設計の理由

KAGIはローカルファーストアーキテクチャを採用しています。全てのデータはSwiftDataでオンデバイスに保存され、サーバーには暗号化されたシェアデータのみが存在します。

この設計にした理由は3つあります。

1. **民泊のWi-Fiパスワードやドアコードは機密情報** — クラウドに平文で置きたくない
2. **オフラインでも動作すべき** — 物件に行ったとき、Wi-Fiが不安定でも確認できる必要がある
3. **サーバーコスト最小化** — ユーザーごとにDBを持つ必要がない

Keychainバックアップで機種変更にも対応しています。

```swift
struct BackgroundRefresh {
    private static func handleRefresh(_ task: BGAppRefreshTask, container: ModelContainer) {
        scheduleNext()

        let workTask = Task {
            let (context, homes) = await MainActor.run {
                let ctx = ModelContext(container)
                let h = (try? ctx.fetch(FetchDescriptor<Home>())) ?? []
                return (ctx, h)
            }

            for home in homes where !home.beds24RefreshToken.isEmpty {
                // Beds24からの予約同期
                let _ = await BookingPoller.pollAndNotify(
                    context: context, home: home, allHomes: homes
                )
            }

            // Keychainバックアップ
            await MainActor.run { KeychainBackup.backup(context: context) }
        }

        task.expirationHandler = { workTask.cancel() }

        Task {
            await workTask.value
            task.setTaskCompleted(success: true)
        }
    }
}
```

## E2E暗号化共有の実装

物件情報を他のスタッフやゲストとシェアする機能では、E2E暗号化を実装しています。サーバーには暗号化されたblobだけが保存され、復号キーはURL fragmentとして共有リンクに含まれます。

```swift
struct ShareClient {
    static let baseURL = "https://kacha.pasha.run"

    static func createShare(
        data: HomeShareData,
        validFrom: Date?,
        expiresAt: Date?,
        ownerToken: String
    ) async throws -> (token: String, encryptionKey: String) {
        // 1. ランダムな256bit鍵を生成
        let symmetricKey = SymmetricKey(size: .bits256)
        let keyData = symmetricKey.withUnsafeBytes { Data($0) }
        let keyBase64 = keyData.base64EncodedString()

        // 2. AES-256-GCMで暗号化
        let plaintext = try JSONEncoder().encode(data)
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)
        guard let combined = sealedBox.combined else { throw ShareError.uploadFailed }
        let encryptedBase64 = combined.base64EncodedString()

        // 3. サーバーにアップロード（暗号化blobのみ）
        // ...
        return (token: result.token, encryptionKey: keyBase64)
    }
}
```

共有リンクの形式は `https://kacha.pasha.run/s/{token}#{encryptionKey}` です。`#` 以降のフラグメントはHTTPリクエストに含まれないため、サーバーが復号キーを知ることはありません。

シェアデータにはロールに応じたアクセス制御があります。

```swift
struct HomeShareData: Codable {
    let name: String
    let address: String
    let role: String               // "guest" | "cleaner" | "manager" | "admin"
    // manager+admin のみ
    let switchBotToken: String
    let switchBotSecret: String
    let sesameApiKey: String
    let sesameDeviceUUIDs: String
    // cleaner以外
    let doorCode: String
    let wifiPassword: String
    // admin のみ
    let beds24ApiKey: String?
    let beds24RefreshToken: String?
}
```

## サーバー側: Rust + axum + SQLite

サーバーはRust (axum) + SQLiteで、Fly.ioの東京リージョンにデプロイしています。サーバーの役割は最小限で、暗号化されたシェアデータの保管と取得だけです。

```rust
// server/src/main.rs
use axum::{routing::{get, post, delete}, Router};
use rusqlite::Connection;

struct AppState {
    db: Mutex<Connection>,
}

#[derive(Deserialize)]
struct CreateShare {
    encrypted_data: String,     // Base64 AES-256-GCM blob
    valid_from: Option<DateTime<Utc>>,
    expires_at: Option<DateTime<Utc>>,
    owner_token: String,        // オーナーが取り消すときに使う
}
```

DBスキーマもシンプルです。

```sql
CREATE TABLE IF NOT EXISTS shares (
    token          TEXT PRIMARY KEY,
    owner_token    TEXT NOT NULL,
    encrypted_data TEXT NOT NULL,     -- 暗号化blobのみ保存
    valid_from     TEXT,
    expires_at     TEXT,
    revoked        INTEGER NOT NULL DEFAULT 0,
    created_at     TEXT NOT NULL DEFAULT (datetime('now'))
);
```

## オートメーションエンジン

チェックイン/チェックアウトに連動して、複数デバイスを一括制御するオートメーションエンジンを実装しています。

```swift
enum AutomationAction: Codable, Equatable {
    case lightsOn(brightness: Int, colorTemp: Int)
    case lightsOff
    case lockDoor
    case unlockDoor
    case setAC(temp: Int, mode: String)
    case allOff
}

enum AutomationTrigger: String, Codable, CaseIterable {
    case checkIn   = "checkIn"
    case checkOut  = "checkOut"
    case manual    = "manual"
    case schedule  = "schedule"
}
```

プリセットシーンとして「ウェルカム」「チェックアウト」「おやすみ」「お出かけ」「パーティー」を用意しています。

```swift
static let presets: [AutomationScene] = [
    AutomationScene(
        id: "welcome", name: "ウェルカム",
        trigger: .checkIn,
        actions: [
            .lightsOn(brightness: 70, colorTemp: 2700),
            .setAC(temp: 24, mode: "cool")
        ],
        isEnabled: true
    ),
    AutomationScene(
        id: "checkout", name: "チェックアウト",
        trigger: .checkOut,
        actions: [.lightsOff, .lockDoor, .setAC(temp: 26, mode: "off")],
        isEnabled: true
    ),
]
```

`executeAction` では、SwitchBot/Sesame/Hueなど各プラットフォームのクライアントをディスパッチして、実際のデバイス制御を行います。

## Beds24 API連携のハマりポイント

実装中に遭遇した落とし穴をまとめます。

### 1. トークンはカスタムヘッダー

前述の通り、`Authorization: Bearer` ではなく `token` ヘッダーです。

### 2. レスポンスの `data` ラッパー

Beds24 v2のレスポンスは `{"data": [...]}` でラップされている場合とされていない場合があります。両方に対応する必要があります。

```swift
private func decodeDataArray<T: Decodable>(_ data: Data) -> [T]? {
    // { "data": [...] } 形式
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let arr = json["data"] {
        let arrData = try? JSONSerialization.data(withJSONObject: arr)
        if let arrData, let decoded = try? JSONDecoder().decode([T].self, from: arrData) {
            return decoded
        }
    }
    // 直接配列の場合
    return try? JSONDecoder().decode([T].self, from: data)
}
```

### 3. 物件の自動検出

Beds24アカウントに紐づく物件を自動検出し、アプリ内にHomeを自動作成する機能があります。ただし、propertyIdの紐付けが正しくないと予約が別の物件に表示されます。

### 4. Airbnb問い合わせのインポート

デフォルトではAirbnbの「問い合わせ」と「リクエスト」がBeds24にインポートされません。APIで明示的に有効化する必要があります。

```swift
func enableAirbnbInquiryImport(propertyId: Int, token: String) async throws {
    let payload: [String: Any] = [
        "channel": "airbnb",
        "properties": [["id": propertyId, "inquiryAndRequests": "importAll"]]
    ]
    // POST /channels/settings
}
```

## OSSとして公開した理由

KAGIはGitHubでOSSとして公開しています。理由はシンプルで、民泊管理ツールはホスト一人一人のニーズが違いすぎるからです。

- 対応ロックのブランドが違う
- Beds24以外のPMSを使っている人もいる
- LINEで通知したい人、メールで通知したい人
- 旅館業の人、民泊の人

全てを一つのアプリで吸収するよりも、コードを公開して各自がカスタマイズできるほうが合理的だと考えました。

リポジトリ: [https://github.com/enablerdao/kacha](https://github.com/enablerdao/kacha)

## まとめ

SwiftUI + SwiftData + CryptoKitの組み合わせは、民泊管理のようなローカルファースト+セキュリティ重視のアプリに非常に適しています。特に SwiftData は CoreData と比べて宣言的に書けるので、15モデルあっても見通しが良く保てました。

バックエンドをRust + SQLiteで最小限に抑えたことで、Fly.ioの無料枠に近いコストで運用できています。「サーバーは暗号化blobの倉庫」という割り切りが、セキュリティとコストの両面で効きました。
