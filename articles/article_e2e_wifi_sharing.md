---
title: "E2E暗号化でゲストにWi-Fiパスワードを安全に共有する仕組みを作った"
emoji: "🔑"
type: "tech"
topics: ["security", "cryptokit", "e2e", "aes", "swift"]
published: false
---

## 問題：LINEやメールでパスワードを送ること自体がリスク

民泊を運営していると、チェックイン前にゲストへWi-Fiパスワードやドアコードを伝える必要があります。多くのホストはLINEやメール、Airbnbのメッセージで送っていますが、これには問題があります。

- **平文で残る**: LINEやメールのサーバーにパスワードが平文で保存される
- **転送される可能性**: ゲストが同行者に転送 → どこまで広がるか分からない
- **スクショで拡散**: パスワードが画像として残り続ける
- **チェックアウト後も有効**: 送ったメッセージは削除できない（相手側に残る）

特に危険なのは、ドアコードとWi-Fiパスワードが同じメッセージに入っていて、それがいつまでも閲覧可能なことです。

## 解決策：E2E暗号化 + 時間制限付き共有リンク

KAGIアプリでは、以下の仕組みでこの問題を解決しています。

1. 共有データを**AES-256-GCM**で暗号化
2. 暗号化blobだけをサーバーに保存
3. 復号キーは**URLフラグメント** (`#` 以降) に含める → サーバーに送られない
4. 共有リンクに**有効期限**を設定 → チェックアウト後は自動失効
5. オーナーがいつでも**取り消し (revoke)** 可能

```
共有リンク: https://kacha.pasha.run/s/abc123#SGVsbG8gV29ybGQ=
                                      ^^^^^^^^ ^^^^^^^^^^^^^^^^^
                                      トークン   復号キー（サーバーに送られない）
```

URLの `#` 以降（フラグメント）はHTTPリクエストに含まれないため、サーバーは復号キーを知ることが原理的に不可能です。これがE2E暗号化の核心部分です。

## 技術詳細：AES-256-GCM

AES-256-GCMは認証付き暗号で、以下の性質を持ちます。

- **256bit鍵**: ブルートフォース不可能
- **GCM (Galois/Counter Mode)**: 暗号化と同時に改ざん検知
- **Nonce (12byte)**: 同じ鍵で異なるデータを安全に暗号化
- **Tag (16byte)**: 認証タグで完全性を保証

暗号化後のデータ形式:

```
nonce (12byte) || ciphertext (可変長) || tag (16byte)
→ これをBase64エンコードしてサーバーに送る
```

## 実装：CryptoKit (Swift) での暗号化

### 暗号化

```swift
import CryptoKit

struct ShareClient {
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

        // 2. HomeShareDataをJSONにエンコードしてAES-256-GCMで暗号化
        let plaintext = try JSONEncoder().encode(data)
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)
        guard let combined = sealedBox.combined else {
            throw ShareError.uploadFailed
        }
        let encryptedBase64 = combined.base64EncodedString()

        // 3. サーバーに暗号化blobだけをアップロード
        guard let url = URL(string: "\(baseURL)/api/v1/shares") else {
            throw ShareError.uploadFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let iso = ISO8601DateFormatter()
        var body: [String: Any] = [
            "encrypted_data": encryptedBase64,
            "owner_token": ownerToken,
        ]
        if let from = validFrom { body["valid_from"] = iso.string(from: from) }
        if let until = expiresAt { body["expires_at"] = iso.string(from: until) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw ShareError.uploadFailed
        }

        struct Response: Codable { let token: String }
        let result = try JSONDecoder().decode(Response.self, from: responseData)

        // token = サーバー側ID, encryptionKey = クライアントだけが知る復号キー
        return (token: result.token, encryptionKey: keyBase64)
    }
}
```

### 復号

