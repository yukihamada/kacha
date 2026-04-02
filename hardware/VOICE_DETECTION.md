# KAGI Home — 音声ウェイクワード「大丈夫」検知 設計書

> 「ボタンを押す動作すら難しい時でも、声だけで命の証明ができる」

---

## 1. 設計概要

### 1-1. 目的

I'm OK ボタンの押下が困難な状況 (手が塞がっている、体が動かせない等) でも、
「大丈夫」「はい」「OK」という声だけで生存確認イベントを送信できるようにする。

**音声検知イベントは I'm OK ボタン押下と同等の確認イベントとして扱う。**
つまり signing.rs の `ProofEvent::OkButton` を生成し、ATECC608A で署名する。

### 1-2. プライバシーファースト設計の原則

```
[マイク] → [ESP32-S3 DSP] → [TFLite Micro モデル] → [ウェイクワード判定]
                                                              │
                                          YES → ProofEvent::OkButton (署名)
                                          NO  → 音声データを即廃棄

音声データは ESP32-S3 の内部 SRAM のみで処理。
クラウドへは「検知した」という署名済みイベントのみを送信。
生の音声データはどこにも保存・送信しない。
```

**「音声録音デバイスではない」ことを設計・実装・ユーザー説明の全レベルで担保する。**

---

## 2. ハードウェア構成

### 2-1. マイク選定

| 候補 | 型番 | インターフェース | SNR | 消費電流 | 推奨 |
|------|------|--------------|-----|--------|------|
| MEMS デジタル | INMP441 | I2S | 61dB | 1.4mA | **推奨** |
| MEMS デジタル | SPH0645 | I2S | 65dB | 0.9mA | 代替 |
| MEMS アナログ | MAX4466 | ADC | 60dB | 24μA | 低消費 |

**推奨: INMP441 (I2S 接続)**
- ESP32-S3 の I2S ペリフェラルと直接接続 → CPU 負荷なしでサンプリング
- 16kHz / 16bit でサンプリング (TFLite Micro DS-CNN モデルの入力仕様に合わせる)
- SNR 61dB は室内 (背景雑音 40dB 想定) で十分な品質

### 2-2. GPIO 割り当て (main.rs の pins モジュールと整合)

```rust
// 音声検知用 (Hub / Pro モデルのみ)
// Lite モデルはマイク非搭載 → 音声検知は未対応
pub const MIC_SCK: i32 = 41;   // I2S SCK (BCLK)
pub const MIC_WS: i32 = 42;    // I2S WS (LRCLK)
pub const MIC_SD: i32 = 40;    // I2S SD (Data In)
```

### 2-3. オーディオパイプライン

```
[INMP441 マイク]
    │ I2S 16kHz/16bit
    ▼
[ESP32-S3 I2S ペリフェラル]
    │ DMA 転送 (CPU 不要)
    ▼
[音声バッファ: 1秒 = 16,000サンプル × 2byte = 32KB SRAM]
    │
    ▼
[DSP前処理: esp-idf DSP component]
    ├── プリエンファシス フィルタ (高域強調)
    ├── ハミング窓 (25ms フレーム、10ms ホップ)
    ├── FFT → パワースペクトル
    └── メル周波数フィルタバンク (40バンド)
    │
    ▼
[MFCC 特徴量: 49フレーム × 10係数 = 490次元]
    │
    ▼
[TFLite Micro 推論エンジン]
    │ DS-CNN モデル (< 40KB)
    ▼
[出力: softmax確率]
    ├── "大丈夫": 0.0〜1.0
    ├── "はい": 0.0〜1.0
    ├── "OK": 0.0〜1.0
    └── "その他/雑音": 0.0〜1.0
```

---

## 3. TFLite Micro モデル

### 3-1. モデルアーキテクチャ: DS-CNN (Depthwise Separable CNN)

DS-CNN (DS=Depthwise Separable) は通常の CNN に比べてパラメータ数を 8〜9倍削減できる
軽量アーキテクチャで、キーワードスポッティングに特に有効。

Google の `speech_commands` データセットでの標準ベンチマーク:
- 精度: 94.4% (DS-CNN-S、従来モデル比 +3.5%)
- モデルサイズ: **約 28KB** (SPIFFS 領域内に収まる)
- 推論時間: ESP32-S3 @ 240MHz で 約 25ms / フレーム

**参照実装**: `tensorflow/tflite-micro-speech-experiments`

