// KAGI Home ファームウェア
// 「人が一人で死んでいく世界を、テクノロジーで終わらせる」

mod cloud;
mod safety;
mod sensors;
mod storage;

use anyhow::Result;
use esp_idf_hal::delay::FreeRtos;
use esp_idf_hal::gpio::{AnyInputPin, AnyOutputPin, PinDriver, Pull};
use esp_idf_hal::i2c::{I2cConfig, I2cDriver};
use esp_idf_hal::peripherals::Peripherals;
use esp_idf_hal::prelude::*;
use esp_idf_hal::uart::{UartConfig, UartDriver};
use esp_idf_svc::eventloop::EspSystemEventLoop;
use esp_idf_svc::log::EspLogger;
use esp_idf_svc::nvs::EspDefaultNvsPartition;
use esp_idf_svc::wifi::{AuthMethod, ClientConfiguration, Configuration, EspWifi};
use log::{info, warn, error};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use safety::{SafetyMonitor, SafetyState, SafetyConfig};
use sensors::{SensorManager, SensorSnapshot};
use cloud::CloudClient;
use storage::StorageManager;

/// デバイスモデル (コンパイル時feature flagで決定)
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DeviceModel {
    Lite,
    Hub,
    Pro,
}

impl DeviceModel {
    pub fn current() -> Self {
        #[cfg(feature = "pro")]
        return DeviceModel::Pro;
        #[cfg(all(feature = "hub", not(feature = "pro")))]
        return DeviceModel::Hub;
        #[cfg(not(feature = "hub"))]
        return DeviceModel::Lite;
    }
}

/// GPIO割り当て (schematic_notes.md準拠)
mod pins {
    pub const I2C_SDA: i32 = 8;
    pub const I2C_SCL: i32 = 9;
    pub const RADAR_TX: i32 = 14;   // UART1 TX → LD2410B RX
    pub const RADAR_RX: i32 = 15;   // UART1 RX ← LD2410B TX
    pub const RADAR_OUT: i32 = 4;   // LD2410B OUT (HIGH=在室)
    pub const DOOR_SW: i32 = 3;     // MC-38 ドアセンサー (プルアップ, HIGH=開)
    pub const BUTTON_OK: i32 = 2;   // SW2: I'm OKボタン 12mm大型 (プルアップ, LOW=押下)
                                    // ※ペアリング時も兼用 (3秒長押しでペアリングモード)
    pub const BUZZER: i32 = 17;     // BZ1 アクティブ圧電ブザー (HIGH=鳴動)
    pub const WS2812_DATA: i32 = 38; // WS2812B-2020 ×2 (ステータスLED)
    pub const VBUS_ADC: i32 = 1;    // USB VBUS分圧 (停電検知)
}

