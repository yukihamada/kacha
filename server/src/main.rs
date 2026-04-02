use axum::{
    extract::{Path, Query, State},
    http::{header, HeaderMap, StatusCode},
    response::{Html, IntoResponse},
    routing::{delete, get, post},
    Json, Router,
};
use rand::Rng;
use chrono::{DateTime, Utc};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::{Arc, Mutex};
use tower_http::cors::CorsLayer;
use tower_http::services::ServeDir;
use uuid::Uuid;

struct AppState {
    db: Mutex<Connection>,
}

#[derive(Deserialize)]
struct CreateShare {
    encrypted_data: String, // Base64 AES-256-GCM encrypted blob
    valid_from: Option<DateTime<Utc>>,
    expires_at: Option<DateTime<Utc>>,
    owner_token: String, // random token owner keeps — needed to revoke
}

#[derive(Serialize)]
struct CreateShareResponse {
    token: String,
}

#[derive(Serialize)]
struct FetchShareResponse {
    encrypted_data: String,
    valid_from: Option<DateTime<Utc>>,
    expires_at: Option<DateTime<Utc>>,
}

#[derive(Serialize)]
struct ShareInfo {
    token: String,
    valid_from: Option<String>,
    expires_at: Option<String>,
    revoked: bool,
    created_at: String,
}

fn init_db(conn: &Connection) {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS waitlist (
            email       TEXT PRIMARY KEY,
            source      TEXT NOT NULL DEFAULT 'website',
            created_at  TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS shares (
            token       TEXT PRIMARY KEY,
            owner_token TEXT NOT NULL,
            encrypted_data TEXT NOT NULL,
            valid_from  TEXT,
            expires_at  TEXT,
            revoked     INTEGER NOT NULL DEFAULT 0,
            created_at  TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_owner ON shares(owner_token);
        CREATE TABLE IF NOT EXISTS users (
            id          TEXT PRIMARY KEY,
            email       TEXT UNIQUE NOT NULL,
            created_at  TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS magic_links (
            token       TEXT PRIMARY KEY,
            email       TEXT NOT NULL,
            expires_at  TEXT NOT NULL,
            used        INTEGER NOT NULL DEFAULT 0,
            created_at  TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS user_backups (
            user_id     TEXT NOT NULL,
            app_id      TEXT NOT NULL,
            encrypted_data TEXT NOT NULL,
            updated_at  TEXT NOT NULL DEFAULT (datetime('now')),
            PRIMARY KEY (user_id, app_id)
        );
        CREATE TABLE IF NOT EXISTS sessions (
            token       TEXT PRIMARY KEY,
            user_id     TEXT NOT NULL,
            expires_at  TEXT NOT NULL,
            created_at  TEXT NOT NULL DEFAULT (datetime('now'))
        );
        -- KAGIデバイス: デバイス登録テーブル
        CREATE TABLE IF NOT EXISTS devices (
            device_id        TEXT PRIMARY KEY,
            device_type      TEXT NOT NULL,  -- 'lite', 'band', 'hub', 'pro'
            owner_token      TEXT NOT NULL,
            family_token     TEXT NOT NULL UNIQUE,
            firmware_version TEXT,
            last_seen_at     INTEGER,
            created_at       INTEGER NOT NULL
        );
        -- KAGIデバイス: 安否イベントログテーブル
        CREATE TABLE IF NOT EXISTS safety_events (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id   TEXT NOT NULL,
            event_type  TEXT NOT NULL,  -- 'ok_button', 'breathing', 'door', 'fall', 'tier1', 'tier2', 'spo2_alert', 'hr_alert'
            acs_pct     INTEGER,        -- 0-100
            payload     TEXT,           -- JSON追加データ
            signature   TEXT,           -- ATECC608A署名 (hex)
            created_at  INTEGER NOT NULL
        );
        -- KAGIデバイス: 家族プッシュ通知トークンテーブル
        CREATE TABLE IF NOT EXISTS family_push_tokens (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            family_token TEXT NOT NULL,
            platform     TEXT NOT NULL,  -- 'apns', 'fcm'
            push_token   TEXT NOT NULL,
            created_at   INTEGER NOT NULL,
            UNIQUE(family_token, push_token)
        );
        -- KAGIデバイス: ファームウェアテーブル (OTA用)
        CREATE TABLE IF NOT EXISTS firmware_versions (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            version     TEXT NOT NULL UNIQUE,
            binary_data BLOB NOT NULL,
            created_at  INTEGER NOT NULL
        );
        -- Stripe 注文テーブル
        CREATE TABLE IF NOT EXISTS orders (
            id              TEXT PRIMARY KEY,
            product         TEXT NOT NULL,
            quantity        INTEGER NOT NULL DEFAULT 1,
            amount          INTEGER NOT NULL,
            currency        TEXT NOT NULL DEFAULT 'jpy',
            email           TEXT,
            stripe_session  TEXT,
            status          TEXT NOT NULL DEFAULT 'pending',
            created_at      TEXT NOT NULL DEFAULT (datetime('now'))
        );
        -- ChatWeb Vault: E2E暗号化キーストア
        CREATE TABLE IF NOT EXISTS vault_items (
            id          TEXT PRIMARY KEY,
            user_email  TEXT NOT NULL,
            key_name    TEXT NOT NULL,
            encrypted_value TEXT NOT NULL,
            category    TEXT NOT NULL DEFAULT 'apikey',
            created_at  TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at  TEXT NOT NULL DEFAULT (datetime('now')),
            UNIQUE(user_email, key_name)
        );
        -- チャリン連携: APNsプッシュトークン
        CREATE TABLE IF NOT EXISTS charin_push_tokens (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id     TEXT NOT NULL,
            push_token  TEXT NOT NULL UNIQUE,
            created_at  TEXT NOT NULL DEFAULT (datetime('now'))
        );
        -- チャリン連携: APIキー管理
        CREATE TABLE IF NOT EXISTS charin_api_keys (
            api_key     TEXT PRIMARY KEY,
            user_label  TEXT NOT NULL,
            created_at  TEXT NOT NULL DEFAULT (datetime('now'))
        );
        -- チャリン連携: 未取得の収入データ
        CREATE TABLE IF NOT EXISTS charin_pending_income (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            api_key     TEXT NOT NULL DEFAULT '',
            source      TEXT NOT NULL,
            amount      INTEGER NOT NULL,
            currency    TEXT NOT NULL DEFAULT 'JPY',
            category    TEXT NOT NULL DEFAULT 'subscription',
            memo        TEXT NOT NULL DEFAULT '',
            email       TEXT,
            fetched     INTEGER NOT NULL DEFAULT 0,
            created_at  TEXT NOT NULL DEFAULT (datetime('now'))
        );
        -- Beds24予約通知: アカウント登録
        CREATE TABLE IF NOT EXISTS beds24_accounts (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id         TEXT NOT NULL,
            refresh_token   TEXT NOT NULL,
            push_token      TEXT NOT NULL,
            platform        TEXT NOT NULL DEFAULT 'apns',
            last_polled_at  TEXT,
            created_at      TEXT NOT NULL DEFAULT (datetime('now')),
            UNIQUE(user_id, refresh_token)
        );
        -- Beds24予約通知: 既知の予約ID（重複通知防止）
        CREATE TABLE IF NOT EXISTS beds24_seen_bookings (
            account_id      INTEGER NOT NULL,
            booking_ext_id  TEXT NOT NULL,
            status          TEXT NOT NULL DEFAULT '',
            amount          INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (account_id, booking_ext_id)
        );
        -- Beds24メッセージ通知: 最後に確認したメッセージID（重複通知防止）
        CREATE TABLE IF NOT EXISTS beds24_seen_messages (
            account_id      INTEGER NOT NULL,
            booking_id      INTEGER NOT NULL,
            last_message_id TEXT NOT NULL DEFAULT '',
            last_checked_at TEXT NOT NULL DEFAULT (datetime('now')),
            PRIMARY KEY (account_id, booking_id)
        );",
    )
    .expect("init db");

    // Migration: add api_key column to charin_pending_income if missing
    let _ = conn.execute("ALTER TABLE charin_pending_income ADD COLUMN api_key TEXT NOT NULL DEFAULT ''", []);
}

async fn create_share(
    State(state): State<Arc<AppState>>,
    Json(body): Json<CreateShare>,
) -> Result<(StatusCode, Json<CreateShareResponse>), StatusCode> {
    let token = Uuid::new_v4().to_string();
    let db = state.db.lock().unwrap();
    db.execute(
        "INSERT INTO shares (token, owner_token, encrypted_data, valid_from, expires_at) VALUES (?1, ?2, ?3, ?4, ?5)",
        rusqlite::params![
            token,
            body.owner_token,
            body.encrypted_data,
            body.valid_from.map(|d| d.to_rfc3339()),
            body.expires_at.map(|d| d.to_rfc3339()),
        ],
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok((StatusCode::CREATED, Json(CreateShareResponse { token })))
}

async fn fetch_share(
    State(state): State<Arc<AppState>>,
    Path(token): Path<String>,
) -> Result<Json<FetchShareResponse>, StatusCode> {
    let db = state.db.lock().unwrap();
    let mut stmt = db
        .prepare("SELECT encrypted_data, valid_from, expires_at, revoked FROM shares WHERE token = ?1")
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let row = stmt
        .query_row(rusqlite::params![token], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, Option<String>>(1)?,
                row.get::<_, Option<String>>(2)?,
                row.get::<_, bool>(3)?,
            ))
        })
        .map_err(|_| StatusCode::NOT_FOUND)?;

    let (encrypted_data, valid_from_str, expires_at_str, revoked) = row;

    if revoked {
        return Err(StatusCode::GONE); // 410
    }

    let now = Utc::now();
    let valid_from = valid_from_str
        .as_deref()
        .and_then(|s| DateTime::parse_from_rfc3339(s).ok())
        .map(|d| d.with_timezone(&Utc));
    let expires_at = expires_at_str
        .as_deref()
        .and_then(|s| DateTime::parse_from_rfc3339(s).ok())
        .map(|d| d.with_timezone(&Utc));

    if let Some(from) = valid_from {
        if now < from {
            return Err(StatusCode::FORBIDDEN); // not yet valid
        }
    }
    if let Some(until) = expires_at {
        if now > until {
            return Err(StatusCode::GONE); // expired
        }
    }

    Ok(Json(FetchShareResponse {
        encrypted_data,
        valid_from,
        expires_at,
    }))
}

async fn revoke_share(
    State(state): State<Arc<AppState>>,
    Path(token): Path<String>,
    Json(body): Json<RevokeRequest>,
) -> StatusCode {
    let db = state.db.lock().unwrap();
    let affected = db
        .execute(
            "UPDATE shares SET revoked = 1 WHERE token = ?1 AND owner_token = ?2",
            rusqlite::params![token, body.owner_token],
        )
        .unwrap_or(0);
    if affected > 0 {
        StatusCode::OK
    } else {
        StatusCode::NOT_FOUND
    }
}

#[derive(Deserialize)]
struct RevokeRequest {
    owner_token: String,
}

#[derive(Deserialize)]
struct ListQuery {
    owner_token: String,
}

async fn list_shares(
    State(state): State<Arc<AppState>>,
    Json(body): Json<ListQuery>,
) -> Result<Json<Vec<ShareInfo>>, StatusCode> {
    let db = state.db.lock().unwrap();
    let mut stmt = db
        .prepare("SELECT token, valid_from, expires_at, revoked, created_at FROM shares WHERE owner_token = ?1 ORDER BY created_at DESC")
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let rows = stmt
        .query_map(rusqlite::params![body.owner_token], |row| {
            Ok(ShareInfo {
                token: row.get(0)?,
                valid_from: row.get(1)?,
                expires_at: row.get(2)?,
                revoked: row.get(3)?,
                created_at: row.get(4)?,
            })
        })
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .filter_map(|r| r.ok())
        .collect();

    Ok(Json(rows))
}

// MARK: - Apple App Site Association (Universal Links)

async fn aasa() -> impl IntoResponse {
    let body = r#"{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appIDs": ["5BV85JW8US.com.enablerdao.kacha"],
        "paths": ["/join*"]
      }
    ]
  }
}"#;
    (
        StatusCode::OK,
        [(header::CONTENT_TYPE, "application/json")],
        body,
    )
}