```
DS-CNN-S アーキテクチャ (KAGI 向けカスタム版):

入力: [1, 49, 10, 1]  # [batch, time_frames, mfcc_coeffs, channels]
    │
    Conv2D (64 filters, 10×4 kernel, stride 1)
    BatchNorm + ReLU6
    │
    DepthwiseConv2D (stride 2)  × 4 blocks
    PointwiseConv2D (64 filters) × 4 blocks
    BatchNorm + ReLU6
    │
    AveragePooling2D (global)
    │
    Dense (4 units)  # 大丈夫 / はい / OK / 雑音
    Softmax
    │
出力: [1, 4]  # 各クラスの確率
```

### 3-2. モデルサイズ管理

| コンポーネント | サイズ |
|-------------|--------|
| TFLite Micro ランタイム (esp-idf 組み込み) | ~16KB (ライブラリ) |
| DS-CNN モデルファイル (.tflite) | ~28KB |
| MFCC 計算用バッファ | ~8KB SRAM |
| テンソルアリーナ (推論作業領域) | ~10KB SRAM |
| **合計 Flash (SPIFFS)** | **~36KB** |
| **合計 SRAM** | **~50KB** |

SPIFFS パーティション割り当て (partitions.csv):
```csv
# Name,   Type, SubType, Offset,   Size,    Flags
nvs,      data, nvs,     0x9000,   0x5000,
otadata,  data, ota,     0xe000,   0x2000,
ota_0,    app,  ota_0,   0x10000,  0x180000,
ota_1,    app,  ota_1,   0x190000, 0x180000,
spiffs,   data, spiffs,  0x310000, 0xF0000,  # 960KB: モデル + 設定
```

SPIFFS 内のモデルパス: `/spiffs/wake_model.tflite`

### 3-3. 推論判定ロジック

```rust
// 推論結果の判定 (誤検知低減のための平滑化)
// 連続 3フレーム (= 30ms) でスコアが閾値を超えた場合のみ検知とする

const WAKE_THRESHOLD: f32 = 0.85;  // 感度: 高すぎると誤検知、低すぎると見逃し
const CONFIRM_FRAMES: usize = 3;   // 連続フレーム数

// 推論後の判定フロー:
// frame_scores[i] > WAKE_THRESHOLD が CONFIRM_FRAMES 回連続
//   → ProofEvent::OkButton を生成
//   → 5秒間の不応期 (チャタリング防止)
```

---

## 4. ESP32-S3 オンデバイス音声処理

### 4-1. esp-idf DSP コンポーネント活用

esp-idf には `esp-dsp` という DSP 最適化ライブラリが付属している。
ESP32-S3 の Xtensa LX7 コアは SIMD 命令セット (PIE) を持ち、
FFT 演算を最大 4倍高速化できる。

```c
// esp-dsp を使った FFT の例 (C API、Rust の FFI で呼び出し)
// esp_err_t dsps_fft2r_fc32(float *data, int N)

// Rust 側での利用方法:
// esp_idf_sys を経由してバインドするか、
// esp-idf-hal の dsp feature flag を有効にする
```

### 4-2. Rust 実装フロー (sensors/voice.rs として実装予定)

```rust
// sensors/voice.rs の構造 (実装時の参照用)

use esp_idf_hal::i2s::{I2sDriver, I2sStdConfig};
use esp_idf_hal::delay::FreeRtos;

pub struct VoiceDetector {
    // I2S ドライバ (INMP441 との接続)
    i2s: I2sDriver<'static>,
    // TFLite Micro インタープリタ (esp-idf の tflite-micro crate を使用)
    // または C FFI で呼び出し
    model_data: &'static [u8],  // include_bytes!("/spiffs/wake_model.tflite") 相当
    // 直近フレームのスコア履歴 (平滑化用)
    score_history: [f32; 5],
    // 不応期カウンタ (誤検知防止)
    cooldown_frames: u32,
}

impl VoiceDetector {
    // 初期化: I2S + TFLite Micro インタープリタのセットアップ
    pub fn new(i2s: I2sDriver<'static>) -> Result<Self>

    // 音声バッファを処理し、ウェイクワードを検知した場合 true を返す
    // 10ms ごとに呼び出す (= 1フレームのホップサイズ)
    pub fn process_frame(&mut self) -> bool

    // DMA バッファから音声サンプルを読み出す
    fn read_samples(&mut self) -> [i16; 160]  // 16kHz × 10ms = 160サンプル

    // MFCC 特徴量を計算する
    fn compute_mfcc(&self, samples: &[i16]) -> [[f32; 10]; 49]

    // TFLite Micro で推論を実行する
    fn run_inference(&self, mfcc: &[[f32; 10]; 49]) -> [f32; 4]
}
```

### 4-3. タスクスケジューリング

音声処理は FreeRTOS タスクとして独立して動作する。
main.rs の他のタスク (センサー監視、クラウド通信) とのリソース競合を避けるため、
Core 1 (アプリケーションコア) に固定する。

