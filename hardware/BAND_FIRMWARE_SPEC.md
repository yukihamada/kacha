# KAGI Band ファームウェア仕様

## アーキテクチャ

ESP32-C3 上で `esp-idf` (Rust + esp-hal) を使用。

```
⚠️ KAGI Lite/Hub (ESP32-S3) との違い:
  Lite/Hub ターゲット: xtensa-esp32s3-espidf   (Tensilica Xtensa LX7)
  Band    ターゲット: riscv32imc-esp-espidf     (RISC-V 32bit)

ツールチェーンは別インストールが必要:
  $ espup install  (Xtensa + RISC-V の両方をセットアップ)

Cargo workspace 構成:
  kacha/firmware/       ← Lite/Hub/Pro (ESP32-S3)
  kacha/firmware-band/  ← Band         (ESP32-C3) ← 必ず別ディレクトリ
```

### Cargo.toml (Band専用)
```toml
[package]
name = "kagi-band"
version = "1.0.0"
edition = "2021"

[dependencies]
esp-idf-hal = { version = "0.45", features = ["std"] }
esp-idf-svc = { version = "0.50", features = ["std", "ble"] }
esp-idf-sys = { version = "0.36", features = ["binstart"] }
esp-idf-ble = { version = "0.1" }   # BLE GATT実装
anyhow = "1"
log = "0.4"
heapless = "0.8"

[build-dependencies]
embuild = { version = "0.33", features = ["espidf"] }
```

### .cargo/config.toml (Band専用)
```toml
[build]
target = "riscv32imc-esp-espidf"  # ← C3はRISC-V

[target.riscv32imc-esp-espidf]
linker = "ldproxy"
runner = "espflash flash --monitor"
rustflags = ["--cfg", "espidf_time64"]

[unstable]
build-std = ["std", "panic_abort"]

[env]
ESP_IDF_VERSION = "v5.2.5"
```

---

## タスク構成

```
メインループ (優先度5):
  - GPIOポーリング (SW1ボタン)
  - BLE接続状態管理
  - バッテリー残量チェック (1分ごと)
  - 転倒確認状態機械

BLE GAP/GATT タスク (優先度4):
  - Advertisingパラメータ管理
  - Connection interval更新
  - GATT Notifyキュー処理

LIS2DH12 割り込みハンドラ:
  - INT1: Free-fall検知 → 状態機械へイベント
  - INT7: クリック/衝撃検知 → 状態機械へイベント

タイマータスク (FreeRTOS Timer):
  - 日次チェックリマインダー (設定時刻)
  - Tier1エスカレーションタイムアウト
  - 電池残量Notify (60秒ごと)
```

---

## 状態機械

### BLE接続状態
```rust
pub enum BleState {
    Advertising,        // 未接続、広告中
    Connecting,         // 接続ネゴシエーション中
    Connected(ConnHandle),  // Hub/Liteと接続済み
    Bonded,             // ペアリング済み (アドレス記憶)
}
```

### 転倒検知状態
```rust
pub enum FallState {
    Normal,
    FreeFall {
        started_at: Instant,
    },
    PostFall {
        impact_detected: bool,
        started_at: Instant,
    },
    Confirmed {
        confidence: u8,  // 0-100
    },
    Cancelled,  // ユーザーがボタン押下でキャンセル
}
```

### I'm OKボタン処理
```rust
// GPIO0割り込み (ネガティブエッジ)
fn on_ok_button_pressed(state: &mut BandState) {
    // 1. 振動フィードバック
    vibrate(Pattern::OkConfirm);

    // 2. BLE Notify送信
    ble_notify(Char::OkButton, &[0x01]);

    // 3. 転倒確認中ならキャンセル
    if let FallState::PostFall { .. } | FallState::Confirmed { .. } = state.fall_state {
        state.fall_state = FallState::Cancelled;
        ble_notify(Char::FallDetection, &[0xFF, 0x00]);  // キャンセルイベント
    }

    // 4. 長押し(3秒)でペアリングモード切替
    if button_held_ms() > 3000 {
        enter_pairing_mode();
    }
}
```

