// KAGI Band BLE GATT サーバー
// Service UUID: 0x4B47 (KG)
// Characteristic 0x4B01: OK Button Notify
// Characteristic 0x4B02: Fall Event Notify
// Characteristic 0x4B03: Battery Level Notify
// Characteristic 0x4B04: Vibration Command (Write)
// Characteristic 0x4B05: Pairing Token (Write)
// Characteristic 0x4B06: SpO2/Heart Rate Notify
// Characteristic 0x4B07: Streak Milestone Notify

use anyhow::Result;
use log::{info, warn};

use crate::fall_detect::FallEvent;
use crate::vibrate::VibPattern;

/// BLEペアリング状態
#[derive(Debug, Clone, PartialEq)]
pub enum PairingState {
    Unpaired,
    Advertising,
    Paired { peer_addr: [u8; 6] },
}

/// BLEコマンド (0x4B04 Vibration Command)
#[derive(Debug, Clone)]
pub enum VibCommand {
    Alert(VibPattern),
    Stop,
}

pub struct BandBle {
    pairing_state: PairingState,
    pending_vib: Option<VibCommand>,
    ok_button_count: u32,
}

impl BandBle {
    pub fn new() -> Result<Self> {
        // ESP-IDF NimBLE初期化
        // NOTE: esp_idf_svc::bt::BtDriver + NimBLE でGATTサーバーを構築
        // 実際の初期化はesp_idf_svc 0.50以降のBLE APIを使用
        info!("BLE GATT初期化: KAGI-BAND Service UUID=0x4B47");
        Ok(Self {
            pairing_state: PairingState::Advertising,
            pending_vib: None,
            ok_button_count: 0,
        })
    }

    /// I'm OKボタン押下をBLE Notify
    pub fn notify_ok_button(&self) {
        // 0x4B01 Characteristic に Notify
        // payload: [0x01, timestamp_low, timestamp_high]
        info!("BLE Notify: I'm OK (count={})", self.ok_button_count);
        // TODO: esp_nimble_host_init → gattc_notify
    }

    /// 転倒イベントをBLE Notify
    pub fn notify_fall_event(&self, event: &FallEvent) {
        // 0x4B02 Characteristic に Notify
        // payload: [severity, accel_x, accel_y, accel_z, timestamp...]
        info!("BLE Notify: 転倒イベント severity={}", event.severity as u8);
        // TODO: NimBLE notify
    }

    /// BLEから受信した振動コマンドを取得 (メインループでポーリング)
    pub fn pending_vibration_command(&self) -> Option<VibPattern> {
        // 0x4B04 Characteristic のWrite値を取得
        // TODO: NimBLE Write callback → Mutex経由で受け渡し
        None
    }

    /// ペアリングモード開始 (SW1 3秒長押し)
    pub fn enter_pairing_mode(&mut self) {
        info!("ペアリングモード: 新規接続を受け入れます (60秒)");
        self.pairing_state = PairingState::Advertising;
        // TODO: NimBLE広告パラメータをペアリング用に変更
        // gap_connectable = true, adv_duration = 60s
    }

    /// ペアリング済みか確認
    pub fn is_paired(&self) -> bool {
        matches!(self.pairing_state, PairingState::Paired { .. })
    }

    /// バッテリー残量をBLE Notify (定期的に呼ぶ)
    pub fn notify_battery_level(&self, percent: u8) {
        // 0x4B03 Characteristic
        info!("BLE Notify: バッテリー {}%", percent);
        // TODO: NimBLE notify
    }

    // ---------------------------------------------------------------
    // SpO2 / 心拍 通知 (0x4B06 Characteristic)
    // payload: [spo2: u8, hr: u8]
    // ---------------------------------------------------------------

    /// SpO2と心拍数を BLE Notify
    pub fn notify_health(&self, spo2: u8, hr: u8) {
        // 0x4B06 Characteristic に Notify
        // payload: [spo2, hr]
        info!("BLE Notify: SpO2={}% HR={}bpm", spo2, hr);
        // TODO: NimBLE notify実装
    }

    /// SpO2 低下アラートを BLE Notify
    pub fn notify_spo2_alert(&self, spo2: u8) {
        // 0x4B06 Characteristic に Notify (アラートフラグ付き)
        // payload: [0xFF, spo2] — 0xFF はアラートマーカー
        warn!("BLE Notify: SpO2低下アラート SpO2={}%", spo2);
        // TODO: NimBLE notify実装
    }

    /// 心拍数異常アラートを BLE Notify
    pub fn notify_hr_alert(&self, hr: u8) {
        // 0x4B06 Characteristic に Notify (アラートフラグ付き)
        // payload: [spo2=0x00, hr] + alert_flag byte
        warn!("BLE Notify: 心拍異常アラート HR={}bpm", hr);
        // TODO: NimBLE notify実装
    }

    /// 心臓系緊急アラートを BLE Notify
    pub fn notify_cardiac_alert(&self) {
        // 0x4B06 Characteristic に Notify (最優先アラート)
        // payload: [0xFF, 0xFF] — 両フィールドがアラートマーカー
        warn!("BLE Notify: 心臓系緊急アラート");
        // TODO: NimBLE notify実装
    }

    // ---------------------------------------------------------------
    // Streak マイルストーン通知 (0x4B07 Characteristic)
    // payload: [days: u32 little-endian (4 bytes)]
    // ---------------------------------------------------------------

    /// Streak マイルストーン達成を BLE Notify
    pub fn notify_streak_milestone(&self, days: u32) {
        // 0x4B07 Characteristic に Notify
        // payload: days を little-endian 4 バイトで送信
        info!("BLE Notify: Streak マイルストーン達成! {} 日", days);
        // TODO: NimBLE notify実装
    }
}
