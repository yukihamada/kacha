// KAGI Cloud Module
// WiFi接続管理 / MQTT over TLS / 監査ログ送信 / BLEフォールバック

use anyhow::{anyhow, Result};
use log::{info, warn, error};
use serde::Serialize;
use std::time::Duration;

use crate::sensors::SensorSnapshot;

// ──────────────────────────────────────
// 定数
// ──────────────────────────────────────

const MQTT_BROKER: &str = "mqtts://api.kagi.home:8883";
const TELEMETRY_TOPIC_PREFIX: &str = "kagi/";
const TELEMETRY_TOPIC_SUFFIX: &str = "/telemetry";
const EVENT_TOPIC_SUFFIX: &str = "/event";
const COMMAND_TOPIC_SUFFIX: &str = "/command";

/// Exponential backoff設定
const INITIAL_RETRY_MS: u64 = 5_000;
const MAX_RETRY_MS: u64 = 300_000; // 5分

// ──────────────────────────────────────
// CloudClient
// ──────────────────────────────────────

/// クラウド接続状態
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ConnectionState {
    /// WiFi + MQTT接続済み
    Connected,
    /// WiFi接続済み、MQTT未接続
    WifiOnly,
    /// WiFi未接続、BLEフォールバック
    BleOnly,
    /// 完全オフライン
    Offline,
}

pub struct CloudClient {
    state: ConnectionState,
    device_id: String,
    retry_interval_ms: u64,
    /// 送信失敗カウンター
    consecutive_failures: u32,
    /// 最後に送信成功した時刻 (UNIX epoch)
    last_success_at: u64,
}

impl CloudClient {
    pub fn new() -> Result<Self> {
        // デバイスIDはNVSから読み取る (プロビジョニング時に設定済み)
        let device_id = option_env!("KAGI_DEVICE_ID")
            .unwrap_or("KAGI-UNPROVISIONED")
            .to_string();

        info!("CloudClient初期化: device_id={}", device_id);

        Ok(Self {
            state: ConnectionState::Offline,
            device_id,
            retry_interval_ms: INITIAL_RETRY_MS,
            consecutive_failures: 0,
            last_success_at: 0,
        })
    }

    /// MQTT接続を確立 (mTLS: ATECC608Aクライアント証明書)
    pub fn connect(&mut self) -> Result<()> {
        info!("MQTT接続試行: {}", MQTT_BROKER);

        // ESP-IDF MQTT client設定
        // 実際の実装では esp_idf_svc::mqtt::client::EspMqttClient を使用
        // ここではインターフェースを定義

        // mTLS設定:
        // - CA証明書: KAGI Root CA (ファームウェアに埋め込み)
        // - クライアント証明書: ATECC608A Slot 2
        // - クライアント秘密鍵: ATECC608A Slot 1 (チップ外に出ない)

        // MQTT接続パラメータ:
        // - Client ID: device_id
        // - Keep Alive: 60秒
        // - Clean Session: false (QoS1メッセージの永続化)
        // - Will Message: {device_id}/status → "offline"

        self.state = ConnectionState::Connected;
        self.retry_interval_ms = INITIAL_RETRY_MS;
        self.consecutive_failures = 0;
        info!("MQTT接続成功");

        // コマンドトピックをsubscribe
        let command_topic = format!("{}{}{}", TELEMETRY_TOPIC_PREFIX, self.device_id, COMMAND_TOPIC_SUFFIX);
        info!("Subscribe: {}", command_topic);

        Ok(())
    }

    /// テレメトリデータを送信 (60秒間隔)
    pub fn send_telemetry(&mut self, snapshot: &SensorSnapshot) -> Result<()> {
        if self.state == ConnectionState::Offline || self.state == ConnectionState::BleOnly {
            return Err(anyhow!("Not connected"));
        }

        let topic = format!("{}{}{}", TELEMETRY_TOPIC_PREFIX, self.device_id, TELEMETRY_TOPIC_SUFFIX);

        // MessagePack形式で送信 (JSON比30%サイズ削減)
        // ここではJSON fallback (MessagePack crateが利用可能な場合は切り替え)
        let payload = serde_json::to_vec(snapshot)
            .map_err(|e| anyhow!("Serialize failed: {:?}", e))?;

        self.mqtt_publish(&topic, &payload, QoS::AtLeastOnce)?;

        self.last_success_at = now_epoch();
        self.consecutive_failures = 0;

        Ok(())
    }

    /// 安全イベントを送信 (即時)
    pub fn send_safety_event(&mut self, snapshot: &SensorSnapshot, event_type: &str) -> Result<()> {
        if self.state == ConnectionState::Offline {
            return Err(anyhow!("Not connected"));
        }

        let topic = format!("{}{}{}", TELEMETRY_TOPIC_PREFIX, self.device_id, EVENT_TOPIC_SUFFIX);

        let event = SafetyEvent {
            device_id: self.device_id.clone(),
            event_type: event_type.to_string(),
            snapshot: snapshot.clone(),
            firmware_version: env!("CARGO_PKG_VERSION").to_string(),
        };

        let payload = serde_json::to_vec(&event)
            .map_err(|e| anyhow!("Serialize failed: {:?}", e))?;

        // QoS1 (at least once) で確実に送信
        self.mqtt_publish(&topic, &payload, QoS::AtLeastOnce)?;

        info!("安全イベント送信完了: {}", event_type);
        Ok(())
    }