// MARK: - Web fallback for /join (when app not installed)

async fn join_fallback() -> Html<String> {
    Html(r#"<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>KAGI — ホームをシェア</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Hiragino Sans',sans-serif;background:#0A0A12;color:#eaeaf2;display:flex;align-items:center;justify-content:center;min-height:100vh;padding:24px}
.card{text-align:center;max-width:400px}
.icon{font-size:64px;margin-bottom:16px}
h1{font-size:24px;margin-bottom:8px}
p{color:#7a7a95;font-size:14px;line-height:1.6;margin-bottom:24px}
a.btn{display:inline-block;padding:14px 32px;background:#E8A838;color:#000;font-weight:700;border-radius:12px;text-decoration:none;font-size:16px}
a.btn:hover{opacity:.9}
.security{margin-top:24px;padding:16px;border:1px solid rgba(255,255,255,.06);border-radius:12px;text-align:left}
.security h3{font-size:13px;color:#3B9FE8;margin-bottom:8px}
.security li{font-size:12px;color:#7a7a95;margin-bottom:4px;list-style:none}
.security li::before{content:"🔒 "}
</style>
</head>
<body>
<div class="card">
<div class="icon">🏠</div>
<h1>KAGI</h1>
<p>スマートホームを友達とシェア。<br>鍵・照明・エアコンをまとめて管理。</p>
<a class="btn" href="https://apps.apple.com/app/id6760736346">App Storeで開く</a>
<div class="security">
<h3>セキュリティ</h3>
<ul>
<li>AES-256-GCM E2E暗号化</li>
<li>サーバーに平文データは保存されません</li>
<li>アクセス期間の制限・取り消しが可能</li>
</ul>
</div>
</div>
</body>
</html>"#.to_string())
}

async fn privacy_page() -> Html<String> {
    Html(r#"<!DOCTYPE html><html lang="ja"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>KAGI プライバシーポリシー</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,'Hiragino Sans',sans-serif;background:#0A0A12;color:#eaeaf2;padding:24px;max-width:700px;margin:0 auto;line-height:1.8}h1{font-size:22px;margin-bottom:16px;color:#E8A838}h2{font-size:16px;margin:20px 0 8px;color:#3B9FE8}p,li{font-size:14px;color:#aaa;margin-bottom:8px}ul{padding-left:20px}</style></head><body>
<h1>KAGI プライバシーポリシー</h1>
<p>最終更新日: 2026年3月25日</p>
<h2>1. 収集するデータ</h2>
<p>KAGIはユーザーの個人データを外部サーバーに収集・送信しません。すべてのデータ（デバイス設定、APIキー、予約情報等）はiPhoneのローカルストレージに保存されます。</p>
<h2>2. クラウド同期（E2Eバックアップ）</h2>
<p>クラウドバックアップ機能を有効にした場合、設定データはAES-256-GCMで端末内で暗号化されたうえでサーバーに保存されます。復号キーはサーバーに送信されません。サーバーは暗号化された状態のデータのみを保管するため、運営者はデータの内容を参照することができません。バックアップはメールアドレス認証によるセッショントークンで保護されます。</p>
<h2>3. E2Eシェア</h2>
<p>シェア機能を使用した場合、AES-256-GCMで暗号化されたデータのみがサーバーに保存されます。復号キーはサーバーに送信されません。暗号化データは期限切れ後にアクセス不能になります。シェアはオーナートークンにより任意のタイミングで取り消しできます。</p>
<h2>4. ゲストページ</h2>
<p>シェアリンク（/join）からアクセスしたゲストユーザーのデータは収集しません。ゲストページはアプリのインストール案内のみを提供し、アクセスログは保存されません。</p>
<h2>5. Apple Watch</h2>
<p>Apple Watch連携機能を使用する場合、ロック操作のコマンドはiPhoneを経由してスマートロックデバイスに直接送信されます。Watch上のデータはiPhoneと同期されたローカルデータのみを使用し、サーバーには送信されません。</p>
<h2>6. 外部サービス連携</h2>
<p>SwitchBot、Sesame、Philips Hue、Nuki、Beds24等の外部サービスとの通信は、各サービスのAPIサーバーと直接行われます。KAGIのサーバーを経由しません。</p>
<h2>7. 位置情報</h2>
<p>ジオフェンス機能を有効にした場合のみ、位置情報を使用します。位置情報は端末内でのみ処理され、外部に送信されません。</p>
<h2>8. 広告・トラッキング</h2>
<p>KAGIは広告SDK、アナリティクスSDKを一切使用していません。利用状況の追跡は行いません。</p>
<h2>9. データの削除</h2>
<p>アプリを削除すると、ローカルストレージのデータは削除されます。クラウドバックアップデータの削除をご希望の場合は info@enablerdao.com までご連絡ください。Keychainに保存されたデータは、iOSの設定からKeychainを削除することで消去できます。</p>
<h2>10. お問い合わせ</h2>
<p>プライバシーに関するお問い合わせ: info@enablerdao.com</p>
<p>運営: Enabler DAO / Yuki Hamada</p>
</body></html>"#.to_string())
}

async fn support_page() -> Html<String> {
    Html(r#"<!DOCTYPE html><html lang="ja"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>KAGI サポート</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,'Hiragino Sans',sans-serif;background:#0A0A12;color:#eaeaf2;padding:24px;max-width:700px;margin:0 auto;line-height:1.8}h1{font-size:22px;margin-bottom:16px;color:#E8A838}h2{font-size:16px;margin:20px 0 8px;color:#3B9FE8}p{font-size:14px;color:#aaa;margin-bottom:8px}a{color:#3B9FE8}</style></head><body>
<h1>KAGI サポート</h1>
<h2>よくある質問</h2>
<p><strong>Q: データはどこに保存されますか？</strong><br>A: すべてのデータはiPhoneのローカルに保存されます。クラウドバックアップ機能を有効にした場合は、AES-256-GCMで端末内暗号化されたデータがサーバーに保存されます（運営者は内容を参照不可）。E2Eシェア機能を使用した場合も同様に暗号化データのみが保存されます。</p>
<p><strong>Q: アプリを再インストールしてもデータは残りますか？</strong><br>A: はい。Keychainバックアップにより、再インストール後も自動復元されます。</p>
<p><strong>Q: Beds24の予約が同期されません</strong><br>A: 設定→Beds24で「接続する」を確認してください。Invite CodeはBeds24の設定→API v2から作成できます。</p>
<p><strong>Q: オートロック解除が動きません</strong><br>A: SwitchBotアプリでBotの動作を確認し、KAGIの設定でBotデバイスを選択してください。</p>
<h2>お問い合わせ</h2>
<p>メール: <a href="mailto:info@enablerdao.com">info@enablerdao.com</a></p>
<p>GitHub: <a href="https://github.com/yukihamada/kacha">yukihamada/kacha</a></p>
</body></html>"#.to_string())
}

// MARK: - Waitlist

#[derive(Deserialize)]
struct WaitlistRequest {
    email: String,
}

#[derive(Serialize)]
struct WaitlistResponse {
    success: bool,
    message: String,
}

async fn join_waitlist(
    State(state): State<Arc<AppState>>,
    Json(body): Json<WaitlistRequest>,
) -> Result<(StatusCode, Json<WaitlistResponse>), StatusCode> {
    let email = body.email.trim().to_lowercase();
    if email.is_empty() || !email.contains('@') {
        return Ok((StatusCode::BAD_REQUEST, Json(WaitlistResponse {
            success: false,
            message: "有効なメールアドレスを入力してください".into(),
        })));
    }
    let db = state.db.lock().unwrap();
    let result = db.execute(
        "INSERT OR IGNORE INTO waitlist (email) VALUES (?1)",
        rusqlite::params![email],
    );
    match result {
        Ok(_) => Ok((StatusCode::OK, Json(WaitlistResponse {
            success: true,
            message: "登録ありがとうございます！ベータ版の準備ができ次第ご連絡します。".into(),
        }))),
        Err(_) => Ok((StatusCode::OK, Json(WaitlistResponse {
            success: true,
            message: "既に登録済みです。".into(),
        }))),
    }
}

// MARK: - Magic Link Auth

#[derive(Deserialize)]
struct MagicLinkRequest {
    email: String,
}

#[derive(Serialize)]
struct MagicLinkResponse {
    success: bool,
    message: String,
}

#[derive(Deserialize)]
struct VerifyRequest {
    email: String,
    code: String,
}

#[derive(Serialize)]
struct VerifyResponse {
    success: bool,
    user_id: String,
    token: String,
    expires_at: String,
}

#[derive(Deserialize)]
struct SaveBackupRequest {
    user_id: String,
    app_id: String,
    encrypted_data: String,
    session_token: String,
}

#[derive(Serialize)]
struct SaveBackupResponse {
    success: bool,
}

#[derive(Deserialize)]
struct GetBackupQuery {
    user_id: String,
    session_token: String,
}

#[derive(Serialize)]
struct GetBackupResponse {
    encrypted_data: String,
}

async fn send_magic_link(
    State(state): State<Arc<AppState>>,
    Json(body): Json<MagicLinkRequest>,
) -> Result<(StatusCode, Json<MagicLinkResponse>), StatusCode> {
    let email = body.email.trim().to_lowercase();
    if email.is_empty() || !email.contains('@') {
        return Ok((
            StatusCode::BAD_REQUEST,
            Json(MagicLinkResponse {
                success: false,
                message: "有効なメールアドレスを入力してください".into(),
            }),
        ));
    }

    let code: String = format!("{:06}", rand::thread_rng().gen_range(0..1_000_000u32));
    let expires_at = (Utc::now() + chrono::Duration::minutes(10)).to_rfc3339();
    let one_hour_ago = (Utc::now() - chrono::Duration::hours(1)).to_rfc3339();

    let db = state.db.lock().unwrap();

    // Rate limit: max 5 codes per email per hour
    let recent_count: i64 = db
        .query_row(
            "SELECT COUNT(*) FROM magic_links WHERE email = ?1 AND created_at > ?2",
            rusqlite::params![email, one_hour_ago],
            |row| row.get(0),
        )
        .unwrap_or(0);
    if recent_count >= 5 {
        return Ok((
            StatusCode::TOO_MANY_REQUESTS,
            Json(MagicLinkResponse {
                success: false,
                message: "リクエストが多すぎます。しばらくしてから再試行してください。".into(),
            }),
        ));
    }

    db.execute(
        "INSERT INTO magic_links (token, email, expires_at) VALUES (?1, ?2, ?3)",
        rusqlite::params![code, email, expires_at],
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // TODO: In production, send email via Resend API
    // For now the code is stored in DB (retrieve via DB for testing)
    if std::env::var("ENABLE_DEBUG_LOG").is_ok() {
        println!("Magic link code for {}: {}", email, code);
    }

    Ok((
        StatusCode::OK,
        Json(MagicLinkResponse {
            success: true,
            message: "確認コードを送信しました".into(),
        }),
    ))
}

async fn verify_magic_link(
    State(state): State<Arc<AppState>>,
    Json(body): Json<VerifyRequest>,
) -> Result<Json<VerifyResponse>, StatusCode> {
    let email = body.email.trim().to_lowercase();
    let code = body.code.trim().to_string();
    let now = Utc::now().to_rfc3339();

    let db = state.db.lock().unwrap();

    // Check for valid, unused, non-expired code
    let valid = db
        .query_row(
            "SELECT token FROM magic_links WHERE token = ?1 AND email = ?2 AND used = 0 AND expires_at > ?3",
            rusqlite::params![code, email, now],
            |_row| Ok(()),
        )
        .is_ok();

    if !valid {
        return Err(StatusCode::UNAUTHORIZED);
    }

    // Mark as used
    db.execute(
        "UPDATE magic_links SET used = 1 WHERE token = ?1 AND email = ?2",
        rusqlite::params![code, email],
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // Create user if not exists, get user_id
    let user_id: String = match db.query_row(
        "SELECT id FROM users WHERE email = ?1",
        rusqlite::params![email],
        |row| row.get(0),
    ) {
        Ok(id) => id,
        Err(_) => {
            let new_id = Uuid::new_v4().to_string();
            db.execute(
                "INSERT INTO users (id, email) VALUES (?1, ?2)",
                rusqlite::params![new_id, email],
            )
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
            new_id
        }
    };

    let session_token = Uuid::new_v4().to_string();
    let session_expires = (Utc::now() + chrono::Duration::days(30)).to_rfc3339();

    db.execute(
        "INSERT INTO sessions (token, user_id, expires_at) VALUES (?1, ?2, ?3)",
        rusqlite::params![session_token, user_id, session_expires],
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(VerifyResponse {
        success: true,
        user_id,
        token: session_token,
        expires_at: session_expires,
    }))
}

fn cleanup_expired(conn: &Connection) {
    conn.execute("DELETE FROM magic_links WHERE expires_at < datetime('now')", []).ok();
    conn.execute("DELETE FROM shares WHERE expires_at IS NOT NULL AND expires_at < datetime('now') AND revoked = 0", []).ok();
    conn.execute("DELETE FROM sessions WHERE expires_at < datetime('now')", []).ok();
    conn.execute("DELETE FROM verify_attempts WHERE attempted_at < datetime('now', '-1 hour')", []).ok();
}

fn verify_session(db: &Connection, session_token: &str, user_id: &str) -> Result<(), StatusCode> {
    let now = Utc::now().to_rfc3339();
    db.query_row(
        "SELECT token FROM sessions WHERE token = ?1 AND user_id = ?2 AND expires_at > ?3",
        rusqlite::params![session_token, user_id, now],
        |_row| Ok(()),
    )
    .map_err(|_| StatusCode::UNAUTHORIZED)
}

async fn save_backup(
    State(state): State<Arc<AppState>>,
    Json(body): Json<SaveBackupRequest>,
) -> Result<Json<SaveBackupResponse>, StatusCode> {
    let db = state.db.lock().unwrap();
    verify_session(&db, &body.session_token, &body.user_id)?;
    db.execute(
        "INSERT INTO user_backups (user_id, app_id, encrypted_data, updated_at)
         VALUES (?1, ?2, ?3, datetime('now'))
         ON CONFLICT(user_id, app_id) DO UPDATE SET encrypted_data = ?3, updated_at = datetime('now')",
        rusqlite::params![body.user_id, body.app_id, body.encrypted_data],
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(SaveBackupResponse { success: true }))
}

async fn get_backup(
    State(state): State<Arc<AppState>>,
    Path(app_id): Path<String>,
    Query(params): Query<GetBackupQuery>,
) -> Result<Json<GetBackupResponse>, StatusCode> {
    let db = state.db.lock().unwrap();
    verify_session(&db, &params.session_token, &params.user_id)?;
    let encrypted_data: String = db
        .query_row(
            "SELECT encrypted_data FROM user_backups WHERE user_id = ?1 AND app_id = ?2",
            rusqlite::params![params.user_id, app_id],
            |row| row.get(0),
        )
        .map_err(|_| StatusCode::NOT_FOUND)?;

    Ok(Json(GetBackupResponse { encrypted_data }))
}

#[tokio::main]
async fn main() {
    let db_path = std::env::var("DATABASE_PATH").unwrap_or_else(|_| "kagi.db".into());
    let conn = Connection::open(&db_path).expect("open db");
    conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;")
        .ok();
    init_db(&conn);

    let state = Arc::new(AppState {
        db: Mutex::new(conn),
    });

    let app = Router::new()
        .route("/api/v1/shares", post(create_share))
        .route("/api/v1/shares/:token", get(fetch_share))
        .route("/api/v1/shares/:token", delete(revoke_share))
        .route("/api/v1/shares/list", post(list_shares))
        .route("/.well-known/apple-app-site-association", get(aasa))
        .route("/join", get(join_fallback))
        .route("/privacy", get(privacy_page))
        .route("/support", get(support_page))
        .route("/checkout/success", get(checkout_success_page))
        .route("/api/v1/waitlist", post(join_waitlist))
        .route("/api/v1/auth/magic-link", post(send_magic_link))
        .route("/api/v1/auth/verify", post(verify_magic_link))
        .route("/api/v1/auth/backup", post(save_backup))
        .route("/api/v1/auth/backup/:app_id", get(get_backup))
        // KAGI安否確認 API
        .route("/api/v1/devices/register", post(kagi_register_device))
        .route("/api/v1/devices/firmware/upload", post(kagi_firmware_upload))
        .route("/api/v1/devices/:device_id/events", post(kagi_post_event))
        .route("/api/v1/devices/:device_id/firmware", get(kagi_firmware_check))
        .route("/api/v1/family/:family_token/status", get(kagi_family_status))
        .route("/api/v1/family/:family_token/push_token", post(kagi_register_push_token))
        // Stripe 予約購入
        .route("/api/v1/checkout", post(stripe_create_checkout))
        .route("/api/v1/stripe/webhook", post(stripe_webhook))
        // チャリン連携
        .route("/api/v1/charin/register", post(charin_register_token))
        .route("/api/v1/charin/apikey", post(charin_create_apikey))
        .route("/api/v1/charin/income", post(charin_add_income))
        .route("/api/v1/charin/income/pending", get(charin_get_pending))
        .route("/api/v1/charin/wh/{api_key}", post(charin_stripe_webhook))
        // ChatWeb Vault — セキュアキー管理
        .route("/api/v1/vault/store", post(vault_store))
        .route("/api/v1/vault/list", post(vault_list))
        .route("/api/v1/vault/get", post(vault_get))
        .route("/api/v1/vault/delete", post(vault_delete))
        // Beds24予約通知
        .route("/api/v1/beds24/register", post(beds24_register))
        .route("/api/v1/beds24/unregister", post(beds24_unregister))
        .route("/health", get({
            let state = state.clone();
            move || async move {
                let db = state.db.lock().unwrap();
                cleanup_expired(&db);
                "ok"
            }
        }))
        .layer(
            CorsLayer::new()
                .allow_origin(tower_http::cors::Any)
                .allow_methods([http::Method::GET, http::Method::POST, http::Method::DELETE])
                .allow_headers([header::CONTENT_TYPE])
        )
        .fallback_service(ServeDir::new("/app/site").append_index_html_on_directories(true))
        .with_state(state.clone());

    // Beds24ポーリング（5分間隔）をバックグラウンドで起動
    tokio::spawn(beds24_poll_loop(state));

    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(8080);
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{port}"))
        .await
        .expect("bind");

    println!("kagi-server listening on :{port}");
    axum::serve(listener, app).await.expect("serve");
}

// ============================================================
// MARK: - KAGI 安否確認 API
// ============================================================

// --- デバイス登録 ---

#[derive(Deserialize)]
struct KagiRegisterDeviceRequest {
    device_id: String,
    device_type: String,   // 'lite', 'band', 'hub', 'pro'
    owner_token: String,
}

#[derive(Serialize)]
struct KagiRegisterDeviceResponse {
    device_id: String,
    family_token: String,
}

/// POST /api/v1/devices/register
/// デバイスを登録し family_token を返す。
/// device_id が重複する場合は既存の family_token を返す。
async fn kagi_register_device(
    State(state): State<Arc<AppState>>,
    Json(body): Json<KagiRegisterDeviceRequest>,
) -> Result<(StatusCode, Json<KagiRegisterDeviceResponse>), StatusCode> {
    let db = state.db.lock().unwrap();

    // 既存デバイスの確認
    let existing = db.query_row(
        "SELECT family_token FROM devices WHERE device_id = ?1",
        rusqlite::params![body.device_id],
        |row| row.get::<_, String>(0),
    );

    match existing {
        Ok(family_token) => {
            // 既存デバイス → 既存の family_token を返す
            Ok((
                StatusCode::OK,
                Json(KagiRegisterDeviceResponse {
                    device_id: body.device_id,
                    family_token,
                }),
            ))
        }
        Err(_) => {
            // 新規登録
            let family_token = Uuid::new_v4().to_string();
            let now = Utc::now().timestamp();
            db.execute(
                "INSERT INTO devices (device_id, device_type, owner_token, family_token, created_at)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                rusqlite::params![
                    body.device_id,
                    body.device_type,
                    body.owner_token,
                    family_token,
                    now,
                ],
            )
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

            Ok((
                StatusCode::CREATED,
                Json(KagiRegisterDeviceResponse {
                    device_id: body.device_id,
                    family_token,
                }),
            ))
        }
    }
}

// --- 安否イベント投稿 ---

#[derive(Deserialize)]
struct KagiPostEventRequest {
    event_type: String,       // 'ok_button', 'fall', 'tier1', 'tier2', etc.
    acs_pct: Option<i64>,     // 0-100
    payload: Option<Value>,   // JSON追加データ
    signature: Option<String>, // ATECC608A署名 (hex)
}

#[derive(Serialize)]
struct KagiPostEventResponse {
    ok: bool,
}

/// アラート系イベントかどうかを判定する
fn is_alert_event(event_type: &str) -> bool {
    matches!(event_type, "fall" | "tier1" | "tier2" | "spo2_alert" | "hr_alert")
}

/// POST /api/v1/devices/:device_id/events
/// 安否イベントを記録する。
/// Authorization ヘッダーで owner_token を検証する。
/// アラート系イベントのみ家族への push 通知ログを出力する (実際の送信は将来実装)。
async fn kagi_post_event(
    State(state): State<Arc<AppState>>,
    Path(device_id): Path<String>,
    headers: HeaderMap,
    Json(body): Json<KagiPostEventRequest>,
) -> Result<Json<KagiPostEventResponse>, StatusCode> {
    // Authorization ヘッダーから owner_token を取得
    let auth_header = headers
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .ok_or(StatusCode::UNAUTHORIZED)?;

    // "Bearer <token>" または "<token>" 形式に対応
    let owner_token = auth_header
        .strip_prefix("Bearer ")
        .unwrap_or(auth_header)
        .trim();

    let db = state.db.lock().unwrap();

    // owner_token を検証し family_token を取得
    let family_token: String = db
        .query_row(
            "SELECT family_token FROM devices WHERE device_id = ?1 AND owner_token = ?2",
            rusqlite::params![device_id, owner_token],
            |row| row.get(0),
        )
        .map_err(|_| StatusCode::UNAUTHORIZED)?;

    let now = Utc::now().timestamp();
    let payload_str = body.payload.as_ref().map(|v| v.to_string());

    // イベントを記録
    db.execute(
        "INSERT INTO safety_events (device_id, event_type, acs_pct, payload, signature, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        rusqlite::params![
            device_id,
            body.event_type,
            body.acs_pct,
            payload_str,
            body.signature,
            now,
        ],
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // last_seen_at を更新
    db.execute(
        "UPDATE devices SET last_seen_at = ?1 WHERE device_id = ?2",
        rusqlite::params![now, device_id],
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // アラート系のみプッシュ通知を送る (現時点はログのみ、将来 APNs/FCM 送信に拡張)
    if is_alert_event(&body.event_type) {
        let push_tokens: Vec<(String, String)> = {
            let mut stmt = db
                .prepare(
                    "SELECT platform, push_token FROM family_push_tokens WHERE family_token = ?1",
                )
                .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
            let rows = stmt.query_map(rusqlite::params![family_token], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
            })
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
            .filter_map(|r| r.ok())
            .collect();
            rows
        };

        // TODO: 実際の APNs/FCM 送信をここで実装する
        // 現時点はログ出力のみ
        for (platform, push_token) in &push_tokens {
            println!(
                "[KAGI ALERT] device={device_id} event={} → push({platform}, {push_token})",
                body.event_type
            );
        }
    }

    Ok(Json(KagiPostEventResponse { ok: true }))
}

// --- 家族向けステータス取得 ---

#[derive(Serialize)]
struct KagiLastEvent {
    #[serde(rename = "type")]
    event_type: String,
    ts: i64,
}

#[derive(Serialize)]
struct KagiRecentEvent {
    #[serde(rename = "type")]
    event_type: String,
    acs_pct: Option<i64>,
    payload: Option<Value>,
    ts: i64,
}

#[derive(Serialize)]
struct KagiFamilyStatusResponse {
    device_id: String,
    device_type: String,
    last_seen_minutes_ago: Option<i64>,
    streak_days: i64,
    acs_pct: Option<i64>,
    status: String,  // 'active', 'inactive', 'unknown'
    last_event: Option<KagiLastEvent>,
    recent_events: Vec<KagiRecentEvent>,
}

/// GET /api/v1/family/:family_token/status
/// 家族向けにデバイスの最新ステータスを返す。
async fn kagi_family_status(
    State(state): State<Arc<AppState>>,
    Path(family_token): Path<String>,
) -> Result<Json<KagiFamilyStatusResponse>, StatusCode> {
    let db = state.db.lock().unwrap();

    // デバイス情報を取得
    let (device_id, device_type, last_seen_at): (String, String, Option<i64>) = db
        .query_row(
            "SELECT device_id, device_type, last_seen_at FROM devices WHERE family_token = ?1",
            rusqlite::params![family_token],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .map_err(|_| StatusCode::NOT_FOUND)?;

    let now = Utc::now().timestamp();

    // 最終確認からの経過分数を計算
    let last_seen_minutes_ago = last_seen_at.map(|ts| (now - ts) / 60);

    // ステータス判定: 30分以内なら active、それ以外は inactive
    let status = match last_seen_minutes_ago {
        Some(m) if m <= 30 => "active",
        Some(_) => "inactive",
        None => "unknown",
    }
    .to_string();

    // 直近7日のイベント数でストリーク日数を計算 (簡易実装: ok_button イベントを基準)
    let streak_days: i64 = {
        let seven_days_ago = now - 7 * 24 * 3600;
        db.query_row(
            "SELECT COUNT(DISTINCT date(created_at, 'unixepoch')) FROM safety_events
             WHERE device_id = ?1 AND event_type = 'ok_button' AND created_at >= ?2",
            rusqlite::params![device_id, seven_days_ago],
            |row| row.get(0),
        )
        .unwrap_or(0)
    };

    // 最新イベントの acs_pct を取得
    let latest_acs: Option<i64> = db
        .query_row(
            "SELECT acs_pct FROM safety_events WHERE device_id = ?1
             ORDER BY created_at DESC LIMIT 1",
            rusqlite::params![device_id],
            |row| row.get(0),
        )
        .ok()
        .flatten();

    // 最新イベント情報
    let last_event: Option<KagiLastEvent> = db
        .query_row(
            "SELECT event_type, created_at FROM safety_events WHERE device_id = ?1
             ORDER BY created_at DESC LIMIT 1",
            rusqlite::params![device_id],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?)),
        )
        .ok()
        .map(|(event_type, ts)| KagiLastEvent { event_type, ts });

    // 直近10件のイベント履歴
    let recent_events: Vec<KagiRecentEvent> = {
        let mut stmt = db
            .prepare(
                "SELECT event_type, acs_pct, payload, created_at FROM safety_events
                 WHERE device_id = ?1 ORDER BY created_at DESC LIMIT 10",
            )
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        let rows = stmt.query_map(rusqlite::params![device_id], |row| {
            let payload_str: Option<String> = row.get(2)?;
            let payload: Option<Value> = payload_str
                .as_deref()
                .and_then(|s| serde_json::from_str(s).ok());
            Ok(KagiRecentEvent {
                event_type: row.get(0)?,
                acs_pct: row.get(1)?,
                payload,
                ts: row.get(3)?,
            })
        })
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .filter_map(|r| r.ok())
        .collect();
        rows
    };

    Ok(Json(KagiFamilyStatusResponse {
        device_id,
        device_type,
        last_seen_minutes_ago,
        streak_days,
        acs_pct: latest_acs,
        status,
        last_event,
        recent_events,
    }))
}

// --- 家族プッシュトークン登録 ---

#[derive(Deserialize)]
struct KagiRegisterPushTokenRequest {
    platform: String,   // 'apns', 'fcm'
    push_token: String,
}

#[derive(Serialize)]
struct KagiRegisterPushTokenResponse {
    ok: bool,
}

/// POST /api/v1/family/:family_token/push_token
/// 家族のプッシュ通知トークンを登録する (重複は無視)。
async fn kagi_register_push_token(
    State(state): State<Arc<AppState>>,
    Path(family_token): Path<String>,
    Json(body): Json<KagiRegisterPushTokenRequest>,
) -> Result<Json<KagiRegisterPushTokenResponse>, StatusCode> {
    let db = state.db.lock().unwrap();

    // family_token の存在確認
    let exists: bool = db
        .query_row(
            "SELECT 1 FROM devices WHERE family_token = ?1",
            rusqlite::params![family_token],
            |_| Ok(true),
        )
        .unwrap_or(false);

    if !exists {
        return Err(StatusCode::NOT_FOUND);
    }

    let now = Utc::now().timestamp();

    // 重複は UNIQUE 制約で無視される
    db.execute(
        "INSERT OR IGNORE INTO family_push_tokens (family_token, platform, push_token, created_at)
         VALUES (?1, ?2, ?3, ?4)",
        rusqlite::params![family_token, body.platform, body.push_token, now],
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(KagiRegisterPushTokenResponse { ok: true }))
}

// --- OTA ファームウェア確認 ---

#[derive(Deserialize)]
#[allow(dead_code)] // 将来バージョン比較に使用
struct KagiFirmwareQuery {
    version: Option<String>,
}

/// GET /api/v1/devices/:device_id/firmware
/// OTA ファームウェア確認。現在のバージョンが最新なら 204、更新があれば 200 + バイナリを返す。
/// 現時点は常に 204 を返すスタブ実装。
async fn kagi_firmware_check(
    State(_state): State<Arc<AppState>>,
    Path(_device_id): Path<String>,
    Query(_params): Query<KagiFirmwareQuery>,
) -> StatusCode {
    // TODO: DB に最新ファームウェアを保存し、バージョン比較を実装する
    // 現時点は常に "最新です" を返すスタブ
    StatusCode::NO_CONTENT
}

// --- 管理者用 FW アップロード ---

#[derive(Deserialize)]
struct KagiFirmwareUploadQuery {
    version: String,
    token: String,
}

/// POST /api/v1/devices/firmware/upload
/// 管理者専用ファームウェアアップロード。
/// env "KAGI_ADMIN_TOKEN" で認証し、バイナリを DB に保存する。
async fn kagi_firmware_upload(
    State(state): State<Arc<AppState>>,
    Query(params): Query<KagiFirmwareUploadQuery>,
    body: axum::body::Bytes,
) -> StatusCode {
    // 管理者トークン検証
    let admin_token = std::env::var("KAGI_ADMIN_TOKEN").unwrap_or_default();
    if admin_token.is_empty() || params.token != admin_token {
        return StatusCode::UNAUTHORIZED;
    }

    if body.is_empty() {
        return StatusCode::BAD_REQUEST;
    }

    let db = state.db.lock().unwrap();
    let now = Utc::now().timestamp();

    // 既存バージョンは上書き (INSERT OR REPLACE)
    match db.execute(
        "INSERT OR REPLACE INTO firmware_versions (version, binary_data, created_at)
         VALUES (?1, ?2, ?3)",
        rusqlite::params![params.version, body.as_ref(), now],
    ) {
        Ok(_) => {
            println!("[KAGI OTA] firmware uploaded: v{}", params.version);
            StatusCode::CREATED
        }
        Err(_) => StatusCode::INTERNAL_SERVER_ERROR,
    }
}

// ============================================================
// MARK: - Checkout Success Page
// ============================================================

async fn checkout_success_page() -> Html<String> {
    Html(r#"<!DOCTYPE html><html lang="ja"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>IKI - ご予約ありがとうございます</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{background:#0a0a0a;color:#d4d4d4;font-family:'Inter',-apple-system,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;text-align:center;padding:24px}
.card{max-width:500px}.check{font-size:72px;margin-bottom:24px}h1{font-size:28px;color:#fff;margin-bottom:12px}p{color:#666;line-height:1.7;margin-bottom:24px}
.btn{display:inline-block;background:#e8a838;color:#0a0a0a;font-weight:700;padding:14px 32px;border-radius:12px;text-decoration:none;margin-top:16px}</style></head>
<body><div class="card"><div class="check">&#10003;</div><h1>ご予約ありがとうございます</h1>
<p>IKIデバイスの予約を受け付けました。<br>製造完了後、登録メールアドレスに発送のご連絡をいたします。</p>
<a href="/" class="btn">ホームに戻る</a></div></body></html>"#.to_string())
}

// ============================================================
// MARK: - Stripe 予約購入 API
// ============================================================

#[derive(Deserialize)]
struct CheckoutRequest {
    product: String,    // "lite", "hub", "band"
    quantity: Option<i32>,
    email: Option<String>,
}

#[derive(Serialize)]
struct CheckoutResponse {
    url: String,
    order_id: String,
}

/// POST /api/v1/checkout — Stripe Checkout Session 作成
async fn stripe_create_checkout(
    State(state): State<Arc<AppState>>,
    Json(body): Json<CheckoutRequest>,
) -> impl IntoResponse {
    let stripe_key = std::env::var("STRIPE_SECRET_KEY").unwrap_or_default();

    let (price, name): (i32, &str) = match body.product.as_str() {
        "lite" => (4800, "KAGI Lite"),
        "hub" => (14800, "KAGI Hub"),
        "band" => (9800, "KAGI Band"),
        _ => return (StatusCode::BAD_REQUEST, Json(serde_json::json!({"error":"invalid product"}))),
    };
    let qty = body.quantity.unwrap_or(1).max(1).min(100);
    let order_id = Uuid::new_v4().to_string();

    {
        let db = state.db.lock().unwrap();
        let _ = db.execute(
            "INSERT INTO orders (id, product, quantity, amount, email, status) VALUES (?1, ?2, ?3, ?4, ?5, 'pending')",
            rusqlite::params![&order_id, &body.product, qty, price * qty, &body.email],
        );
    }

    if stripe_key.is_empty() {
        // Stripe未設定: 直接successページへ
        return (StatusCode::OK, Json(serde_json::json!({
            "url": format!("/checkout/success?order_id={order_id}"),
            "order_id": order_id
        })));
    }

    let base_url = std::env::var("BASE_URL").unwrap_or_else(|_| "https://kagi-server.fly.dev".into());
    let price_str = price.to_string();
    let qty_str = qty.to_string();
    let success = format!("{base_url}/checkout/success?order_id={order_id}");
    let cancel = format!("{base_url}/#lineup");
    let email = body.email.as_deref().unwrap_or("");

    let client = reqwest::Client::new();
    let res = client
        .post("https://api.stripe.com/v1/checkout/sessions")
        .header("Authorization", format!("Bearer {stripe_key}"))
        .form(&[
            ("mode", "payment"),
            ("currency", "jpy"),
            ("line_items[0][price_data][currency]", "jpy"),
            ("line_items[0][price_data][unit_amount]", price_str.as_str()),
            ("line_items[0][price_data][product_data][name]", name),
            ("line_items[0][quantity]", qty_str.as_str()),
            ("success_url", success.as_str()),
            ("cancel_url", cancel.as_str()),
            ("metadata[order_id]", order_id.as_str()),
            ("customer_email", email),
        ])
        .send()
        .await;

    match res {
        Ok(r) => {
            if let Ok(json) = r.json::<Value>().await {
                if let Some(url) = json["url"].as_str() {
                    let sid = json["id"].as_str().unwrap_or("").to_string();
                    let db = state.db.lock().unwrap();
                    let _ = db.execute(
                        "UPDATE orders SET stripe_session = ?1 WHERE id = ?2",
                        rusqlite::params![&sid, &order_id],
                    );
                    return (StatusCode::OK, Json(serde_json::json!({"url": url, "order_id": order_id})));
                }
            }
            (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({"error":"stripe error"})))
        }
        Err(_) => (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({"error":"request failed"}))),
    }
}

/// POST /api/v1/stripe/webhook — Stripe Webhook (payment成功時にチャリンへ通知)
async fn stripe_webhook(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    body: axum::body::Bytes,
) -> StatusCode {
    // Webhook署名検証（オプション）
    let _sig = headers.get("stripe-signature").and_then(|v| v.to_str().ok());

    let payload: Value = match serde_json::from_slice(&body) {
        Ok(v) => v,
        Err(_) => return StatusCode::BAD_REQUEST,
    };

    let event_type = payload["type"].as_str().unwrap_or("").to_string();
    if event_type != "checkout.session.completed" {
        return StatusCode::OK;
    }

    let order_id = payload["data"]["object"]["metadata"]["order_id"].as_str().unwrap_or("").to_string();
    let amount = payload["data"]["object"]["amount_total"].as_i64().unwrap_or(0);
    let email = payload["data"]["object"]["customer_email"].as_str().unwrap_or("").to_string();

    println!("[Stripe] payment completed: order={order_id} amount={amount} email={email}");

    // 注文ステータス更新
    {
        let db = state.db.lock().unwrap();
        let _ = db.execute(
            "UPDATE orders SET status = 'paid', email = ?1 WHERE id = ?2",
            rusqlite::params![&email, &order_id],
        );
    }

    // チャリンへプッシュ通知（売上通知）
    let oid = order_id.to_string();
    tokio::spawn(async move {
        notify_charin(amount, &oid).await;
    });

    StatusCode::OK
}

/// チャリンアプリにAPNsプッシュ通知を送る
async fn notify_charin(amount: i64, order_id: &str) {
    // チャリンのプッシュサーバーまたはWebhook
    // 現時点はログのみ。APNs/FCM統合は後続実装。
    println!("[Charin] revenue notification: {} JPY (order: {})", amount, order_id);

    // enablerdaoのWebhook統合エンドポイント（将来）
    let webhook_url = std::env::var("CHARIN_WEBHOOK_URL").unwrap_or_default();
    if !webhook_url.is_empty() {
        let client = reqwest::Client::new();
        let _ = client.post(&webhook_url)
            .json(&serde_json::json!({
                "type": "revenue",
                "source": "kagi",
                "amount": amount,
                "currency": "jpy",
                "order_id": order_id,
                "timestamp": Utc::now().to_rfc3339(),
            }))
            .send()
            .await;
    }
}

// ============================================================
// MARK: - チャリン連携 API
// ============================================================

#[derive(Deserialize)]
struct CharinRegisterRequest {
    user_id: String,
    push_token: String,
}

/// POST /api/v1/charin/register — チャリンアプリのプッシュトークン登録
async fn charin_register_token(
    State(state): State<Arc<AppState>>,
    Json(body): Json<CharinRegisterRequest>,
) -> StatusCode {
    let db = state.db.lock().unwrap();
    match db.execute(
        "INSERT OR REPLACE INTO charin_push_tokens (user_id, push_token) VALUES (?1, ?2)",
        rusqlite::params![body.user_id, body.push_token],
    ) {
        Ok(_) => StatusCode::CREATED,
        Err(_) => StatusCode::INTERNAL_SERVER_ERROR,
    }
}

/// APNs プッシュ通知送信
async fn send_apns_push(device_token: String, payload: serde_json::Value) {
    send_apns_push_with_topic(device_token, payload, None).await;
}

async fn send_apns_push_with_topic(device_token: String, payload: serde_json::Value, override_topic: Option<&str>) {
    let key_b64 = match std::env::var("APNS_KEY_B64") {
        Ok(k) if !k.is_empty() => k,
        _ => { println!("[APNs] No APNS_KEY_B64 configured"); return; }
    };
    let key_id = std::env::var("APNS_KEY_ID").unwrap_or_default();
    let team_id = std::env::var("APNS_TEAM_ID").unwrap_or_default();
    let topic = override_topic.map(|s| s.to_string())
        .unwrap_or_else(|| std::env::var("APNS_TOPIC").unwrap_or("com.enablerdao.charin".to_string()));

    if key_id.is_empty() || team_id.is_empty() {
        println!("[APNs] Missing KEY_ID or TEAM_ID");
        return;
    }

    // Decode p8 key
    let key_pem = match base64::Engine::decode(&base64::engine::general_purpose::STANDARD, &key_b64) {
        Ok(k) => k,
        Err(e) => { println!("[APNs] Key decode error: {e}"); return; }
    };

    // Create JWT
    let now = chrono::Utc::now().timestamp() as u64;
    let header = jsonwebtoken::Header {
        alg: jsonwebtoken::Algorithm::ES256,
        kid: Some(key_id.clone()),
        ..Default::default()
    };
    let claims = serde_json::json!({
        "iss": team_id,
        "iat": now,
    });
    let encoding_key = match jsonwebtoken::EncodingKey::from_ec_pem(&key_pem) {
        Ok(k) => k,
        Err(e) => { println!("[APNs] JWT key error: {e}"); return; }
    };
    let jwt = match jsonwebtoken::encode(&header, &claims, &encoding_key) {
        Ok(t) => t,
        Err(e) => { println!("[APNs] JWT encode error: {e}"); return; }
    };

    // Send to APNs (development server for debug builds)
    let apns_url = format!(
        "https://api.development.push.apple.com/3/device/{}",
        device_token
    );

    let client = reqwest::Client::builder()
        .http2_prior_knowledge()
        .build()
        .unwrap_or_default();

    match client.post(&apns_url)
        .header("authorization", format!("bearer {jwt}"))
        .header("apns-topic", &topic)
        .header("apns-push-type", "alert")
        .header("apns-priority", "10")
        .json(&payload)
        .send()
        .await
    {
        Ok(resp) => {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            if status.is_success() {
                println!("[APNs] Push sent to {}...", &device_token[..16.min(device_token.len())]);
            } else {
                println!("[APNs] Push failed {status}: {body}");
            }
        }
        Err(e) => println!("[APNs] Request error: {e}"),
    }
}

/// POST /api/v1/charin/apikey — APIキー発行
#[derive(Deserialize)]
struct CharinApiKeyRequest {
    user_label: String,
}

async fn charin_create_apikey(
    State(state): State<Arc<AppState>>,
    Json(body): Json<CharinApiKeyRequest>,
) -> (StatusCode, Json<serde_json::Value>) {
    let key = format!("chk_{}", uuid::Uuid::new_v4().to_string().replace("-", ""));
    let db = state.db.lock().unwrap();
    match db.execute(
        "INSERT INTO charin_api_keys (api_key, user_label) VALUES (?1, ?2)",
        rusqlite::params![key, body.user_label],
    ) {
        Ok(_) => {
            println!("[Charin] API key created for: {}", body.user_label);
            (StatusCode::CREATED, Json(serde_json::json!({"api_key": key, "user_label": body.user_label})))
        }
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({"error": e.to_string()}))),
    }
}

/// POST /api/v1/charin/income — 外部サービスから収入データを登録 (APIキー必須)
#[derive(Deserialize)]
struct CharinIncomeRequest {
    api_key: String,
    source: String,
    amount: i64,
    #[serde(default = "default_jpy")]
    currency: String,
    #[serde(default = "default_subscription")]
    category: String,
    #[serde(default)]
    memo: String,
    #[serde(default)]
    email: String,
}
fn default_jpy() -> String { "JPY".to_string() }
fn default_subscription() -> String { "subscription".to_string() }

async fn charin_add_income(
    State(state): State<Arc<AppState>>,
    Json(body): Json<CharinIncomeRequest>,
) -> (StatusCode, Json<serde_json::Value>) {
    // Validate API key
    {
        let db = state.db.lock().unwrap();
        let valid: bool = db.query_row(
            "SELECT COUNT(*) FROM charin_api_keys WHERE api_key = ?1",
            rusqlite::params![body.api_key], |row| row.get::<_, i64>(0)
        ).unwrap_or(0) > 0;
        if !valid {
            return (StatusCode::UNAUTHORIZED, Json(serde_json::json!({"error": "invalid api_key"})));
        }
    }

    let db = state.db.lock().unwrap();
    match db.execute(
        "INSERT INTO charin_pending_income (api_key, source, amount, currency, category, memo, email) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        rusqlite::params![body.api_key, body.source, body.amount, body.currency, body.category, body.memo, body.email],
    ) {
        Ok(_) => {
            println!("[Charin] Income: {} {} {} → key:{}", body.amount, body.currency, body.source, &body.api_key[..12]);

            // Send APNs push to all devices registered for this user
            let tokens: Vec<String> = {
                // Find user_id from push_tokens that matches this api_key's user
                // For simplicity, send to ALL registered charin devices
                let mut stmt = db.prepare("SELECT push_token FROM charin_push_tokens").unwrap();
                stmt.query_map([], |row| row.get::<_, String>(0))
                    .unwrap().filter_map(|r| r.ok()).collect()
            };
            drop(db);

            // Send APNs push notifications
            for token in &tokens {
                let payload = serde_json::json!({
                    "aps": {
                        "alert": {
                            "title": "チャリン！💰",
                            "body": format!("{} {} {}", body.source, body.amount, body.currency)
                        },
                        "sound": "charin.wav",
                        "badge": 1
                    },
                    "type": "revenue",
                    "source": body.source,
                    "amount": body.amount,
                    "currency": body.currency
                });
                tokio::spawn(send_apns_push(token.clone(), payload));
            }

            (StatusCode::CREATED, Json(serde_json::json!({"ok": true, "push_sent": tokens.len()})))
        }
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({"error": e.to_string()}))),
    }
}

/// GET /api/v1/charin/income/pending?api_key=xxx — 未取得の収入データ (APIキー認証)
async fn charin_get_pending(
    State(state): State<Arc<AppState>>,
    axum::extract::Query(params): axum::extract::Query<std::collections::HashMap<String, String>>,
) -> (StatusCode, Json<serde_json::Value>) {
    let api_key = params.get("api_key").cloned().unwrap_or_default();
    if api_key.is_empty() {
        return (StatusCode::UNAUTHORIZED, Json(serde_json::json!({"error": "api_key required"})));
    }

    let db = state.db.lock().unwrap();
    // Validate key
    let valid: bool = db.query_row(
        "SELECT COUNT(*) FROM charin_api_keys WHERE api_key = ?1",
        rusqlite::params![api_key], |row| row.get::<_, i64>(0)
    ).unwrap_or(0) > 0;
    if !valid {
        return (StatusCode::UNAUTHORIZED, Json(serde_json::json!({"error": "invalid api_key"})));
    }

    let mut stmt = db.prepare(
        "SELECT id, source, amount, currency, category, memo, email, created_at FROM charin_pending_income WHERE api_key = ?1 AND fetched = 0 ORDER BY id"
    ).unwrap();
    let rows: Vec<serde_json::Value> = stmt.query_map(rusqlite::params![api_key], |row| {
        Ok(serde_json::json!({
            "id": row.get::<_, i64>(0)?,
            "source": row.get::<_, String>(1)?,
            "amount": row.get::<_, i64>(2)?,
            "currency": row.get::<_, String>(3)?,
            "category": row.get::<_, String>(4)?,
            "memo": row.get::<_, String>(5)?,
            "email": row.get::<_, String>(6)?,
            "created_at": row.get::<_, String>(7)?,
        }))
    }).unwrap().filter_map(|r| r.ok()).collect();

    // Mark fetched
    for r in &rows {
        if let Some(id) = r["id"].as_i64() {
            let _ = db.execute("UPDATE charin_pending_income SET fetched = 1 WHERE id = ?1", rusqlite::params![id]);
        }
    }

    (StatusCode::OK, Json(serde_json::json!({"count": rows.len(), "income": rows})))
}

/// POST /api/v1/charin/wh/{api_key} — ユーザー専用Stripe Webhook
/// Stripe Dashboardに https://kagi-server.fly.dev/api/v1/charin/wh/chk_xxx を貼るだけ
async fn charin_stripe_webhook(
    State(state): State<Arc<AppState>>,
    Path(api_key): Path<String>,
    body: String,
) -> StatusCode {
    // Validate API key
    {
        let db = state.db.lock().unwrap();
        let valid: bool = db.query_row(
            "SELECT COUNT(*) FROM charin_api_keys WHERE api_key = ?1",
            rusqlite::params![api_key], |row| row.get::<_, i64>(0)
        ).unwrap_or(0) > 0;
        if !valid {
            println!("[Charin WH] Invalid key: {}", &api_key[..12.min(api_key.len())]);
            return StatusCode::UNAUTHORIZED;
        }
    }

    let event: serde_json::Value = match serde_json::from_str(&body) {
        Ok(v) => v,
        Err(_) => return StatusCode::BAD_REQUEST,
    };

    let event_type = event["type"].as_str().unwrap_or("");
    println!("[Charin WH] {event_type} for key:{}", &api_key[..12.min(api_key.len())]);

    match event_type {
        "checkout.session.completed" | "payment_intent.succeeded" => {
            let obj = &event["data"]["object"];
            let (email, name, amount, currency) = if event_type == "checkout.session.completed" {
                (
                    obj["customer_details"]["email"].as_str().unwrap_or("").to_string(),
                    obj["customer_details"]["name"].as_str().unwrap_or("").to_string(),
                    obj["amount_total"].as_i64().unwrap_or(0),
                    obj["currency"].as_str().unwrap_or("jpy").to_uppercase(),
                )
            } else {
                (
                    "".to_string(),
                    "".to_string(),
                    obj["amount"].as_i64().unwrap_or(0),
                    obj["currency"].as_str().unwrap_or("jpy").to_uppercase(),
                )
            };

            // Convert cents to actual amount for non-JPY
            let display_amount = if currency != "JPY" { amount / 100 } else { amount };

            let source = if name.is_empty() {
                format!("Stripe ({})", &email[..email.find('@').unwrap_or(email.len())])
            } else {
                format!("Stripe ({name})")
            };

            let db = state.db.lock().unwrap();
            let _ = db.execute(
                "INSERT INTO charin_pending_income (api_key, source, amount, currency, category, memo, email) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                rusqlite::params![api_key, source, display_amount, currency, "one-time", format!("{email}"), email],
            );
            println!("[Charin WH] Income: {display_amount} {currency} from {email}");

            // Send push
            let tokens: Vec<String> = {
                let mut stmt = db.prepare("SELECT push_token FROM charin_push_tokens").unwrap();
                stmt.query_map([], |row| row.get::<_, String>(0))
                    .unwrap().filter_map(|r| r.ok()).collect()
            };
            drop(db);
            for token in &tokens {
                let payload = serde_json::json!({
                    "aps": {
                        "alert": {"title": "チャリン！💰", "body": format!("{source} {display_amount} {currency}")},
                        "sound": "charin.wav", "badge": 1
                    },
                    "type": "revenue", "source": source, "amount": display_amount, "currency": currency
                });
                tokio::spawn(send_apns_push(token.clone(), payload));
            }
        }
        "invoice.paid" => {
            let obj = &event["data"]["object"];
            let email = obj["customer_email"].as_str().unwrap_or("").to_string();
            let amount = obj["amount_paid"].as_i64().unwrap_or(0);
            let currency = obj["currency"].as_str().unwrap_or("jpy").to_uppercase();
            let display_amount = if currency != "JPY" { amount / 100 } else { amount };
            let lines = obj["lines"]["data"].as_array();
            let desc = lines.and_then(|l| l.first())
                .and_then(|l| l["description"].as_str())
                .unwrap_or("Subscription");

            let db = state.db.lock().unwrap();
            let _ = db.execute(
                "INSERT INTO charin_pending_income (api_key, source, amount, currency, category, memo, email) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                rusqlite::params![api_key, format!("Stripe ({desc})"), display_amount, currency, "subscription", email, email],
            );
            println!("[Charin WH] Subscription: {display_amount} {currency} — {desc}");

            let tokens: Vec<String> = {
                let mut stmt = db.prepare("SELECT push_token FROM charin_push_tokens").unwrap();
                stmt.query_map([], |row| row.get::<_, String>(0))
                    .unwrap().filter_map(|r| r.ok()).collect()
            };
            drop(db);
            for token in &tokens {
                let payload = serde_json::json!({
                    "aps": {
                        "alert": {"title": "チャリン！💰", "body": format!("{desc} {display_amount} {currency}")},
                        "sound": "charin.wav", "badge": 1
                    },
                    "type": "revenue", "source": desc, "amount": display_amount, "currency": currency
                });
                tokio::spawn(send_apns_push(token.clone(), payload));
            }
        }
        _ => {}
    }

    StatusCode::OK
}

// ============================================================
// MARK: - Beds24 予約通知
// ============================================================

#[derive(Deserialize)]
struct Beds24RegisterRequest {
    user_id: String,
    refresh_token: String,
    push_token: String,
    platform: Option<String>,
}

/// POST /api/v1/beds24/register — Beds24アカウント+プッシュトークン登録
async fn beds24_register(
    State(state): State<Arc<AppState>>,
    Json(body): Json<Beds24RegisterRequest>,
) -> StatusCode {
    let db = state.db.lock().unwrap();
    let platform = body.platform.as_deref().unwrap_or("apns");
    db.execute(
        "INSERT INTO beds24_accounts (user_id, refresh_token, push_token, platform)
         VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT(user_id, refresh_token) DO UPDATE SET push_token=?3, platform=?4",
        rusqlite::params![body.user_id, body.refresh_token, body.push_token, platform],
    ).ok();
    println!("[Beds24] Registered account for user={}", body.user_id);
    StatusCode::OK
}

#[derive(Deserialize)]
struct Beds24UnregisterRequest {
    user_id: String,
}

/// POST /api/v1/beds24/unregister — 登録解除
async fn beds24_unregister(
    State(state): State<Arc<AppState>>,
    Json(body): Json<Beds24UnregisterRequest>,
) -> StatusCode {
    let db = state.db.lock().unwrap();
    db.execute("DELETE FROM beds24_accounts WHERE user_id = ?1", [&body.user_id]).ok();
    StatusCode::OK
}

/// Beds24 APIからトークン取得
async fn beds24_get_token(refresh_token: &str) -> Option<String> {
    let client = reqwest::Client::new();
    let resp = client
        .get("https://api.beds24.com/v2/authentication/token")
        .header("refreshToken", refresh_token)
        .timeout(std::time::Duration::from_secs(15))
        .send()
        .await
        .ok()?;
    let json: serde_json::Value = resp.json().await.ok()?;
    json["token"].as_str().map(|s| s.to_string())
}

/// Beds24 APIから予約取得
async fn beds24_fetch_bookings(token: &str) -> Vec<serde_json::Value> {
    let client = reqwest::Client::new();
    let resp = client
        .get("https://api.beds24.com/v2/bookings?includeGuests=true")
        .header("token", token)
        .header("Accept", "application/json")
        .timeout(std::time::Duration::from_secs(15))
        .send()
        .await;
    let resp = match resp {
        Ok(r) if r.status().is_success() => r,
        _ => return vec![],
    };
    let json: serde_json::Value = match resp.json().await {
        Ok(j) => j,
        Err(_) => return vec![],
    };
    if let Some(arr) = json.get("data").and_then(|d| d.as_array()) {
        arr.clone()
    } else if let Some(arr) = json.as_array() {
        arr.clone()
    } else {
        vec![]
    }
}

/// Beds24 APIから予約のメッセージ取得
async fn beds24_fetch_messages(token: &str, booking_id: i64) -> Vec<serde_json::Value> {
    let client = reqwest::Client::new();
    let url = format!("https://api.beds24.com/v2/bookings/messages?bookingId={booking_id}");
    let resp = client
        .get(&url)
        .header("token", token)
        .header("Accept", "application/json")
        .timeout(std::time::Duration::from_secs(15))
        .send()
        .await;
    let resp = match resp {
        Ok(r) if r.status().is_success() => r,
        _ => return vec![],
    };
    let json: serde_json::Value = match resp.json().await {
        Ok(j) => j,
        Err(_) => return vec![],
    };
    if let Some(arr) = json.get("data").and_then(|d| d.as_array()) {
        arr.clone()
    } else if let Some(arr) = json.as_array() {
        arr.clone()
    } else {
        vec![]
    }
}

/// メッセージがゲストからのものか判定
fn is_guest_message(msg: &serde_json::Value) -> bool {
    if let Some(from) = msg.get("from").and_then(|v| v.as_str()) {
        return from.to_lowercase() == "guest";
    }
    if let Some(dir) = msg.get("direction").and_then(|v| v.as_str()) {
        let d = dir.to_lowercase();
        return d == "in" || d == "received";
    }
    if let Some(t) = msg.get("type").and_then(|v| v.as_str()) {
        return t.to_lowercase() == "received";
    }
    false
}

/// メッセージのIDを取得（数値/文字列両対応）
fn get_message_id(msg: &serde_json::Value, index: usize) -> String {
    if let Some(id) = msg.get("id").and_then(|v| v.as_i64()) {
        return id.to_string();
    }
    if let Some(id) = msg.get("id").and_then(|v| v.as_str()) {
        return id.to_string();
    }
    format!("idx-{index}")
}

/// 5分間隔でBeds24をポーリングし、新規/変更を検知してAPNs通知
async fn beds24_poll_loop(state: Arc<AppState>) {
    println!("[Beds24] Poll loop started (5min interval)");
    loop {
        beds24_poll_once(&state).await;
        tokio::time::sleep(std::time::Duration::from_secs(300)).await;
    }
}

async fn beds24_poll_once(state: &Arc<AppState>) {
    let accounts: Vec<(i64, String, String, String)> = {
        let db = state.db.lock().unwrap();
        let mut stmt = match db.prepare(
            "SELECT id, refresh_token, push_token, platform FROM beds24_accounts"
        ) {
            Ok(s) => s,
            Err(_) => return,
        };
        stmt.query_map([], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
            ))
        }).unwrap().filter_map(|r| r.ok()).collect()
    };

    if accounts.is_empty() { return; }

    for (account_id, refresh_token, push_token, _platform) in &accounts {
        let token = match beds24_get_token(refresh_token).await {
            Some(t) => t,
            None => {
                println!("[Beds24] Token refresh failed for account {account_id}");
                continue;
            }
        };

        let bookings = beds24_fetch_bookings(&token).await;

        let seen: std::collections::HashMap<String, (String, i64)> = {
            let db = state.db.lock().unwrap();
            let mut stmt = match db.prepare(
                "SELECT booking_ext_id, status, amount FROM beds24_seen_bookings WHERE account_id = ?1"
            ) {
                Ok(s) => s,
                Err(_) => continue,
            };
            stmt.query_map([account_id], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    (row.get::<_, String>(1)?, row.get::<_, i64>(2)?),
                ))
            }).unwrap().filter_map(|r| r.ok()).collect()
        };

        for b in &bookings {
            let bid = b.get("id").and_then(|v| v.as_i64()).unwrap_or(0);
            let ext_id = format!("beds24-{bid}");
            let status = b.get("status").and_then(|v| v.as_str()).unwrap_or("");
            let amount = b.get("price").and_then(|v| v.as_f64()).unwrap_or(0.0) as i64;
            let guest_first = b.get("firstName").and_then(|v| v.as_str()).unwrap_or("");
            let guest_last = b.get("lastName").and_then(|v| v.as_str()).unwrap_or("");
            let guest_name = if !guest_last.is_empty() || !guest_first.is_empty() {
                format!("{} {}", guest_last, guest_first).trim().to_string()
            } else {
                "ゲスト".to_string()
            };
            let arrival = b.get("arrival").and_then(|v| v.as_str()).unwrap_or("");
            let channel = b.get("channel").and_then(|v| v.as_str())
                .or_else(|| b.get("referer").and_then(|v| v.as_str()))
                .unwrap_or("direct");

            if let Some((old_status, old_amount)) = seen.get(&ext_id) {
                // ステータスまたは金額が変わったら通知
                if old_status != status || *old_amount != amount {
                    let msg = if old_status != status {
                        format!("{}様の予約ステータスが変更: {} → {}", guest_name, old_status, status)
                    } else {
                        format!("{}様の予約金額が変更: ¥{} → ¥{}", guest_name, old_amount, amount)
                    };
                    let payload = serde_json::json!({
                        "aps": {
                            "alert": { "title": "予約更新", "body": msg },
                            "sound": "default", "badge": 1
                        },
                        "type": "beds24_booking_updated",
                        "booking_id": bid
                    });
                    send_apns_push_with_topic(push_token.clone(), payload, Some("com.enablerdao.kacha")).await;

                    let db = state.db.lock().unwrap();
                    db.execute(
                        "UPDATE beds24_seen_bookings SET status=?1, amount=?2 WHERE account_id=?3 AND booking_ext_id=?4",
                        rusqlite::params![status, amount, account_id, ext_id],
                    ).ok();
                }
            } else {
                // 新規予約 → 通知
                let body_text = format!("{}様 · {} · ¥{} · {}", guest_name, arrival, amount, channel);
                let payload = serde_json::json!({
                    "aps": {
                        "alert": { "title": "新しい予約", "body": body_text },
                        "sound": "default", "badge": 1
                    },
                    "type": "beds24_new_booking",
                    "booking_id": bid
                });
                send_apns_push_with_topic(push_token.clone(), payload, Some("com.enablerdao.kacha")).await;
                println!("[Beds24] New booking: {ext_id} ({guest_name})");

                let db = state.db.lock().unwrap();
                db.execute(
                    "INSERT OR IGNORE INTO beds24_seen_bookings (account_id, booking_ext_id, status, amount) VALUES (?1, ?2, ?3, ?4)",
                    rusqlite::params![account_id, ext_id, status, amount],
                ).ok();
            }
        }

        // --- メッセージポーリング: アクティブ予約のゲストメッセージをチェック ---
        let active_booking_ids: Vec<(i64, String)> = bookings.iter().filter_map(|b| {
            let bid = b.get("id").and_then(|v| v.as_i64())?;
            let status = b.get("status").and_then(|v| v.as_str()).unwrap_or("");
            // cancelled以外の予約のメッセージをチェック
            if status == "cancelled" { return None; }
            let guest_first = b.get("firstName").and_then(|v| v.as_str()).unwrap_or("");
            let guest_last = b.get("lastName").and_then(|v| v.as_str()).unwrap_or("");
            let guest_name = if !guest_last.is_empty() || !guest_first.is_empty() {
                format!("{} {}", guest_last, guest_first).trim().to_string()
            } else {
                "ゲスト".to_string()
            };
            Some((bid, guest_name))
        }).collect();

        for (bid, guest_name) in &active_booking_ids {
            let messages = beds24_fetch_messages(&token, *bid).await;
            // ゲストからのメッセージのみ抽出
            let guest_msgs: Vec<(usize, &serde_json::Value)> = messages.iter()
                .enumerate()
                .filter(|(_, m)| is_guest_message(m))
                .collect();

            if let Some((idx, latest)) = guest_msgs.last() {
                let msg_id = get_message_id(latest, *idx);

                // 前回確認したメッセージIDを取得
                let last_seen: Option<String> = {
                    let db = state.db.lock().unwrap();
                    db.prepare("SELECT last_message_id FROM beds24_seen_messages WHERE account_id=?1 AND booking_id=?2")
                        .ok()
                        .and_then(|mut stmt| {
                            stmt.query_row(rusqlite::params![account_id, bid], |row| row.get(0)).ok()
                        })
                };

                match &last_seen {
                    None => {
                        // 初回: IDを記録するだけ（通知しない）
                        let db = state.db.lock().unwrap();
                        db.execute(
                            "INSERT OR REPLACE INTO beds24_seen_messages (account_id, booking_id, last_message_id, last_checked_at) VALUES (?1, ?2, ?3, datetime('now'))",
                            rusqlite::params![account_id, bid, msg_id],
                        ).ok();
                    }
                    Some(prev_id) if *prev_id != msg_id => {
                        // 新着メッセージ → APNs通知
                        let msg_text = latest.get("message")
                            .or_else(|| latest.get("body"))
                            .or_else(|| latest.get("text"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("");
                        let preview: String = msg_text.chars().take(100).collect();

                        let payload = serde_json::json!({
                            "aps": {
                                "alert": {
                                    "title": format!("{} からメッセージ", guest_name),
                                    "body": preview
                                },
                                "sound": "default",
                                "badge": 1
                            },
                            "type": "beds24_guest_message",
                            "booking_id": bid
                        });
                        send_apns_push_with_topic(push_token.clone(), payload, Some("com.enablerdao.kacha")).await;
                        println!("[Beds24] New guest message from {} (booking {})", guest_name, bid);

                        // 更新
                        let db = state.db.lock().unwrap();
                        db.execute(
                            "INSERT OR REPLACE INTO beds24_seen_messages (account_id, booking_id, last_message_id, last_checked_at) VALUES (?1, ?2, ?3, datetime('now'))",
                            rusqlite::params![account_id, bid, msg_id],
                        ).ok();
                    }
                    _ => {} // 変化なし
                }
            }

            // API rate limit対策: 予約間に少し待つ
            tokio::time::sleep(std::time::Duration::from_millis(200)).await;
        }

        // ポーリング時刻更新
        let db = state.db.lock().unwrap();
        db.execute(
            "UPDATE beds24_accounts SET last_polled_at = datetime('now') WHERE id = ?1",
            [account_id],
        ).ok();
    }
}

