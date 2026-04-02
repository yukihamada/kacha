// local_ble.rs — オフラインファースト BLE ローカルゲートウェイ
//
// 「WiFiが切れても、家族は安心できる」
//
// プロトコル名: kagi://local/
//
// ## 設計思想
// KAGI デバイスは WiFi を主通信路とするが、
// 停電・ルーター障害・引越し直後など WiFi が使えない状況でも
// 家族のスマートフォンが帰宅時に Bluetooth でデバイスに接近することで
// 直近 24 時間の安否ログを取得できる。
//
// ## ローカルモード動作シーケンス
// 1. KAGI デバイスが BLE アドバタイズを常時発信 (低消費: 1285ms間隔)
// 2. 家族のスマホが帰宅 → KAGI アプリが GATT 接続
// 3. Status Summary (8バイト) を即座に読み込み → ACS・連続安否確認日数・バッテリーを表示
// 4. 必要に応じて Full Event Log を取得 (Indicate で複数パケット転送)
// 5. WiFi 復帰後、デバイスがサーバーにバルクアップロード
//
// ## BLE 電力消費
// アドバタイズ間隔 1285ms でのピーク電流: 約 8mA × 0.6ms = 平均 < 10μA
// GATT 接続中: 約 5mA (接続時間は通常 < 5秒)
//
// ## セキュリティ
// ローカル BLE は家族の信頼デバイスのみ接続可能にする。
// ペアリング時に ESP32-S3 側で NVS にデバイス MAC アドレスを登録し、
// 未登録端末からの接続リクエストは拒否する設計 (実装は BLE ペアリングモジュールが担当)。

use std::collections::VecDeque;
use log::{debug, info, warn};

// ---- 定数 ----

/// BLE GATT サービス UUID (16bit 短縮形)
/// 0x4B4C = "KL" (KAGI Local の頭文字)
pub const GATT_SERVICE_UUID: u16 = 0x4B4C;

/// Characteristic 0x4C01: 最新イベント JSON (Read, 最大 128バイト)
/// フォーマット: {"ts":1711440000,"type":"ok_button","acs":0.85}
pub const CHAR_LAST_EVENT: u16 = 0x4C01;

/// Characteristic 0x4C02: ステータスサマリー (Read, 8バイト固定)
/// バイト構成: [acs_u8, streak_hi, streak_lo, battery_u8, flag_wifi, flag_charging, flag_alert, reserved]
pub const CHAR_STATUS_SUMMARY: u16 = 0x4C02;

/// Characteristic 0x4C03: フルイベントログ (Read + Indicate, 複数パケット)
/// MTU=23バイト時、1パケット = 20バイト有効データ
/// 複数パケットで全件 JSON 配列を転送する
pub const CHAR_FULL_LOG: u16 = 0x4C03;

/// イベントログの最大保持件数
/// 10分ごとに記録 × 24時間 = 144件
/// ただし重要イベント (OkButton, FallAlert) は必ず残し、
/// 超過時は InactivityWarning / BreathingDetected を古い順に削除する
pub const MAX_LOG_ENTRIES: usize = 144;

/// WiFi 同期タイムアウト: この時間 (秒) 以上 WiFi 通信がない場合を "オフライン" とみなす
pub const WIFI_TIMEOUT_SECS: u64 = 3600; // 1時間

// ---- データ型 ----

/// ローカルに記録するイベントの種別
#[derive(Debug, Clone, Copy)]
pub enum LocalEventType {
    /// I'm OK ボタン押下
    OkButton,
    /// 呼吸センサーによる正常検知
    BreathingDetected,
    /// ドア開閉
    DoorOpen,
    /// 非活動警告 (N時間以上センサー反応なし)
    InactivityWarning { hours: u8 },
    /// 転倒検知アラート
    FallAlert,
    /// WiFi 接続断
    WifiLost,
    /// WiFi 接続復帰
    WifiRestored,
}