```swift
static func fetchShare(token: String, encryptionKey: String) async throws -> HomeShareData {
    // 1. サーバーから暗号化blobを取得
    guard let url = URL(string: "\(baseURL)/api/v1/shares/\(token)") else {
        throw ShareError.networkError
    }
    let (data, response) = try await URLSession.shared.data(from: url)

    guard let http = response as? HTTPURLResponse else {
        throw ShareError.networkError
    }
    switch http.statusCode {
    case 200: break
    case 403: throw ShareError.notYetValid   // 有効期間前
    case 410: throw ShareError.expired        // 期限切れ
    case 404: throw ShareError.notFound       // 存在しない or 取り消し済み
    default:  throw ShareError.networkError
    }

    struct Response: Codable { let encrypted_data: String }
    let result = try JSONDecoder().decode(Response.self, from: data)

    // 2. Base64デコード → AES-256-GCMで復号
    guard let combinedData = Data(base64Encoded: result.encrypted_data),
          let keyData = Data(base64Encoded: encryptionKey) else {
        throw ShareError.decryptionFailed
    }

    let symmetricKey = SymmetricKey(data: keyData)
    let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
    let plaintext = try AES.GCM.open(sealedBox, using: symmetricKey)
    return try JSONDecoder().decode(HomeShareData.self, from: plaintext)
}
```

## サーバー側：暗号化blobしか保存しない

サーバー (Rust + axum + SQLite) のテーブル定義を見ると、`encrypted_data` が暗号化blobを保持しているだけです。

```sql
CREATE TABLE IF NOT EXISTS shares (
    token          TEXT PRIMARY KEY,
    owner_token    TEXT NOT NULL,
    encrypted_data TEXT NOT NULL,     -- AES-256-GCMで暗号化されたblob
    valid_from     TEXT,              -- この日時以降にアクセス可能
    expires_at     TEXT,              -- この日時以降は410 Goneを返す
    revoked        INTEGER NOT NULL DEFAULT 0,
    created_at     TEXT NOT NULL DEFAULT (datetime('now'))
);
```

サーバーが侵害されても、攻撃者が得られるのは暗号化blobだけです。復号キーはURLフラグメントとして共有リンクに含まれているため、サーバーに送られたことがありません。

### 時間制限の処理

サーバー側で有効期限をチェックし、適切なHTTPステータスを返します。

- `valid_from` 前: **403 Forbidden** (まだ有効期間外)
- `expires_at` 後: **410 Gone** (期限切れ)
- `revoked = 1`: **404 Not Found** (取り消し済み)

これにより、チェックインの日まではリンクが無効で、チェックアウト後は自動的に失効します。

### 取り消し (Revoke)

オーナーは `owner_token` を使っていつでもシェアを取り消せます。

```swift
static func revokeShare(token: String, ownerToken: String) async throws {
    guard let url = URL(string: "\(baseURL)/api/v1/shares/\(token)") else {
        throw ShareError.revokeFailed
    }
    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(
        withJSONObject: ["owner_token": ownerToken]
    )
    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw ShareError.revokeFailed
    }
}
```

## ロールベースのアクセス制御

共有リンクを作成するとき、シェア先のロールによって含まれる情報が変わります。

| ロール | ドアコード | Wi-Fi | デバイス制御 | Beds24 |
|--------|-----------|-------|-------------|--------|
| guest | ○ | ○ | - | - |
| cleaner | - | - | - | - |
| manager | ○ | ○ | ○ | - |
| admin | ○ | ○ | ○ | ○ |

```swift
private var sharePayload: HomeShareData {
    let hasDeviceAccess = selectedRole == "admin" || selectedRole == "manager"
    let hasFullAdmin = selectedRole == "admin"
    return HomeShareData(
        name: home.name,
        address: home.address,
        role: selectedRole,
        // manager+admin: デバイス制御キー
        switchBotToken: hasDeviceAccess ? home.switchBotToken : "",
        switchBotSecret: hasDeviceAccess ? home.switchBotSecret : "",
        sesameApiKey: hasDeviceAccess ? home.sesameApiKey : "",
        sesameDeviceUUIDs: hasDeviceAccess ? home.sesameDeviceUUIDs : "",
        // cleaner以外: ドアコード & Wi-Fi
        doorCode: (selectedRole != "cleaner") ? home.doorCode : "",
        wifiPassword: (selectedRole != "cleaner") ? home.wifiPassword : "",
        // admin のみ: Beds24
        beds24ApiKey: hasFullAdmin ? home.beds24ApiKey : nil,
        beds24RefreshToken: hasFullAdmin ? home.beds24RefreshToken : nil
    )
}
```

清掃スタッフにはドアコードすら渡しません（物理鍵やBLE解錠を想定）。ゲストにはWi-Fiパスワードとドアコードだけ。管理者にはスマートデバイスの制御権限まで含めます。