// ── ChatWeb Vault — セキュアキー管理 ──
// 値はクライアント側でAES-256-GCMで暗号化された状態で送受信。
// サーバーは暗号化blobを保存するだけ。平文のキーはサーバーに存在しない。

#[derive(Deserialize)]
struct VaultStoreReq {
    session_token: String,
    key_name: String,
    encrypted_value: String,   // AES-256-GCM encrypted, base64
    category: Option<String>,  // "apikey", "password", "token"
}

#[derive(Deserialize)]
struct VaultAuthReq {
    session_token: String,
}

#[derive(Deserialize)]
struct VaultGetReq {
    session_token: String,
    key_name: String,
}

#[derive(Deserialize)]
struct VaultDeleteReq {
    session_token: String,
    key_name: String,
}

#[derive(Serialize)]
struct VaultItem {
    key_name: String,
    encrypted_value: String,
    category: String,
    updated_at: String,
}

fn vault_get_email(db: &Connection, session_token: &str) -> Option<String> {
    // Verify session and get user email
    let user_id: Option<String> = db.query_row(
        "SELECT user_id FROM sessions WHERE token=?1 AND expires_at > datetime('now')",
        [session_token], |r| r.get(0)
    ).ok();
    let uid = user_id?;
    db.query_row("SELECT email FROM users WHERE id=?1", [&uid], |r| r.get(0)).ok()
}