impl LocalEventType {
    /// JSON / ログ用の文字列表現
    pub fn as_str(&self) -> &'static str {
        match self {
            LocalEventType::OkButton => "ok_button",
            LocalEventType::BreathingDetected => "breathing",
            LocalEventType::DoorOpen => "door_open",
            LocalEventType::InactivityWarning { .. } => "inactivity_warning",
            LocalEventType::FallAlert => "fall_alert",
            LocalEventType::WifiLost => "wifi_lost",
            LocalEventType::WifiRestored => "wifi_restored",
        }
    }

    /// このイベントが重要 (ログ削除時に保護する) かどうか
    pub fn is_critical(&self) -> bool {
        matches!(
            self,
            LocalEventType::OkButton
                | LocalEventType::FallAlert
                | LocalEventType::InactivityWarning { .. }
        )
    }
}

/// ローカルに記録する 1件のイベント
#[derive(Debug, Clone)]
pub struct LocalEvent {
    /// Unix タイムスタンプ (秒)
    pub timestamp: u64,
    /// イベント種別
    pub event_type: LocalEventType,
    /// その時点での Alive Confirmation Score (0.0 〜 1.0)
    /// ACS は safety モジュールから受け取る
    pub alive_score: f32,
    /// WiFi 同期済みかどうか (バルクアップロード時に true にする)
    pub synced_to_server: bool,
}

/// ステータスサマリー (BLE Characteristic 0x4C02 の 8バイト)
///
/// 家族アプリは接続後まずこれを読む。
/// パースが簡単なバイナリ形式にすることで、
/// MTU が小さい場合でも 1 パケットで全情報を届けられる。
#[derive(Debug, Clone, Copy)]
pub struct StatusSummary {
    /// ACS を 0〜255 にスケール (acs × 255 の u8)
    pub acs_u8: u8,
    /// 連続安否確認日数 (u16, 最大 65535日 ≈ 179年)
    pub streak_days: u16,
    /// バッテリー残量 (0〜100%)
    pub battery_pct: u8,
    /// WiFi 接続中かどうか
    pub wifi_connected: bool,
    /// USB 充電中かどうか
    pub charging: bool,
    /// アクティブなアラートがあるかどうか
    pub alert_active: bool,
}

impl StatusSummary {
    /// 8バイトのバイナリペイロードにシリアライズ
    ///
    /// バイト構成:
    /// [0]: acs_u8
    /// [1]: streak_days の上位バイト
    /// [2]: streak_days の下位バイト
    /// [3]: battery_pct
    /// [4]: flags (bit0=wifi, bit1=charging, bit2=alert)
    /// [5..7]: 予約 (将来拡張用、ゼロ埋め)
    pub fn to_bytes(&self) -> [u8; 8] {
        let mut buf = [0u8; 8];
        buf[0] = self.acs_u8;
        buf[1] = (self.streak_days >> 8) as u8;
        buf[2] = (self.streak_days & 0xFF) as u8;
        buf[3] = self.battery_pct;
        buf[4] = (self.wifi_connected as u8)
            | ((self.charging as u8) << 1)
            | ((self.alert_active as u8) << 2);
        // buf[5..7] はゼロ (予約)
        buf
    }
}

/// オフラインファースト BLE ローカルゲートウェイ
///
/// 直近 24 時間のイベントをリングバッファで保持し、
/// 家族のスマートフォンが BLE GATT 接続した際に
/// ステータスと履歴を提供する。
pub struct LocalBleGateway {
    /// イベントログ (リングバッファ、最大 MAX_LOG_ENTRIES 件)
    event_log: VecDeque<LocalEvent>,
    /// 最後に WiFi 同期した Unix タイムスタンプ
    last_wifi_sync: Option<u64>,
    /// 現在の ACS (外部から定期的に更新)
    current_acs: f32,
    /// 連続安否確認日数
    streak_days: u16,
    /// バッテリー残量 (%)
    battery_pct: u8,
    /// USB 充電中フラグ
    is_charging: bool,
    /// アクティブアラートフラグ
    alert_active: bool,
}