---

## BLEコード骨格

```rust
// KAGI Band Service UUID
const KAGI_BAND_SVC: BleUuid = BleUuid::from_u16(0x4B47);

// Characteristics
const CHAR_OK_BUTTON:    BleUuid = BleUuid::from_u16(0x4B01);
const CHAR_VIBRATION:    BleUuid = BleUuid::from_u16(0x4B02);
const CHAR_BATTERY:      BleUuid = BleUuid::from_u16(0x4B03);
const CHAR_FALL_DETECT:  BleUuid = BleUuid::from_u16(0x4B04);
const CHAR_STATUS:       BleUuid = BleUuid::from_u16(0x4B05);

// Advertising data
const ADV_NAME: &str = "KAGI-BAND";
const ADV_INTERVAL_MS: u16 = 500;  // 未接続時
const CONN_INTERVAL_MS: u16 = 500; // 接続中 省電力優先

// 振動コマンド受信ハンドラ (CHAR_VIBRATIONへのWriteコールバック)
fn on_vibration_write(data: &[u8]) -> Result<()> {
    if data.len() < 4 { return Err(anyhow!("invalid")); }
    let pattern_id = data[0];
    let intensity   = data[1];  // 0-100 (PWMデューティ%)
    let repeat      = data[2];
    let interval_ms = data[3] as u32 * 10;

    vibrate_pattern(pattern_id, intensity, repeat, interval_ms);
    Ok(())
}
```

---

## KAGI Lite/Hub側の対応実装

### Hub ファームウェアへの追加 (src/main.rs)

```rust
// BLEセントラルタスク追加
let band_handle = Arc::new(Mutex::new(None::<BandHandle>));

thread::Builder::new()
    .name("ble_central".into())
    .stack_size(8192)
    .spawn(move || {
        ble_central_task(band_handle, safety_monitor);
    })?;
```

```rust
fn ble_central_task(
    band: Arc<Mutex<Option<BandHandle>>>,
    safety: Arc<Mutex<SafetyMonitor>>,
) {
    loop {
        // KAGI-BANDをスキャン (UUID 0x4B47でフィルタ)
        if let Some(found) = ble_scan_for_band(Duration::from_secs(10)) {
            let handle = BandHandle::connect(found)?;

            // Notifyを購読
            handle.subscribe(Char::OkButton, {
                let safety = safety.clone();
                move |_data| {
                    if let Ok(mut m) = safety.lock() {
                        m.on_ok_button_pressed();  // 既存メソッドを流用
                    }
                }
            });

            handle.subscribe(Char::FallDetection, {
                let safety = safety.clone();
                move |data| {
                    if data[0] == 0x03 {  // confirmed fall
                        if let Ok(mut m) = safety.lock() {
                            m.on_fall_detected(data[1]);  // confidence
                        }
                    }
                }
            });

            *band.lock().unwrap() = Some(handle);
        }

        // Band未接続30分でACS減算
        if band.lock().unwrap().is_none() {
            warn!("Band未接続: ACS補正適用");
        }

        FreeRtos::delay_ms(5_000);
    }
}
```

### SafetyMonitor の拡張 (src/safety/mod.rs)

```rust
// 転倒検知イベント
pub fn on_fall_detected(&mut self, confidence: u8) {
    info!("転倒検知 (confidence={}%)", confidence);

    // 即時Tier1へ遷移
    if confidence >= 70 {
        self.state = SafetyState::Tier1Active {
            entered_at: Instant::now(),
            trigger: Trigger::FallDetected,
        };
        self.acs = (self.acs - 30.0).max(0.0);  // ACS急降下
    }
}

// ACS計算に「Band接続状態」を追加
fn compute_acs(&self) -> f32 {
    let base_acs = /* 既存計算 */;

    // Band接続ボーナス/ペナルティ
    let band_factor = match self.band_state {
        BandState::Connected => 1.0,    // 正常
        BandState::Disconnected(since) if since.elapsed() < Duration::from_secs(1800) => 0.95,
        BandState::Disconnected(_) => 0.85,  // 30分以上未接続 → -15%
    };

    base_acs * band_factor
}
```