async fn vault_store(State(s): State<Arc<AppState>>, Json(body): Json<VaultStoreReq>) -> impl IntoResponse {
    let db = s.db.lock().unwrap();
    let email = match vault_get_email(&db, &body.session_token) {
        Some(e) => e,
        None => return (StatusCode::UNAUTHORIZED, Json(serde_json::json!({"error":"unauthorized"}))).into_response(),
    };
    let id = Uuid::new_v4().to_string();
    let cat = body.category.as_deref().unwrap_or("apikey");
    db.execute(
        "INSERT OR REPLACE INTO vault_items (id, user_email, key_name, encrypted_value, category, updated_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, datetime('now'))",
        rusqlite::params![id, email, body.key_name, body.encrypted_value, cat],
    ).ok();
    Json(serde_json::json!({"ok": true})).into_response()
}

async fn vault_list(State(s): State<Arc<AppState>>, Json(body): Json<VaultAuthReq>) -> impl IntoResponse {
    let db = s.db.lock().unwrap();
    let email = match vault_get_email(&db, &body.session_token) {
        Some(e) => e,
        None => return (StatusCode::UNAUTHORIZED, Json(serde_json::json!({"error":"unauthorized"}))).into_response(),
    };
    let mut stmt = db.prepare(
        "SELECT key_name, encrypted_value, category, updated_at FROM vault_items WHERE user_email=?1 ORDER BY key_name"
    ).unwrap();
    let items: Vec<VaultItem> = stmt.query_map([&email], |r| Ok(VaultItem {
        key_name: r.get(0)?, encrypted_value: r.get(1)?,
        category: r.get(2)?, updated_at: r.get(3)?,
    })).unwrap().filter_map(|r| r.ok()).collect();
    Json(serde_json::json!({"items": items})).into_response()
}