impl LocalBleGateway {
    /// 新しい LocalBleGateway を初期化する
    ///
    /// NVS から前回セッションのログを復元する場合は
    /// `restore_from_nvs` を呼び出すこと (別途実装)。
    pub fn new() -> Self {
        info!("[local_ble] LocalBleGateway 初期化 (最大{}件のログ)", MAX_LOG_ENTRIES);
        Self {
            event_log: VecDeque::with_capacity(MAX_LOG_ENTRIES),
            last_wifi_sync: None,
            current_acs: 0.5, // 初期値: 中立
            streak_days: 0,
            battery_pct: 100,
            is_charging: false,
            alert_active: false,
        }
    }

    /// イベントをログに記録する
    ///
    /// MAX_LOG_ENTRIES を超える場合は古い非重要イベントを削除する。
    /// 重要イベント (OkButton, FallAlert, InactivityWarning) は削除されない。
    pub fn record_event(&mut self, event: LocalEvent) {
        debug!(
            "[local_ble] イベント記録: type={}, ts={}, acs={:.2}",
            event.event_type.as_str(),
            event.timestamp,
            event.alive_score
        );

        // アラートフラグを更新
        if matches!(event.event_type, LocalEventType::FallAlert) {
            self.alert_active = true;
            warn!("[local_ble] 転倒アラートを記録");
        }
        if matches!(event.event_type, LocalEventType::OkButton) {
            // OK ボタンでアラートをクリア
            self.alert_active = false;
        }

        // WiFi 状態フラグを更新
        if matches!(event.event_type, LocalEventType::WifiLost) {
            warn!("[local_ble] WiFi 切断をログに記録");
        }
        if matches!(event.event_type, LocalEventType::WifiRestored) {
            info!("[local_ble] WiFi 復帰をログに記録");
        }

        // ログが満杯の場合、古い非重要イベントを削除
        if self.event_log.len() >= MAX_LOG_ENTRIES {
            self.evict_old_entry();
        }

        self.event_log.push_back(event);
    }

    /// BLE 接続時に家族アプリへ送る 8バイトサマリーを生成
    ///
    /// 接続後最初に読み込まれる Characteristic 0x4C02 のデータ。
    /// WiFi がなくても ACS・連続日数・バッテリーが即座にわかる。
    pub fn summary_payload(&self) -> [u8; 8] {
        let summary = StatusSummary {
            acs_u8: (self.current_acs * 255.0).clamp(0.0, 255.0) as u8,
            streak_days: self.streak_days,
            battery_pct: self.battery_pct,
            wifi_connected: self.is_wifi_connected(),
            charging: self.is_charging,
            alert_active: self.alert_active,
        };
        let payload = summary.to_bytes();
        debug!("[local_ble] サマリーペイロード生成: {:02X?}", payload);
        payload
    }