```rust
// main.rs での音声タスク起動 (Hub/Pro モデルのみ)
#[cfg(any(feature = "hub", feature = "pro"))]
{
    let _voice_task = thread::Builder::new()
        .name("voice_detect".into())
        .stack_size(8 * 1024)  // 8KB スタック (TFLite Micro のテンソルアリーナ込み)
        .spawn(move || {
            let mut detector = VoiceDetector::new(i2s_mic).unwrap();
            loop {
                if detector.process_frame() {
                    // ウェイクワード検知! → メインタスクに通知
                    let event = ProofEvent::OkButton;
                    event_queue.send(event).ok();
                }
                FreeRtos::delay_ms(10);  // 10ms = 1フレームのホップ
            }
        })?;
}
```

---

## 5. 多言語対応設計

### 5-1. 対象ウェイクワード

| 言語 | ウェイクワード | 発音表記 | 優先度 |
|------|-------------|---------|--------|
| 日本語 | 大丈夫 | だいじょうぶ | 最優先 |
| 日本語 | はい | / | 日本語2 |
| 英語 | OK | /oʊˈkeɪ/ | 英語 |
| 英語 | I'm fine | /aɪm faɪn/ | 英語2 |
| 中国語 | 没问题 | méi wèntí | 将来対応 |
| 韓国語 | 괜찮아요 | gwaenchanh-ayo | 将来対応 |

### 5-2. 「大丈夫」の音響的特徴

日本語の「大丈夫」は 4モーラ (だ・い・じょ・う・ぶ) で構成される。
英語の "OK" や "Yes" より音節数が多く、**偽陽性 (誤検知) が起きにくい**利点がある。

モデル学習では以下の多様性を確保する:
- 年齢: 60代〜90代の高齢者音声を重点的に収集
- 音量: 普通 (60dB) + 小声 (45dB) + 大声 (75dB)
- 距離: 0.3m / 1m / 3m (部屋の端から話しかける場合)
- 背景雑音: TV音声 / 換気扇 / 雨音 / 無音

### 5-3. NVS によるウェイクワード設定

```rust
// 入居者がアプリから設定するウェイクワード言語
// NVS に "voice_lang" キーで保存
// デフォルト: "ja" (日本語)
pub enum WakeLang {
    Japanese,  // 大丈夫 / はい
    English,   // OK / I'm fine
    Chinese,   // 没问题
}
```

---

## 6. 学習データ収集方針

### 6-1. データ収集の倫理

- **同意取得**: 録音協力者には書面で同意を取得
- **匿名化**: 音声データに個人識別情報を含めない
- **保存期間**: モデル学習完了後、3ヶ月で削除
- **使用目的外禁止**: KAGI のウェイクワードモデル学習のみに使用

### 6-2. 目標データ量

| クラス | 目標サンプル数 | 最低サンプル数 |
|--------|-------------|-------------|
| 大丈夫 | 5,000 発話 | 1,000 発話 |
| はい | 3,000 発話 | 500 発話 |
| OK | 3,000 発話 | 500 発話 |
| 雑音 / 背景音 | 10,000 サンプル | 2,000 サンプル |

初期モデル (v1.0) は Google の `speech_commands` データセット
(35単語 × 各 2,000〜3,000 サンプル、CC BY 4.0) をベースに
日本語「大丈夫」のデータを追加して転移学習する。

### 6-3. データ拡張 (Augmentation)

学習データ不足を補うために以下の拡張を適用:
- **時間伸縮**: ±10% (話すスピードの個人差を吸収)
- **ピッチシフト**: ±2半音 (声の高さの個人差)
- **ホワイトノイズ付加**: SNR 10〜30dB
- **残響付加**: 部屋の反響シミュレーション (RIR)

---

## 7. モデル学習パイプライン

### 7-1. 使用フレームワーク

```bash
# 学習環境 (PC / クラウド GPU)
pip install tensorflow==2.12.0  # TFLite 変換ツール込み
pip install librosa              # 音声特徴量抽出

# 学習スクリプト (train_wake_model.py)
python train_wake_model.py \
  --data_dir ./data/speech_commands/ \
  --model_architecture ds_cnn \
  --target_keywords "daijoubu,hai,okay" \
  --window_size_ms 25 \
  --window_stride_ms 10 \
  --feature_type mfcc \
  --num_mfcc 10 \
  --sample_rate 16000 \
  --epochs 30 \
  --batch_size 32

# TFLite 変換 (量子化: int8)
python convert_to_tflite.py \
  --saved_model ./saved_model/ \
  --output wake_model.tflite \
  --quantize int8             # サイズ 1/4 + 推論速度 4倍
```

### 7-2. 量子化 (Int8 Quantization)

