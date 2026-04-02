# ベッド下圧電センサーオプション — KAGI Lite 拡張モジュール

## 概要

LD2410B (mmWaveレーダー) は壁越し・布団越しでも反応するが、
厚い羽毛布団や特定の体勢では死角が生じる。
圧電センサーをマットレス下に敷くことで「就寝中の呼吸・脈波」を
直接検知し、夜間の安否確認精度を大幅に向上させる。

```
LD2410B (mmWave)     → 在室・呼吸検知 (3m以内)
圧電センサー          → ベッド上の微細振動 (呼吸・心拍由来)
両者の AND条件        → 夜間の生存確信度を 2倍以上 向上
```

---

## センサー仕様

| 項目 | 仕様 |
|------|------|
| センサータイプ | PVDF圧電フィルム (Measurement Specialties DT1028K, ~$3) |
| 代替品 | 汎用圧電センサー 27mm φ ($0.30/個) — 感度は劣るが十分 |
| 出力 | アナログ電圧 (呼吸: ~10mV p-p, 心拍: ~2mV p-p) |
| ESP32-S3 接続 | ADC1_CH0 (GPIO1) ← 既存の GPIO割り当てと要調整 |
| コネクタ | JST PH 2P (KAGI Liteの J2 ドアセンサーと兼用ポート) |
| 設置方法 | マットレス下にテープで固定、ケーブルは床を這わせる |

---

## 回路設計

圧電素子の出力は非常に微弱なため、前置増幅が必要:

```
圧電センサー → [INA122P 計装アンプ Gain=100倍] → ADC (ESP32-S3 GPIO1)
                    │
                 +3.3V / GND
```

ただし KAGI Lite 本体 PCB への実装は複雑になるため、
**別基板 (KAGI Lite Bed Module)** として分離を推奨:

```
[KAGI Lite 本体]  ←─JST PH 2P─→  [Bed Module PCB 15×15mm]
                                        INA122P + 圧電
```

Bed Moduleのコストは ~$1.20 (INA122P $0.90 + 基板 $0.30)。

---

## ファームウェア処理

```rust
// firmware/src/sensors/bed.rs

const BREATH_FREQ_MIN: f32 = 0.1; // 6 BPM
const BREATH_FREQ_MAX: f32 = 0.5; // 30 BPM
const HEART_FREQ_MIN: f32 = 0.8;  // 48 BPM
const HEART_FREQ_MAX: f32 = 2.5;  // 150 BPM

pub struct BedSensor {
    buffer: [i16; 256],  // 10Hz × 25.6秒
    write_idx: usize,
}

impl BedSensor {
    // ADC値をバッファに蓄積 (10Hz でサンプリング)
    pub fn push_sample(&mut self, raw_adc: i16)

    // FFTで呼吸周波数成分を抽出 (0.1-0.5Hz)
    pub fn detect_breathing(&self) -> Option<f32> // BPM or None

    // FFTで心拍周波数成分を抽出 (0.8-2.5Hz)
    pub fn detect_heartbeat(&self) -> Option<f32>  // BPM or None

    // ACS入力用シグナル (0.0-1.0)
    pub fn alive_signal(&self) -> f32
}
```

---

## ACS への組み込み

```rust
// safety/mod.rs に追加
SensorWeights {
    mmwave: 5.0,
    ok_button: 4.0,
    door: 3.0,
    bed_sensor: 4.0,  // ← 追加 (夜間は mmwave と同等の重みを持つ)
    ...
}

// 夜間 (就寝時間帯) は bed_sensor の重みを動的に上昇
if rhythm.is_sleep_time(current_hour) {
    weights.bed_sensor *= 1.5;
    weights.door *= 0.3;  // 就寝中はドア開閉しないので重みを下げる
}
```

---

## 設置手順 (エンドユーザー向け)

```
1. Bed Module の圧電センサーをマットレスの下、
   背中の位置に合わせて粘着テープで固定

2. JST PH ケーブルを KAGI Lite の J2 ポートに接続
   (ドアセンサーとの排他使用 — 設定アプリで切替)

3. KAGI アプリ → センサー設定 → 「ベッドセンサー」を選択

4. 翌朝に自動キャリブレーション完了
   (最初の就寝時に呼吸・心拍のベースラインを学習)
```

---

## SKU 設計案

| SKU | 内容 | 価格 |
|-----|------|------|
| KAGI-LITE | 本体のみ | ¥2,980 |
| KAGI-LITE-BED | 本体 + ベッドモジュール | ¥3,980 (+¥1,000) |
| KAGI-LITE-BUNDLE | 本体 + Band + ベッドモジュール | ¥8,980 |

夜間の誤検知 (「起きているのに就寝中と誤認」) を防ぐ効果が高く、
家族の信頼性向上に直結するため、バンドルでの提供を推奨。