async fn vault_get(State(s): State<Arc<AppState>>, Json(body): Json<VaultGetReq>) -> impl IntoResponse {
    let db = s.db.lock().unwrap();
    let email = match vault_get_email(&db, &body.session_token) {
        Some(e) => e,
        None => return (StatusCode::UNAUTHORIZED, Json(serde_json::json!({"error":"unauthorized"}))).into_response(),
    };
    let item: Option<VaultItem> = db.query_row(
        "SELECT key_name, encrypted_value, category, updated_at FROM vault_items WHERE user_email=?1 AND key_name=?2",
        rusqlite::params![email, body.key_name],
        |r| Ok(VaultItem { key_name: r.get(0)?, encrypted_value: r.get(1)?, category: r.get(2)?, updated_at: r.get(3)? })
    ).ok();
    match item {
        Some(i) => Json(serde_json::json!({"item": i})).into_response(),
        None => (StatusCode::NOT_FOUND, Json(serde_json::json!({"error":"not_found"}))).into_response(),
    }
}

async fn vault_delete(State(s): State<Arc<AppState>>, Json(body): Json<VaultDeleteReq>) -> impl IntoResponse {
    let db = s.db.lock().unwrap();
    let email = match vault_get_email(&db, &body.session_token) {
        Some(e) => e,
        None => return (StatusCode::UNAUTHORIZED, Json(serde_json::json!({"error":"unauthorized"}))).into_response(),
    };
    db.execute(
        "DELETE FROM vault_items WHERE user_email=?1 AND key_name=?2",
        rusqlite::params![email, body.key_name],
    ).ok();
    Json(serde_json::json!({"ok": true})).into_response()
}