**暗号化前にフィルタリングする** のがポイントです。不要な情報はそもそもpayloadに含めないため、仮に復号されても不要な情報は漏洩しません。

## ローカル機密データの暗号化

共有リンクとは別に、ローカルに保存する機密データ（Vaultに保存するパスポート番号、クレジットカード情報など）も暗号化しています。

```swift
enum VaultEncryption {
    private static let keychainService = "com.enablerdao.kacha.vault"

    /// 平文をAES-256-GCMで暗号化し、Base64で返す
    static func encrypt(_ plaintext: String) -> String {
        guard let key = loadOrCreateKey(),
              let data = plaintext.data(using: .utf8) else {
            return plaintext
        }
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else { return plaintext }
            return combined.base64EncodedString()
        } catch {
            return plaintext
        }
    }

    /// 暗号文を復号して平文を返す。失敗時は入力をそのまま返す（旧データ互換）
    static func decrypt(_ ciphertext: String) -> String {
        guard !ciphertext.isEmpty,
              let key = loadOrCreateKey(),
              let combined = Data(base64Encoded: ciphertext) else {
            return ciphertext
        }
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            let decrypted = try AES.GCM.open(sealedBox, using: key)
            return String(data: decrypted, encoding: .utf8) ?? ciphertext
        } catch {
            return ciphertext  // 旧データ（平文）にはフォールバック
        }
    }
}
```

鍵はKeychainに保存し、`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` で保護しています。デバイスのロック解除後にのみアクセス可能で、バックアップからの復元では使えません（このデバイス専用）。

```swift
private static func loadOrCreateKey() -> SymmetricKey? {
    if let existing = loadKeyFromKeychain() {
        return existing
    }
    let newKey = SymmetricKey(size: .bits256)
    saveKeyToKeychain(newKey)
    return newKey
}

private static func saveKeyToKeychain(_ key: SymmetricKey) {
    let keyData = key.withUnsafeBytes { Data($0) }
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: keychainAccount,
    ]
    SecItemDelete(query as CFDictionary)

    var item = query
    item[kSecValueData as String] = keyData
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(item as CFDictionary, nil)
}
```

## KAGIアプリでの使い方

実際のユーザーフローはこうなります。

1. オーナーがKAGIアプリで物件のWi-Fiパスワードとドアコードを登録
2. 予約が入ったら「シェア」ボタンをタップ
3. ロール (ゲスト/清掃/マネージャー/管理者) と有効期限を設定
4. E2E暗号化された共有リンクが生成される
5. リンクをゲストにLINEやメールで送る
6. ゲストがリンクを開くと、ブラウザ上でJavaScriptが `#` 以降のキーを取り出して復号
7. チェックアウト後はリンクが自動失効

LINEで送るのは「暗号化されたリンク」であって、パスワードそのものではありません。仮にLINEのサーバーが侵害されても、リンクからはサーバー上の暗号化blobにアクセスするだけで、復号キー (`#` 以降) はURLフラグメントのためサーバーログにも残りません。

## セキュリティモデルのまとめ

| 脅威 | 対策 |
|------|------|
| サーバー侵害 | 暗号化blobのみ保存。復号キーはサーバーに送られない |
| 通信傍受 | HTTPS + フラグメントは送信されない |
| リンク漏洩 | 有効期限でチェックアウト後に自動失効 |
| 不正アクセス | オーナーがいつでもrevoke可能 |
| ロスト端末 | Keychainはデバイスロックで保護 |
| 権限昇格 | ロールベースで暗号化前にデータをフィルタ |

完全に信頼できるのはクライアントのみ、という前提でシステムを設計しています。

## まとめ

E2E暗号化は「難しそう」に見えますが、CryptoKitのおかげでSwiftでの実装は驚くほどシンプルです。`AES.GCM.seal` と `AES.GCM.open` の2つのAPIだけで暗号化/復号が完結します。

URLフラグメントに復号キーを含めるテクニックは、ファイル共有サービスなどでも使われているパターンです。サーバーを信頼しなくてもいいアーキテクチャは、民泊のような機密情報を扱うサービスに特に有効です。

この仕組みは [KAGI](https://github.com/enablerdao/kacha) というOSSの民泊管理アプリの一部として公開しています。ぜひコードを読んでみてください。
