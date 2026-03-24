use axum::{
    extract::{Path, State},
    http::{header, StatusCode},
    response::{Html, IntoResponse},
    routing::{delete, get, post},
    Json, Router,
};
use chrono::{DateTime, Utc};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};
use tower_http::cors::CorsLayer;
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
        "CREATE TABLE IF NOT EXISTS shares (
            token       TEXT PRIMARY KEY,
            owner_token TEXT NOT NULL,
            encrypted_data TEXT NOT NULL,
            valid_from  TEXT,
            expires_at  TEXT,
            revoked     INTEGER NOT NULL DEFAULT 0,
            created_at  TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_owner ON shares(owner_token);",
    )
    .expect("init db");
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
<title>カチャ — ホームをシェア</title>
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
<h1>カチャ</h1>
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
    Html(r#"<!DOCTYPE html><html lang="ja"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>カチャ プライバシーポリシー</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,'Hiragino Sans',sans-serif;background:#0A0A12;color:#eaeaf2;padding:24px;max-width:700px;margin:0 auto;line-height:1.8}h1{font-size:22px;margin-bottom:16px;color:#E8A838}h2{font-size:16px;margin:20px 0 8px;color:#3B9FE8}p,li{font-size:14px;color:#aaa;margin-bottom:8px}ul{padding-left:20px}</style></head><body>
<h1>カチャ プライバシーポリシー</h1>
<p>最終更新日: 2026年3月24日</p>
<h2>1. 収集するデータ</h2>
<p>カチャはユーザーの個人データを外部サーバーに収集・送信しません。すべてのデータ（デバイス設定、APIキー、予約情報等）はiPhoneのローカルストレージに保存されます。</p>
<h2>2. E2Eシェア</h2>
<p>シェア機能を使用した場合、AES-256-GCMで暗号化されたデータのみがサーバーに保存されます。復号キーはサーバーに送信されません。暗号化データは期限切れ後にアクセス不能になります。</p>
<h2>3. 外部サービス連携</h2>
<p>SwitchBot、Sesame、Philips Hue、Nuki、Beds24等の外部サービスとの通信は、各サービスのAPIサーバーと直接行われます。カチャのサーバーを経由しません。</p>
<h2>4. 位置情報</h2>
<p>ジオフェンス機能を有効にした場合のみ、位置情報を使用します。位置情報は端末内でのみ処理され、外部に送信されません。</p>
<h2>5. 広告・トラッキング</h2>
<p>カチャは広告SDK、アナリティクスSDKを一切使用していません。利用状況の追跡は行いません。</p>
<h2>6. データの削除</h2>
<p>アプリを削除すると、ローカルストレージのデータは削除されます。Keychainに保存されたバックアップデータは、iOSの設定からKeychainを削除することで消去できます。</p>
<h2>7. お問い合わせ</h2>
<p>プライバシーに関するお問い合わせ: info@enablerdao.com</p>
<p>運営: Enabler DAO / Yuki Hamada</p>
</body></html>"#.to_string())
}

async fn support_page() -> Html<String> {
    Html(r#"<!DOCTYPE html><html lang="ja"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>カチャ サポート</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,'Hiragino Sans',sans-serif;background:#0A0A12;color:#eaeaf2;padding:24px;max-width:700px;margin:0 auto;line-height:1.8}h1{font-size:22px;margin-bottom:16px;color:#E8A838}h2{font-size:16px;margin:20px 0 8px;color:#3B9FE8}p{font-size:14px;color:#aaa;margin-bottom:8px}a{color:#3B9FE8}</style></head><body>
<h1>カチャ サポート</h1>
<h2>よくある質問</h2>
<p><strong>Q: データはどこに保存されますか？</strong><br>A: すべてのデータはiPhoneのローカルに保存されます。外部サーバーにはE2E暗号化されたシェアデータのみ保存されます。</p>
<p><strong>Q: アプリを再インストールしてもデータは残りますか？</strong><br>A: はい。Keychainバックアップにより、再インストール後も自動復元されます。</p>
<p><strong>Q: Beds24の予約が同期されません</strong><br>A: 設定→Beds24で「接続する」を確認してください。Invite CodeはBeds24の設定→API v2から作成できます。</p>
<p><strong>Q: オートロック解除が動きません</strong><br>A: SwitchBotアプリでBotの動作を確認し、カチャの設定でBotデバイスを選択してください。</p>
<h2>お問い合わせ</h2>
<p>メール: <a href="mailto:info@enablerdao.com">info@enablerdao.com</a></p>
<p>GitHub: <a href="https://github.com/yukihamada/kacha">yukihamada/kacha</a></p>
</body></html>"#.to_string())
}

#[tokio::main]
async fn main() {
    let db_path = std::env::var("DATABASE_PATH").unwrap_or_else(|_| "kacha.db".into());
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
        .route("/health", get(|| async { "ok" }))
        .layer(
            CorsLayer::new()
                .allow_origin("https://kacha.pasha.run".parse::<http::HeaderValue>().unwrap())
                .allow_methods([http::Method::GET, http::Method::POST, http::Method::DELETE])
                .allow_headers([header::CONTENT_TYPE])
        )
        .with_state(state);

    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(8080);
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{port}"))
        .await
        .expect("bind");
    println!("kacha-server listening on :{port}");
    axum::serve(listener, app).await.expect("serve");
}