---

## 省電力設計

```
動作状態と消費電流:
┌────────────────────────────────────┬──────────┐
│ 状態                               │ 電流     │
├────────────────────────────────────┼──────────┤
│ BLE接続中 (500ms interval)         │ ~7mA     │
│ BLE広告中 (500ms interval)         │ ~3mA     │
│ Light Sleep (GPIO/BLE wake)        │ ~800μA   │
│ Deep Sleep (GPIO wake only)        │ ~10μA    │
│ LIS2DH12 LP 10Hz                   │ ~2μA     │
│ 分圧抵抗 (常時)                    │ ~2μA     │
│ 振動モーター ON                    │ ~100mA   │
└────────────────────────────────────┴──────────┘

典型的な1日の使用パターン:
- BLE接続: 16時間 × 7mA = 112mAh
- Light Sleep: 8時間 × 0.8mA = 6.4mAh
- 振動: 5回/日 × 300ms × 100mA = 0.04mAh
合計: ~118mAh/日

→ 200mAh電池で **約1.7日** (接続維持モード)

省電力モード (接続間欠):
- Hub/LiteがBandを1時間ごとにBLE接続 → 30秒確認 → 切断
- Sleep中は Deep Sleep (10μA)
- 1時間あたり: 30秒×7mA + 3570秒×0.01mA = 0.058mAh + 0.0099mAh ≈ 0.068mAh/h
- 24時間: 1.63mAh → 200mAh/1.63mAh = **122日**

→ **省電力モードで120日以上** ✓
ただしボタン押下の即時反応には「接続維持モード」が必要。
→ 解決策: ユーザーが外出/帰宅をトリガーにモード切替 (Hub側でWiFiモニタ)
```

---

## OTA (Over-The-Air) アップデート

```rust
// KAGI Lite/Hub経由でBandファームウェアをOTA更新
// Hub: クラウドからfirmware.bin取得 → BLE OTA転送
// Band: ESP-IDF NimBLE OTA client で受信 → Flash書き込み

// BLE OTA Service (NimBLE標準)
// UUID: 0x8018 (Nordic DFU互換)
// Chunk size: 244 bytes (BLE 5.0 MTU)
// 200KBファーム = 820チャンク ≈ 3分 (BLE 1Mbps)
```

---

## ビルド・フラッシュ手順

```bash
# リポジトリ構造
kacha/
├── firmware/          # KAGI Lite/Hub (ESP32-S3)
└── firmware-band/     # KAGI Band (ESP32-C3)

# セットアップ
cd firmware-band
cargo install espflash espup
espup install  # ESP32-C3 (RISC-V) ツールチェーン

# ビルド
cargo build --release

# フラッシュ (USB-C接続)
cargo run --release
# または
espflash flash --monitor target/riscv32imc-esp-espidf/release/kagi-band

# OTAイメージ生成 (Hub経由配布用)
cargo build --release
esptool.py --chip esp32c3 elf2image \
  --output firmware-band.bin \
  target/riscv32imc-esp-espidf/release/kagi-band
```

---

## テスト計画

| テスト | 方法 | 合格基準 |
|-------|------|----------|
| BLEペアリング | Band+Hub近距離 | 10秒以内にペアリング完了 |
| ボタン応答性 | 押下→Hub通知 | 200ms以内にSafetyMonitor反映 |
| 振動強度 | 手首装着 | 睡眠中でも気づく振動強度 |
| 転倒検知 | ダミーを床に落下 | 90%以上検知、誤検知<1回/日 |
| 電池寿命 | 連続動作テスト | 省電力モード60日以上 |
| 防水 | IPX4 シャワーテスト | 正常動作継続 |
| BLE距離 | 屋内10m | 安定接続 |
| OTA更新 | 100KB ファームウェア | 5分以内に更新完了 |