fn main() -> Result<()> {
    // ESP-IDF初期化
    esp_idf_svc::sys::link_patches();
    EspLogger::initialize_default();

    info!("=== KAGI Home v{} ({:?}) ===", env!("CARGO_PKG_VERSION"), DeviceModel::current());
    info!("ミッション: 人が一人で死んでいく世界を、テクノロジーで終わらせる");

    let peripherals = Peripherals::take()?;
    let sys_loop = EspSystemEventLoop::take()?;
    let nvs_partition = EspDefaultNvsPartition::take()?;

    // ストレージ初期化
    let mut storage = StorageManager::new(nvs_partition.clone())?;
    let config = storage.load_safety_config()?;
    info!("設定読み込み完了: learning_days={}", config.learning_days);

    // I2Cバス初期化 (400kHz, 4.7Kプルアップ対応)
    let i2c_config = I2cConfig::new().baudrate(400.kHz().into());
    let i2c = I2cDriver::new(
        peripherals.i2c0,
        peripherals.pins.gpio8,  // SDA
        peripherals.pins.gpio9,  // SCL
        &i2c_config,
    )?;
    let i2c = Arc::new(Mutex::new(i2c));
    info!("I2Cバス初期化完了 (400kHz)");

    // UART初期化 (LD2410B: 256000bps)
    let uart_config = UartConfig::new().baudrate(Hertz(256_000));
    let uart = UartDriver::new(
        peripherals.uart1,
        peripherals.pins.gpio14,  // TX → LD2410B RX
        peripherals.pins.gpio15,  // RX ← LD2410B TX
        Option::<AnyInputPin>::None,
        Option::<AnyOutputPin>::None,
        &uart_config,
    )?;
    let uart = Arc::new(Mutex::new(uart));
    info!("UART1初期化完了 (LD2410B 256000bps)");

    // GPIO初期化
    let mut door_pin = PinDriver::input(peripherals.pins.gpio3)?;
    door_pin.set_pull(Pull::Up)?;

    let mut button_pin = PinDriver::input(peripherals.pins.gpio2)?;
    button_pin.set_pull(Pull::Up)?;

    let mut buzzer_pin = PinDriver::output(peripherals.pins.gpio17)?;
    buzzer_pin.set_low()?;

    let mut radar_out_pin = PinDriver::input(peripherals.pins.gpio4)?;

    info!("GPIO初期化完了");

    // センサーマネージャ初期化
    let sensor_mgr = Arc::new(Mutex::new(SensorManager::new(
        i2c.clone(),
        uart.clone(),
        DeviceModel::current(),
    )?));
    info!("センサーマネージャ初期化完了");

    // Safety Monitor初期化
    let safety_monitor = Arc::new(Mutex::new(SafetyMonitor::new(config.clone())?));
    info!("Safety Monitor初期化完了");

    // ストレージを共有
    let storage = Arc::new(Mutex::new(storage));

    // WiFi接続
    let wifi = setup_wifi(peripherals.modem, sys_loop.clone(), nvs_partition.clone())?;
    let wifi = Arc::new(Mutex::new(wifi));
    info!("WiFi初期化完了");

    // クラウドクライアント初期化
    let cloud = Arc::new(Mutex::new(CloudClient::new()?));

    // 起動確認音
    buzzer_beep(&mut buzzer_pin, 1)?;
    info!("起動シーケンス完了。安否確認を開始します。");

    // ==== タスク生成 ====

    // タスク1: センサー読み取り (優先度3, 60秒間隔)
    let sensor_mgr_clone = sensor_mgr.clone();
    let safety_clone = safety_monitor.clone();
    let storage_clone = storage.clone();
    thread::Builder::new()
        .name("sensor_poll".into())
        .stack_size(4096)
        .spawn(move || {
            sensor_poll_task(sensor_mgr_clone, safety_clone, storage_clone);
        })?;

    // タスク2: mmWaveレーダー読み取り (優先度4, 10秒間隔)
    let sensor_mgr_clone2 = sensor_mgr.clone();
    let safety_clone2 = safety_monitor.clone();
    thread::Builder::new()
        .name("mmwave_reader".into())
        .stack_size(4096)
        .spawn(move || {
            mmwave_reader_task(sensor_mgr_clone2, safety_clone2);
        })?;

    // タスク3: クラウド同期 (優先度2, 60秒間隔)
    let cloud_clone = cloud.clone();
    let safety_clone3 = safety_monitor.clone();
    let storage_clone2 = storage.clone();
    thread::Builder::new()
        .name("cloud_sync".into())
        .stack_size(8192)
        .spawn(move || {
            cloud_sync_task(cloud_clone, safety_clone3, storage_clone2);
        })?;

    // メインループ: Safety Monitor + GPIO割り込み処理 (優先度5, 最高)
    info!("メインループ開始 (Safety Monitor)");
    let mut last_door_state = door_pin.is_high();
    let mut last_button_state = button_pin.is_high();

    loop {
        // ドアセンサー変化検知
        let door_state = door_pin.is_high();
        if door_state != last_door_state {
            last_door_state = door_state;
            let is_open = door_state; // プルアップ: HIGH=開, LOW=閉(磁石近接)
            info!("ドアセンサー変化: {}", if is_open { "開" } else { "閉" });

            if let Ok(mut monitor) = safety_monitor.lock() {
                monitor.on_door_event(is_open);
            }
        }

        // I'm OKボタン検知 (ネガティブエッジ: プルアップ → LOW=押下)
        let button_state = button_pin.is_high();
        if !button_state && last_button_state {
            info!("I'm OKボタン押下");

            if let Ok(mut monitor) = safety_monitor.lock() {
                monitor.on_ok_button_pressed();
            }

            // 確認音: ピッ
            buzzer_beep(&mut buzzer_pin, 1).ok();
        }
        last_button_state = button_state;

        // mmWave OUTピン即時チェック
        let radar_presence = radar_out_pin.is_high();
        if let Ok(mut monitor) = safety_monitor.lock() {
            monitor.on_radar_presence(radar_presence);
        }

        // Safety Ladder状態評価 (10秒ごとの主要処理)
        if let Ok(mut monitor) = safety_monitor.lock() {
            let action = monitor.evaluate();
            match action {
                safety::SafetyAction::None => {},
                safety::SafetyAction::Tier1Alert => {
                    warn!("Tier1: 本人に確認 (LED黄+ブザー)");
                    buzzer_beep(&mut buzzer_pin, 3).ok();
                },
                safety::SafetyAction::Tier2Notify => {
                    warn!("Tier2: 家族に通知");
                    if let Ok(mut cl) = cloud.lock() {
                        cl.send_tier2_notification(&monitor.last_snapshot());
                    }
                },
                safety::SafetyAction::Tier3Emergency => {
                    error!("Tier3: 緊急連絡先に通知");
                    if let Ok(mut cl) = cloud.lock() {
                        cl.send_tier3_emergency(&monitor.last_snapshot());
                    }
                },
                safety::SafetyAction::ResetToNormal => {
                    info!("正常状態に復帰");
                },
            }
        }

        // 10秒間隔 (Safety Monitor評価周期)
        FreeRtos::delay_ms(10_000);
    }
}

