// KAGI Band ファームウェア v2.0
// 「人が一人で死んでいく世界を、テクノロジーで終わらせる」
// 手首で繋ぐ、命の綱。
//
// v2.0 追加機能:
//   - MAX30102 SpO2 + 心拍モニタリング
//   - NT3H1101 NFCタッチペアリング
//   - StreakTracker I'm OK連続記録

use anyhow::Result;
use esp_idf_hal::delay::FreeRtos;
use esp_idf_hal::gpio::{PinDriver, Pull};
use esp_idf_hal::i2c::{I2cConfig, I2cDriver};
use esp_idf_hal::peripherals::Peripherals;
use esp_idf_hal::prelude::*;
use esp_idf_svc::log::EspLogger;
use log::{info, warn};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

mod ble;
mod fall_detect;
mod nfc;
mod spo2;
mod streak;
mod vibrate;

use fall_detect::FallDetector;
use spo2::{HealthAlert, Spo2Monitor};
use streak::{StreakEvent, StreakTracker};
use vibrate::{VibPattern, Vibrator};

/// GPIO割り当て (BAND_SCHEMATIC_NOTES.md準拠)
mod pins {
    pub const I2C_SDA: i32 = 4;    // LIS2DH12 + MAX30102 + NT3H1101 共通SDA
    pub const I2C_SCL: i32 = 5;    // 同SCL
    pub const BUTTON_OK: i32 = 0;  // SW1 I'm OKボタン (RC遅延+プルアップ, LOW=押下)
    pub const MOTOR: i32 = 1;      // 振動モーター 2N7002 MOSFET gate (LEDC PWM)
    pub const LED_GREEN: i32 = 2;  // ステータスLED 緑
    pub const VBUS_DETECT: i32 = 3; // USB-C VBUS検出 (HIGH=充電中)
    pub const VBAT_ADC: i32 = 6;   // 電池電圧分圧 ADC (1MΩ/1MΩ → Vbat/2)
    pub const LIS_INT1: i32 = 7;   // LIS2DH12 INT1 転倒割り込み (R_INT 10KΩ プルアップ)
    pub const LED_RED: i32 = 8;    // 充電中LED 赤 (ETA4054 CHRG連動)
}

// SpO2モニタリング周期
const SPO2_POLL_MS: u64 = 5_000;   // 5秒ごとに測定
const SPO2_ALERT_COOLDOWN_S: u64 = 300; // アラートは5分に1回まで