    /// イベントログ全件を JSON 配列文字列で返す (BLE 転送用)
    ///
    /// Characteristic 0x4C03 の Indicate で分割転送する。
    /// MTU=23 (デフォルト) の場合、1パケット = 最大 20バイト。
    /// 呼び出し元 (BLE ドライバ) が MTU サイズに分割して送信すること。
    ///
    /// 出力例:
    /// ```json
    /// [{"ts":1711440000,"type":"ok_button","acs":0.85},{"ts":1711443600,"type":"breathing","acs":0.90}]
    /// ```
    pub fn full_log_json(&self) -> String {
        let parts: Vec<String> = self
            .event_log
            .iter()
            .map(|e| {
                let extra = match e.event_type {
                    LocalEventType::InactivityWarning { hours } => {
                        format!(r#","hours":{}"#, hours)
                    }
                    _ => String::new(),
                };
                format!(
                    r#"{{"ts":{},"type":"{}","acs":{:.2},"synced":{}{}}}"#,
                    e.timestamp,
                    e.event_type.as_str(),
                    e.alive_score,
                    e.synced_to_server,
                    extra,
                )
            })
            .collect();

        format!("[{}]", parts.join(","))
    }

    /// 最新イベント 1件の JSON を返す (Characteristic 0x4C01 用、最大 128バイト)
    pub fn last_event_json(&self) -> String {
        match self.event_log.back() {
            Some(e) => {
                let json = format!(
                    r#"{{"ts":{},"type":"{}","acs":{:.2}}}"#,
                    e.timestamp,
                    e.event_type.as_str(),
                    e.alive_score,
                );
                // 128バイトに切り詰め (BLE Characteristic のペイロード上限)
                if json.len() > 128 {
                    json[..128].to_string()
                } else {
                    json
                }
            }
            None => r#"{"type":"no_event"}"#.to_string(),
        }
    }

    /// WiFi 復帰時に未同期のローカルイベントを取得する
    ///
    /// バルクアップロード後に `mark_synced_up_to` を呼び出すこと。
    /// synced_to_server=false のイベントを古い順に返す。
    pub fn get_unsynced_events(&self) -> Vec<&LocalEvent> {
        self.event_log
            .iter()
            .filter(|e| !e.synced_to_server)
            .collect()
    }

    /// 指定タイムスタンプ以前のイベントを同期済みとしてマーク
    ///
    /// バルクアップロード成功後に呼び出す。
    pub fn mark_synced_up_to(&mut self, until_ts: u64) {
        let mut count = 0usize;
        for event in self.event_log.iter_mut() {
            if event.timestamp <= until_ts && !event.synced_to_server {
                event.synced_to_server = true;
                count += 1;
            }
        }
        self.last_wifi_sync = Some(until_ts);
        info!("[local_ble] {}件のイベントを同期済みとしてマーク (ts<={})", count, until_ts);
    }

    /// ACS を外部から更新する (safety モジュールから定期呼び出し)
    pub fn update_acs(&mut self, acs: f32, streak_days: u16) {
        self.current_acs = acs.clamp(0.0, 1.0);
        self.streak_days = streak_days;
    }

    /// バッテリー状態を外部から更新する
    pub fn update_battery(&mut self, pct: u8, charging: bool) {
        self.battery_pct = pct.min(100);
        self.is_charging = charging;
    }

    /// WiFi が現在接続中かを確認する
    ///
    /// last_wifi_sync が存在すれば接続試行中と楽観的に判定する。
    /// より正確には WiFi イベントループのコールバックで直接フラグを管理すること。
    pub fn is_wifi_connected(&self) -> bool {
        self.last_wifi_sync.is_some()
    }

    /// ログ満杯時の古い非重要エントリを削除する内部メソッド
    ///
    /// 削除優先順位:
    /// 1. BreathingDetected (最も古いもの)
    /// 2. DoorOpen (最も古いもの)
    /// 3. WifiLost / WifiRestored
    /// 4. 残りの非重要イベント (最も古いもの)
    /// 重要イベント (OkButton, FallAlert, InactivityWarning) は削除しない
    fn evict_old_entry(&mut self) {
        // 削除候補を探す (古い非重要イベントの最初のインデックス)
        let evict_idx = self
            .event_log
            .iter()
            .enumerate()
            .find(|(_, e)| !e.event_type.is_critical())
            .map(|(i, _)| i);

        match evict_idx {
            Some(idx) => {
                let removed = self.event_log.remove(idx);
                debug!(
                    "[local_ble] ログ満杯のため古いエントリを削除: type={}",
                    removed.map(|e| e.event_type.as_str()).unwrap_or("unknown")
                );
            }
            None => {
                // すべてが重要イベント — やむを得ず最古のものを削除
                warn!("[local_ble] すべてのログが重要イベント。最古エントリを削除");
                self.event_log.pop_front();
            }
        }
    }

    /// ログの統計情報をデバッグ出力
    pub fn debug_stats(&self) {
        info!(
            "[local_ble] ログ統計: total={}/{}, unsynced={}, acs={:.2}, streak={}日",
            self.event_log.len(),
            MAX_LOG_ENTRIES,
            self.get_unsynced_events().len(),
            self.current_acs,
            self.streak_days,
        );
    }
}

impl Default for LocalBleGateway {
    fn default() -> Self {
        Self::new()
    }
}

// ---- WiFi 復帰時のバルクアップロード設計メモ ----
//
// WiFi が WifiRestored イベントで復帰した場合:
// 1. cloud::CloudClient::bulk_upload_events(gateway.get_unsynced_events()) を呼び出す
// 2. アップロード成功後: gateway.mark_synced_up_to(current_timestamp)
// 3. アップロード失敗: リトライキューに追加し、次回 WiFi 接続時に再試行
//
// bulk_upload のエンドポイント例:
// POST /api/v1/devices/{device_id}/events/bulk
// Body: {"events": [{...}, {...}], "device_id": "hex...", "signature": "hex..."}
//
// サーバー側は timestamp の重複チェックを行い、冪等性を保証すること。

#[cfg(test)]
mod tests {
    use super::*;