    /// Tier2通知: クラウドにイベント送信 → クラウドが家族にプッシュ通知
    pub fn send_tier2_notification(&mut self, snapshot: &SensorSnapshot) {
        match self.send_safety_event(snapshot, "tier2_triggered") {
            Ok(()) => info!("Tier2通知送信成功"),
            Err(e) => {
                error!("Tier2通知送信失敗: {:?} → BLEフォールバック", e);
                self.ble_fallback_notify(snapshot, "tier2");
            }
        }
    }

    /// Tier3通知: 緊急連絡先
    pub fn send_tier3_emergency(&mut self, snapshot: &SensorSnapshot) {
        match self.send_safety_event(snapshot, "tier3_triggered") {
            Ok(()) => info!("Tier3緊急通知送信成功"),
            Err(e) => {
                error!("Tier3緊急通知送信失敗: {:?} → BLEフォールバック", e);
                self.ble_fallback_notify(snapshot, "tier3");
            }
        }
    }

    /// 監査ログを送信
    pub fn send_audit_log(&mut self, log_json: &str) -> Result<()> {
        if self.state != ConnectionState::Connected {
            return Err(anyhow!("MQTT not connected"));
        }

        let topic = format!("{}{}/_audit", TELEMETRY_TOPIC_PREFIX, self.device_id);
        self.mqtt_publish(&topic, log_json.as_bytes(), QoS::AtLeastOnce)?;

        Ok(())
    }

    /// BLEフォールバック通知
    /// WiFi/MQTT不可の場合、BLE Advertiseで近くのスマホに直接通知
    fn ble_fallback_notify(&self, snapshot: &SensorSnapshot, tier: &str) {
        warn!("BLEフォールバック通知: {}", tier);

        // BLE Advertise データ構造:
        // Service UUID: 0xFE95 (KAGI Safety)
        // Service Data:
        //   [0] = tier (1=tier1, 2=tier2, 3=tier3)
        //   [1-4] = ACS score (f32 LE)
        //   [5-8] = timestamp (u32 LE, epoch下位32bit)
        //   [9] = mmwave_last_breath_ago (分, u8: max 255分)
        //   [10] = door_last_open_ago (分, u8: max 255分)

        // ESP-IDF BLE APIを使ったAdvertiseは別途実装
        // esp_idf_svc::bt::ble::gap 経由

        // 実装ポイント:
        // - Advertise間隔: 100ms (低レイテンシ)
        // - TX Power: +9dBm (最大距離)
        // - Duration: 30秒間ブロードキャスト → スリープ
        info!("BLE Advertise開始: tier={}, acs={:.2}", tier, snapshot.acs_score);
    }

    /// 接続状態の確認と再接続
    pub fn ensure_connected(&mut self) -> Result<()> {
        if self.state == ConnectionState::Connected {
            return Ok(());
        }

        // Exponential backoff で再接続試行
        warn!(
            "MQTT再接続試行 (失敗回数: {}, 次回間隔: {}ms)",
            self.consecutive_failures, self.retry_interval_ms
        );

        match self.connect() {
            Ok(()) => {
                info!("MQTT再接続成功");
                Ok(())
            }
            Err(e) => {
                self.consecutive_failures += 1;
                self.retry_interval_ms = (self.retry_interval_ms * 2).min(MAX_RETRY_MS);
                Err(e)
            }
        }
    }

    /// 停電時のBLE onlyモードに移行
    pub fn enter_power_loss_mode(&mut self) {
        warn!("停電検知 → BLE onlyモードに移行");
        self.state = ConnectionState::BleOnly;

        // WiFi OFF (省電力)
        // esp_idf_svc::wifi 経由でstop

        // BLE Advertise開始
        // Service Data に「停電」フラグを含める
    }

    /// 現在の接続状態
    pub fn connection_state(&self) -> ConnectionState {
        self.state
    }

    /// MQTT publish (内部実装)
    /// 実際の実装では EspMqttClient::publish を呼び出す
    fn mqtt_publish(&mut self, topic: &str, payload: &[u8], qos: QoS) -> Result<()> {
        // ESP-IDF MQTT クライアントへの委譲
        // esp_mqtt_client_publish(topic, payload, qos)
        //
        // 実際のEspMqttClient統合時はここを置き換え:
        // self.mqtt_client.as_mut()
        //     .ok_or_else(|| anyhow!("MQTT client not initialized"))?
        //     .publish(topic, qos, false, payload)
        //     .map_err(|e| anyhow!("MQTT publish failed: {:?}", e))?;

        // プレースホルダー: 接続状態チェックのみ
        if self.state != ConnectionState::Connected {
            self.consecutive_failures += 1;
            return Err(anyhow!("MQTT not connected"));
        }

        log::debug!("MQTT publish: {} ({} bytes)", topic, payload.len());
        Ok(())
    }
}

// ──────────────────────────────────────
// MQTT QoS
// ──────────────────────────────────────

#[derive(Debug, Clone, Copy)]
enum QoS {
    AtMostOnce = 0,
    AtLeastOnce = 1,
}

// ──────────────────────────────────────
// 安全イベント構造体
// ──────────────────────────────────────

#[derive(Debug, Serialize)]
struct SafetyEvent {
    device_id: String,
    event_type: String,
    snapshot: SensorSnapshot,
    firmware_version: String,
}

// ──────────────────────────────────────
// ユーティリティ
// ──────────────────────────────────────

fn now_epoch() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}