TFLite Micro は int8 量子化を推奨する。
Float32 モデルに比べて:
- **サイズ**: 1/4 (28KB → 7KB)
- **推論速度**: 2〜4倍高速
- **精度低下**: 通常 < 1% (許容範囲内)

量子化後の最終モデル仕様:
- ファイルサイズ: **< 10KB** (SPIFFS 余裕で収まる)
- SRAM 使用量: **< 30KB** (テンソルアリーナ含む)
- 推論時間: **< 15ms @ 240MHz**

### 7-3. OTA でのモデル更新

モデルは SPIFFS に配置するため、app パーティションの OTA とは独立して更新できる。

```
サーバー: GET /api/v1/device/voice-model?version=X
  → 204 (最新) or 200 + モデルバイナリ

デバイス側:
  1. 新バージョンをダウンロード → /spiffs/wake_model_new.tflite に保存
  2. モデルの整合性チェック (SHA-256)
  3. /spiffs/wake_model.tflite をリネームして差し替え
  4. voice_detect タスクを再起動 (モデルリロード)
```

---

## 8. プライバシー設計の詳細

### 8-1. データフロー図 (プライバシー保護)

```
[マイク] ─I2S─► [ESP32-S3 SRAM 内バッファ: 1秒分]
                         │
                    ウェイクワード判定
                   (SRAM 内のみ処理)
                         │
              ┌──────────┴──────────┐
              │ YES (検知)          │ NO (非検知)
              ▼                     ▼
        [署名イベント生成]      [バッファ即時クリア]
        ATECC608A 署名              (音声データ消滅)
              │
        [サーバー送信]
        {"event":"ok_button","sig":"..."}
        ← 生音声は含まない
```

### 8-2. プライバシー保護の保証事項

| 項目 | 設計上の保証 | 検証方法 |
|------|------------|---------|
| 音声クラウド送信なし | コード審査 + パケットキャプチャ | 第三者監査 |
| 音声 Flash 書き込みなし | SPIFFS マウントポリシー (読み取り専用 for 音声) | ファームウェア静的解析 |
| 連続録音なし | タスクは 10ms ごとにフレーム処理後バッファクリア | コード審査 |
| ウェイクワード以外は破棄 | 推論結果が閾値以下なら即 memset 0 | コード審査 |

### 8-3. ユーザー向け説明文 (アプリ / 取扱説明書に掲載)

> KAGI の音声ウェイクワード機能は、「大丈夫」などの言葉を検知するために
> ESP32-S3 チップ内部でのみ音声を処理します。
> 音声データはインターネットに送信されず、デバイス内に録音・保存もされません。
> 検知したという「事実」のみが、暗号署名付きのデータとして送信されます。
> 常時録音デバイスではありません。

---

## 9. 実装スケジュール

| マイルストーン | 期間 | 完了条件 |
|-------------|------|---------|
| データ収集 (1,000サンプル) | 4週間 | 「大丈夫」1,000発話録音完了 |
| モデル v1.0 学習 | 1週間 | テスト精度 > 90% |
| ESP32-S3 ポーティング | 2週間 | 実機で 10ms/フレーム以内に推論完了 |
| 誤検知チューニング | 2週間 | 誤検知率 < 1件/時間 |
| Hub モデル統合テスト | 2週間 | 実際の高齢者環境でのフィールドテスト |
| **v1.0 リリース** | **11週間後** | アプリから音声検知のオン/オフ設定可能 |

---

## 10. 実装 TODO (sensors/voice.rs)

```rust
// TODO リスト (実装時に参照)
// [ ] I2S ドライバ初期化 (INMP441, 16kHz/16bit/mono)
// [ ] DMA バッファからのサンプル読み出し (160サンプル/10ms)
// [ ] プリエンファシス フィルタ実装 (係数 0.97)
// [ ] ハミング窓適用 (25ms = 400サンプル)
// [ ] esp-dsp の dsps_fft2r_fc32 で FFT 計算
// [ ] メルフィルタバンク (40バンド、mel_filterbank.h 参照)
// [ ] MFCC 係数 10次元を抽出 (log + DCT)
// [ ] TFLite Micro インタープリタの初期化
//     (tflite::MicroInterpreter, tflite::ops::micro::AllOpsResolver)
// [ ] 推論実行と softmax 出力の読み出し
// [ ] 連続フレーム平滑化 (スコア履歴 5フレーム)
// [ ] 閾値判定 + 不応期管理
// [ ] ProofEvent::OkButton をイベントキューに送信
// [ ] feature flag: cfg(any(feature = "hub", feature = "pro")) でガード
```

---

*最終更新: 2026-03-26*
*このドキュメントは sensors/voice.rs の実装仕様書として機能する。*
*実装完了後は実際の精度測定値でベンチマーク数値を更新すること。*