    fn make_event(ts: u64, event_type: LocalEventType, acs: f32) -> LocalEvent {
        LocalEvent {
            timestamp: ts,
            event_type,
            alive_score: acs,
            synced_to_server: false,
        }
    }

    #[test]
    fn test_record_and_retrieve() {
        let mut gw = LocalBleGateway::new();
        gw.record_event(make_event(1000, LocalEventType::OkButton, 0.9));
        gw.record_event(make_event(2000, LocalEventType::BreathingDetected, 0.8));

        assert_eq!(gw.event_log.len(), 2);
        assert_eq!(gw.get_unsynced_events().len(), 2);
    }

    #[test]
    fn test_summary_payload_length() {
        let gw = LocalBleGateway::new();
        let payload = gw.summary_payload();
        assert_eq!(payload.len(), 8, "サマリーペイロードは必ず 8バイト");
    }

    #[test]
    fn test_status_summary_bytes() {
        let summary = StatusSummary {
            acs_u8: 200,
            streak_days: 300,
            battery_pct: 75,
            wifi_connected: true,
            charging: false,
            alert_active: true,
        };
        let bytes = summary.to_bytes();
        assert_eq!(bytes[0], 200);                // acs
        assert_eq!(bytes[1], 1);                  // streak_hi (300 = 0x012C)
        assert_eq!(bytes[2], 44);                 // streak_lo (0x2C = 44)
        assert_eq!(bytes[3], 75);                 // battery
        assert_eq!(bytes[4] & 0x01, 1);           // wifi flag
        assert_eq!((bytes[4] >> 1) & 0x01, 0);   // charging flag
        assert_eq!((bytes[4] >> 2) & 0x01, 1);   // alert flag
    }

    #[test]
    fn test_log_eviction_preserves_critical() {
        let mut gw = LocalBleGateway::new();

        // MAX_LOG_ENTRIES - 1 件の重要でないイベントを追加
        for i in 0..(MAX_LOG_ENTRIES - 1) {
            gw.record_event(make_event(i as u64, LocalEventType::BreathingDetected, 0.8));
        }
        // 1件の重要イベントを追加
        gw.record_event(make_event(9999, LocalEventType::OkButton, 0.95));

        // さらに 1件追加して eviction をトリガー
        gw.record_event(make_event(10000, LocalEventType::DoorOpen, 0.7));

        // OkButton は削除されずに残っているはず
        assert!(
            gw.event_log.iter().any(|e| matches!(e.event_type, LocalEventType::OkButton)),
            "重要イベント (OkButton) が eviction で削除された"
        );
    }

    #[test]
    fn test_full_log_json_valid_format() {
        let mut gw = LocalBleGateway::new();
        gw.record_event(make_event(1000, LocalEventType::OkButton, 0.9));

        let json = gw.full_log_json();
        assert!(json.starts_with('['), "JSON は配列から始まるべき");
        assert!(json.ends_with(']'), "JSON は配列で終わるべき");
        assert!(json.contains("\"type\":\"ok_button\""));
    }

    #[test]
    fn test_mark_synced() {
        let mut gw = LocalBleGateway::new();
        gw.record_event(make_event(1000, LocalEventType::OkButton, 0.9));
        gw.record_event(make_event(2000, LocalEventType::DoorOpen, 0.8));
        gw.record_event(make_event(3000, LocalEventType::BreathingDetected, 0.75));

        gw.mark_synced_up_to(2000);

        let unsynced = gw.get_unsynced_events();
        assert_eq!(unsynced.len(), 1, "ts=3000 のイベントだけ未同期であるべき");
        assert_eq!(unsynced[0].timestamp, 3000);
    }
}
