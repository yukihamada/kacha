use axum::{
    extract::{Path, State},
    http::StatusCode,
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
        .route("/health", get(|| async { "ok" }))
        .layer(CorsLayer::permissive())
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