/// センサーポーリングタスク (60秒間隔)
fn sensor_poll_task(
    sensor_mgr: Arc<Mutex<SensorManager>>,
    safety: Arc<Mutex<SafetyMonitor>>,
    storage: Arc<Mutex<StorageManager>>,
) {
    loop {
        if let Ok(mut mgr) = sensor_mgr.lock() {
            match mgr.read_environmental() {
                Ok(snapshot) => {
                    if let Ok(mut monitor) = safety.lock() {
                        monitor.update_environmental(&snapshot);
                    }
                    // 生活リズム学習データを定期保存
                    if let Ok(mut store) = storage.lock() {
                        if let Ok(monitor) = safety.lock() {
                            store.save_rhythm_data(&monitor.rhythm_data()).ok();
                        }
                    }
                }
                Err(e) => {
                    warn!("センサー読み取りエラー: {:?}", e);
                }
            }
        }
        FreeRtos::delay_ms(60_000);
    }
}

/// mmWaveレーダー読み取りタスク (10秒間隔)
fn mmwave_reader_task(
    sensor_mgr: Arc<Mutex<SensorManager>>,
    safety: Arc<Mutex<SafetyMonitor>>,
) {
    loop {
        if let Ok(mut mgr) = sensor_mgr.lock() {
            match mgr.read_mmwave_uart() {
                Ok(data) => {
                    if let Ok(mut monitor) = safety.lock() {
                        monitor.update_mmwave(&data);
                    }
                }
                Err(e) => {
                    warn!("mmWave UART読み取りエラー: {:?}", e);
                }
            }
        }
        FreeRtos::delay_ms(10_000);
    }
}

/// クラウド同期タスク (60秒間隔)
fn cloud_sync_task(
    cloud: Arc<Mutex<CloudClient>>,
    safety: Arc<Mutex<SafetyMonitor>>,
    storage: Arc<Mutex<StorageManager>>,
) {
    let mut retry_interval_ms: u32 = 5_000;
    let max_retry_ms: u32 = 300_000; // 5分

    loop {
        let send_result = (|| -> Result<()> {
            let snapshot = {
                let monitor = safety.lock().map_err(|_| anyhow::anyhow!("lock error"))?;
                monitor.last_snapshot()
            };

            let mut cl = cloud.lock().map_err(|_| anyhow::anyhow!("lock error"))?;
            cl.send_telemetry(&snapshot)?;

            // ローカルバッファの未送信ログを送信
            let mut store = storage.lock().map_err(|_| anyhow::anyhow!("lock error"))?;
            let pending = store.drain_pending_logs(10);
            for log_entry in pending {
                cl.send_audit_log(&log_entry)?;
            }

            Ok(())
        })();

        match send_result {
            Ok(()) => {
                retry_interval_ms = 5_000; // リセット
            }
            Err(e) => {
                warn!("クラウド同期失敗: {:?} (次回リトライ: {}ms)", e, retry_interval_ms);
                // Exponential backoff
                retry_interval_ms = (retry_interval_ms * 2).min(max_retry_ms);

                // オフラインバッファにログ追記
                if let Ok(monitor) = safety.lock() {
                    if let Ok(mut store) = storage.lock() {
                        store.buffer_log_entry(&monitor.last_snapshot()).ok();
                    }
                }
            }
        }

        FreeRtos::delay_ms(60_000);
    }
}

/// ブザー制御 (count回短いビープ)
fn buzzer_beep(pin: &mut PinDriver<'_, esp_idf_hal::gpio::Gpio17, esp_idf_hal::gpio::Output>, count: u8) -> Result<()> {
    for i in 0..count {
        pin.set_high()?;
        FreeRtos::delay_ms(200);
        pin.set_low()?;
        if i < count - 1 {
            FreeRtos::delay_ms(200);
        }
    }
    Ok(())
}

/// WiFiセットアップ (STA mode)
fn setup_wifi(
    modem: esp_idf_hal::modem::Modem,
    sys_loop: EspSystemEventLoop,
    nvs: EspDefaultNvsPartition,
) -> Result<EspWifi<'static>> {
    let mut wifi = EspWifi::new(modem, sys_loop.clone(), Some(nvs))?;

    // 開発時: コンパイル時に埋め込み (本番はNVSプロビジョニングで上書き)
    let ssid = option_env!("KAGI_WIFI_SSID").unwrap_or("KAGI-SETUP");
    let password = option_env!("KAGI_WIFI_PASS").unwrap_or("");

    let client_config = ClientConfiguration {
        ssid: heapless::String::try_from(ssid).unwrap_or_default(),
        password: heapless::String::try_from(password).unwrap_or_default(),
        auth_method: if password.is_empty() { AuthMethod::None } else { AuthMethod::WPA2Personal },
        ..Default::default()
    };

    wifi.set_configuration(&Configuration::Client(client_config))?;
    wifi.start()?;

    info!("WiFi接続試行中...");
    match wifi.connect() {
        Ok(()) => info!("WiFi接続成功"),
        Err(e) => warn!("WiFi接続失敗: {:?} (オフラインモードで動作)", e),
    }

    Ok(wifi)
}