fn main() -> Result<()> {
    esp_idf_svc::sys::link_patches();
    EspLogger::initialize_default();

    info!("=== KAGI Band v{} ===", env!("CARGO_PKG_VERSION"));
    info!("ミッション: 人が一人で死んでいく世界を、テクノロジーで終わらせる");

    let peripherals = Peripherals::take()?;

    // I2C バス (LIS2DH12 0x18 / MAX30102 0x57 / NT3H1101 0x55 共有)
    let i2c_config = I2cConfig::new().baudrate(400.kHz().into());
    let i2c = I2cDriver::new(
        peripherals.i2c0,
        peripherals.pins.gpio4,
        peripherals.pins.gpio5,
        &i2c_config,
    )?;
    let i2c = Arc::new(Mutex::new(i2c));

    // I'm OKボタン (GPIO0, RC遅延でBootモード誤進入防止)
    let mut button = PinDriver::input(peripherals.pins.gpio0)?;
    button.set_pull(Pull::Up)?;

    // LIS2DH12 INT1 転倒割り込み (GPIO7, R_INT 10KΩ外部プルアップ)
    let lis_int1 = PinDriver::input(peripherals.pins.gpio7)?;

    // 振動モーター (GPIO1, LEDC PWM, 2N7002 Nch MOSFET経由)
    let vibrator = Vibrator::new(
        peripherals.ledc.timer0,
        peripherals.ledc.channel0,
        peripherals.pins.gpio1,
    )?;
    let vibrator = Arc::new(Mutex::new(vibrator));

    // LED
    let mut led_green = PinDriver::output(peripherals.pins.gpio2)?;
    led_green.set_low()?;

    // ──────────────────────────────
    // センサー初期化
    // ──────────────────────────────

    // 転倒検知 (LIS2DH12)
    let fall_detector = Arc::new(Mutex::new(FallDetector::new(i2c.clone())?));

    // SpO2 + 心拍 (MAX30102)
    let spo2_monitor = Arc::new(Mutex::new(Spo2Monitor::new(i2c.clone())?));
    info!("MAX30102 SpO2センサー初期化完了");

    // NFC (NT3H1101) — デバイスIDをURIとして書き込む
    let device_id = get_device_id(); // NVS or ATECC608A シリアルから取得
    if let Ok(mut nfc) = nfc::NfcTag::new(i2c.clone()) {
        let pair_url = format!("https://kagi.home/pair/{}", device_id);
        nfc.write_ndef_url(&pair_url).ok();
        info!("NFCタグ設定完了: {}", pair_url);
    } else {
        warn!("NFCタグ初期化失敗 (オプション部品のためスキップ)");
    }

    // I'm OK連続記録
    let streak = Arc::new(Mutex::new(StreakTracker::load_from_nvs()));
    info!(
        "Streak読み込み: {}日連続 (最長{}日)",
        streak.lock().unwrap().current_streak,
        streak.lock().unwrap().longest_streak
    );

    // BLE初期化
    let ble = Arc::new(Mutex::new(ble::BandBle::new()?));
    info!("BLE初期化完了。KAGI-BANDを広告中...");

    // 起動完了フラッシュ
    for _ in 0..2 {
        led_green.set_high()?;
        FreeRtos::delay_ms(100);
        led_green.set_low()?;
        FreeRtos::delay_ms(100);
    }

    // ──────────────────────────────
    // バックグラウンドスレッド
    // ──────────────────────────────

    // 振動コマンド処理スレッド (BLEからの振動指示を受け付ける)
    {
        let vib_clone = vibrator.clone();
        let ble_clone = ble.clone();
        thread::Builder::new()
            .name("vib_handler".into())
            .stack_size(4096)
            .spawn(move || loop {
                if let Ok(ble) = ble_clone.lock() {
                    if let Some(cmd) = ble.pending_vibration_command() {
                        if let Ok(mut vib) = vib_clone.lock() {
                            vib.execute(cmd).ok();
                        }
                    }
                }
                FreeRtos::delay_ms(100);
            })?;
    }

    // SpO2 / 心拍モニタリングスレッド (5秒ごと)
    {
        let spo2_clone = spo2_monitor.clone();
        let ble_clone = ble.clone();
        let vib_clone = vibrator.clone();
        thread::Builder::new()
            .name("spo2_monitor".into())
            .stack_size(8192)
            .spawn(move || {
                let mut last_alert_ts = Instant::now() - Duration::from_secs(SPO2_ALERT_COOLDOWN_S);
                loop {
                    FreeRtos::delay_ms(SPO2_POLL_MS as u32);

                    let alert = if let Ok(mut mon) = spo2_clone.lock() {
                        mon.measure()
                    } else {
                        continue;
                    };

                    match alert {
                        HealthAlert::Normal { spo2, hr } => {
                            // 10回に1回 BLE Notify (バッテリー節約)
                            static mut COUNTER: u8 = 0;
                            unsafe {
                                COUNTER = COUNTER.wrapping_add(1);
                                if COUNTER % 10 == 0 {
                                    if let Ok(ble) = ble_clone.lock() {
                                        ble.notify_health(spo2, hr);
                                    }
                                }
                            }
                        }
                        HealthAlert::LowSpO2(spo2) => {
                            if last_alert_ts.elapsed().as_secs() >= SPO2_ALERT_COOLDOWN_S {
                                warn!("SpO2低下警告: {}%", spo2);
                                if let Ok(ble) = ble_clone.lock() {
                                    ble.notify_spo2_alert(spo2);
                                }
                                if let Ok(mut vib) = vib_clone.lock() {
                                    vib.execute(VibPattern::Tier1Alert).ok();
                                }
                                last_alert_ts = Instant::now();
                            }
                        }
                        HealthAlert::AbnormalHR(hr) => {
                            if last_alert_ts.elapsed().as_secs() >= SPO2_ALERT_COOLDOWN_S {
                                warn!("心拍異常: {} bpm", hr);
                                if let Ok(ble) = ble_clone.lock() {
                                    ble.notify_hr_alert(hr);
                                }
                                if let Ok(mut vib) = vib_clone.lock() {
                                    vib.execute(VibPattern::Tier1Alert).ok();
                                }
                                last_alert_ts = Instant::now();
                            }
                        }
                        HealthAlert::PossibleCardiacEvent => {
                            warn!("心臓イベント疑い → 緊急BLE通知");
                            if let Ok(ble) = ble_clone.lock() {
                                ble.notify_cardiac_alert();
                            }
                            if let Ok(mut vib) = vib_clone.lock() {
                                vib.execute(VibPattern::FallDetected).ok();
                            }
                            last_alert_ts = Instant::now();
                        }
                        HealthAlert::SensorError => {
                            // センサーが手首に密着していない → 無視
                        }
                    }
                }
            })?;
    }

    info!("全スレッド起動完了。安否確認を開始します。");

    // ──────────────────────────────
    // メインループ (10ms ポーリング)
    // ──────────────────────────────
    let mut last_button = button.is_high();
    let mut button_pressed_at: Option<Instant> = None;

    loop {
        // ── I'm OK ボタン検知 ──
        let btn = button.is_high();
        if !btn && last_button {
            button_pressed_at = Some(Instant::now());
        }
        if btn && !last_button {
            if let Some(pressed) = button_pressed_at.take() {
                let held_ms = pressed.elapsed().as_millis();

                if held_ms >= 3000 {
                    // 3秒長押し → ペアリングモード
                    info!("ペアリングモード開始 (3秒長押し)");
                    if let Ok(mut ble_guard) = ble.lock() {
                        ble_guard.enter_pairing_mode();
                    }
                    for _ in 0..5 {
                        led_green.set_high()?;
                        FreeRtos::delay_ms(100);
                        led_green.set_low()?;
                        FreeRtos::delay_ms(100);
                    }
                } else {
                    // 通常押下 → I'm OK通知 + Streak更新
                    info!("I'm OKボタン押下 → BLE通知");

                    let streak_event = if let Ok(mut s) = streak.lock() {
                        let ts = now_unix();
                        let event = s.record_press(ts);
                        s.save_to_nvs();
                        event
                    } else {
                        StreakEvent::Normal
                    };

                    if let Ok(ble_guard) = ble.lock() {
                        ble_guard.notify_ok_button();
                        // Streak情報もBLEで送る (家族アプリで表示)
                        if let Some(days) = streak_milestone_days(&streak_event) {
                            ble_guard.notify_streak_milestone(days);
                        }
                    }

                    // Streakに応じた振動フィードバック
                    if let Ok(mut vib) = vibrator.lock() {
                        match streak_event {
                            StreakEvent::MilestoneReached(days) => {
                                info!("Streakマイルストーン達成: {}日！", days);
                                vib.execute(VibPattern::PairingComplete).ok(); // 特別パターン
                            }
                            _ => {
                                vib.execute(VibPattern::OkConfirm).ok();
                            }
                        }
                    }

                    led_green.set_high()?;
                    FreeRtos::delay_ms(500);
                    led_green.set_low()?;
                }
            }
        }
        last_button = btn;

        // ── 転倒検知 (LIS2DH12 INT1) ──
        if lis_int1.is_high() {
            if let Ok(mut fd) = fall_detector.lock() {
                if let Some(event) = fd.poll() {
                    info!("転倒イベント検知: {:?}", event);
                    if let Ok(ble_guard) = ble.lock() {
                        ble_guard.notify_fall_event(&event);
                    }
                    if let Ok(mut vib) = vibrator.lock() {
                        vib.execute(VibPattern::FallDetected).ok();
                    }
                }
            }
        }

        FreeRtos::delay_ms(10);
    }
}

/// Streakイベントからマイルストーン日数を取得
fn streak_milestone_days(event: &StreakEvent) -> Option<u32> {
    match event {
        StreakEvent::MilestoneReached(days) => Some(*days),
        _ => None,
    }
}

/// Unix timestamp を返す (ESP-IDF SNTP同期後)
fn now_unix() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// デバイスIDを取得 (NVS "device_id" キーから、なければランダム生成)
fn get_device_id() -> String {
    // TODO: NVS esp_idf_svc::nvs から "kagi" namespace の "device_id" を読む
    // 初回はランダムID生成して保存
    "kagi-band-001".to_string() // プレースホルダー
}
