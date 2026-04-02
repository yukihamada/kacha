# KAGI Band — 回路設計ノート (KiCad設計者向け)

## 概要
KAGI Liteの手首パートナー。I'm OKボタン + 振動アラート + 転倒検知。
BLE5.0でLite/Hubとペアリング、常時装着でミッション完結度を大幅に向上させる。

```
サイズ: 35×30×9mm (PCB 35×30mm, ケース外形)
重量目標: 15g以下 (バンド除く)
防水: IP54 (シリコンシール)
充電: USB-C (底面) 約75分フルチャージ (200mA 1C)
電池寿命: 200mAh / RT9013(55μA) + ESP32-C3 Deep Sleep(10μA) ≈ 合計25μA平均
         = 200,000μAh ÷ 25μA ≈ 8000h ≈ 330日 (理論値)
         実使用 (BLE 1秒/min, 振動5回/日): 約60〜90日
```

> ⚠️ **認証・規制チェックリスト (量産前必須)**
> | 項目 | 対象 | 対応 |
> |------|------|------|
> | **技適** (電波法) | ESP32-C3-MINI-1U | ✅ 認証済 (209-J00143) |
> | **PSE** (電気用品安全法) | LiPo内蔵ウェアラブル | ❌ 要取得。DW01A+FS8205A保護回路で審査通過率↑ |
> | **薬機法** (PMDA) | 転倒検知機能 | ⚠️ 要法的確認。「医療機器」に該当しないよう訴求表現に注意 |
> | **個人情報保護法** | 転倒・位置・行動データ | ⚠️ 要配慮個人情報。プライバシーポリシー必須 |

---

## 1. ESP32-C3-MINI-1U ピンアサイン

| GPIO | 方向 | 機能 | 備考 |
|------|------|------|------|
| GPIO0 | INPUT | SW1 I'm OKボタン | RC遅延回路 (R_BOOT 100KΩ + C_BOOT 100nF) + 内蔵プルアップ。LOW=押下。BOOT兼用だがRC τ=10msでグリッチ吸収 |
| GPIO1 | OUTPUT | 振動モーター (MOSFET Gate) | PWM LEDC ch0、デューティ100%=強、50%=弱 |
| GPIO2 | OUTPUT | LED2 緑ステータス | BLEペアリング時点灯、アラート時点滅 |
| GPIO3 | INPUT | USB-C VBUS検出 | 充電中検知 分圧(5V→1.5V)→ADC不使用、GPIO入力として1/0 |
| GPIO4 | I/O | I2C SDA | LIS2DH12 SDA、4.7KΩプルアップ to 3.3V |
| GPIO5 | I/O | I2C SCL | LIS2DH12 SCL、4.7KΩプルアップ to 3.3V |
| GPIO6 | INPUT | ADC Vbat (電池残量) | R_VDiv1+R_VDiv2で1/2分圧 3.7V→1.85V (ADC 0-3.3V範囲内) |
| GPIO7 | INPUT | LIS2DH12 INT1 (転倒割り込み) | R_INT 10KΩ to 3.3V プルアップ。Free-fall検知で割り込み発生 |
| GPIO8 | OUTPUT | LED1 赤充電中 | ETA4054 CHRGピンで制御が理想だが簡略化のためGPIO直結も可 |
| GPIO18/19 | UART0 | USB-C D+/D- (JTAG/Flash) | プログラミング・デバッグ用、製品出荷後は封止 |

**GPIO0 Boot対策 (RC遅延回路)**:
ESP32-C3はGPIO0がBOOTピン。起動時LOW=ダウンロードモード。
SW1が押されたまま電源投入するとFlash書き込みモードに入る可能性がある。

**採用対策: RC遅延回路**
```
3.3V ── R_BOOT(100KΩ) ── GPIO0
                    │
               C_BOOT(100nF)
                    │
                   GND
```
τ = R×C = 100kΩ × 100nF = **10ms**

電源投入時、C_BOOTが充電される間GPIO0は0Vに近い値だが、
SW1が押されていない場合は10ms後に3.3Vに到達 → Boot通過。
SW1が押し続けられている場合のみGPIO0がLOWのままになるが、
日常使用での誤操作頻度は極めて低い (BOM_BANDに R_BOOT + C_BOOT追加済み)。

---

## 2. 電源回路

```
USB-C 5V ─── ETA4054S21F ─── DW01A+FS8205A (保護回路) ─── LiPo 200mAh
                  │
                CHRG → LED1(赤) + R_LED1(100Ω) → GND
                  │
              Vbat (3.7-4.2V) ─── RT9013-33GB ─── 3.3V rail
                  │
             R_VDiv1(1MΩ) ┬─ GPIO6(ADC)
                          │
                      R_VDiv2(1MΩ) ─── GND
```

### バッテリー保護回路 (DW01A + FS8205A) ← 必須
LiPo電池は保護なしでは発火・膨張リスク。PSE審査にも必須。
```
LiPo(+) ── FS8205A(S1) ── DW01A(B+) ── 3.3V回路
LiPo(-) ── FS8205A(S2) ── DW01A(B-) ── GND
DW01A.DO → FS8205A.G1 (過放電時に放電FETをOFF)
DW01A.CO → FS8205A.G2 (過充電時に充電FETをOFF)
```
| 保護機能 | 閾値 |
|---------|------|
| 過充電保護 | 4.25V |
| 過放電保護 | 2.50V |
| 過電流保護 | ~3A (短絡) |

### LDO RT9013-33GB (AMS1117代替)
- AMS1117-3.3: Iq = **5mA** (スタンバイ時も5mA消費 → 200mAh÷5mA = 40h で枯渇)
- RT9013-33GB: Iq = **55μA** → 200mAh÷55μA = 3636h ≈ 150日 (圧倒的に有利)

### 充電IC ETA4054S21F 設定
- `PROG` ピンに **R_PROG = 6KΩ** → `I_charge = 1200/6000 = 200mA (1C)`
  - 200mAh電池の適正充電レート (0.5C〜1C推奨)
  - 充電時間: 200mAh ÷ 200mA × 1.25(効率) ≈ **約75分でフル充電**
  - ⚠️ 2.4KΩ(500mA/2.5C)は厳禁: LiPo劣化加速・最悪膨張
- `CE` ピン: VCCへプルアップ (常時充電イネーブル)
- 充電完了後 ETA4054S21F が自動停止 (トリクル充電付き)

### 電池残量計算 (ADC)
```
Vbat → R_VDiv1(1MΩ) → GPIO6 → R_VDiv2(1MΩ) → GND
V_ADC = Vbat × 1/(1+1) = Vbat/2

LiPo 電圧-容量対応:
4.20V → 100% (V_ADC = 2.10V)
3.90V → 70%  (V_ADC = 1.95V)
3.70V → 40%  (V_ADC = 1.85V)
3.50V → 10%  (V_ADC = 1.75V)
3.30V → 0%   (V_ADC = 1.65V) ← 保護回路がここで切断
```

分圧抵抗を1MΩ×2にすることで静止電流 = 3.7V/2MΩ = **1.85μA** と極小。

---

## 3. 振動モーター制御

```
GPIO1 ─── R_Gate(0Ω or 33Ω) ─── 2N7002 Gate
                                  2N7002 Drain ─── 振動モーター(+) ─── 3.3V
                                  2N7002 Source ─── GND
```

フライバックダイオード: ERM(コイン型)はインダクタンス小さいが念のため追加推奨。
→ **振動モーターと並列に1N4148 (アノードGND、カソード3.3V)** を追加。

### 振動パターン (ファームウェア定義)
| パターン | 意味 | 振動 |
|---------|------|------|
| `OK_CONFIRM` | I'm OKボタン押下確認 | 1回 短(200ms) |
| `DAILY_CHECK` | 毎日の安否確認リマインダー | 3回 弱(100ms×3) |
| `TIER1_ALERT` | Tier1: 要確認アラート | 3回 強(300ms-200ms-300ms) |
| `TIER2_URGENT` | Tier2: 家族通知済み | 連続 強(5秒間断続) |
| `PAIR_SUCCESS` | BLEペアリング完了 | 2回 弱 |
| `LOW_BATTERY` | 電池残量10%以下 | 1回 弱 (毎時) |

---

## 4. LIS2DH12 転倒検知

### I2C接続
- `SDO/SA0` = **GND** → アドレス **`0x18`** (ファームウェアと一致)
  - ※SDO=HIGHにすると0x19だが、配線を簡略化するためGND固定
- `CS` = VCC (I2Cモード固定)
- `INT1` → ESP32-C3 **GPIO7** (割り込み入力、R_INT 10KΩ外部プルアップ済み)

### レジスタ設定 (初期化シーケンス)
```
// Normal Mode 25Hz (ODR=0x03, LP_EN=0)
CTRL_REG1 = 0x37  // ODR=0011(25Hz), LPen=0, Zen=Yen=Xen=1

// HPF有効 (INT1へ高周波成分を通す → 重力成分除去)
CTRL_REG2 = 0x09  // FDS=1(出力HPF適用), HPIS1=1(INT1にHPF適用)

// INT1にIA1割り込みをルーティング
CTRL_REG3 = 0x40  // I1_IA1=1

// ±2g フルスケール, BDU有効
CTRL_REG4 = 0x80  // BDU=1, FS=00(±2g)

// INT1ラッチ (読み出しでクリア)
CTRL_REG5 = 0x08  // LIR_INT1=1

// Free-Fall検知 (INT1_THS, INT1_DUR)
INT1_CFG  = 0x95  // AOI=1, ZLIE=YLIE=XLIE=1 → 全軸AND(全軸が閾値以下でFree-fall)
INT1_THS  = 0x10  // 閾値 = 16LSB × 16mg/LSB(@±2g) = 256mg ≈ 0.25g
INT1_DUR  = 0x05  // 持続時間 = 5/25Hz = 200ms

// Click検知 (衝撃: Double-Click = INT2)
CLICK_CFG = 0x15  // 単軸クリック検知 (XS+YS+ZS)
CLICK_THS = 0x40  // 衝撃閾値 = 64 * 16mg ≈ 1g
TIME_LIMIT = 0x08
TIME_LATENCY = 0x10
TIME_WINDOW = 0x50
```

### 転倒判定アルゴリズム
```
状態機械:
NORMAL → [Free-fall INT1 fires (|a| < 0.25g, 500ms)] → FALLING
FALLING → [Impact detected OR 3秒タイムアウト] → POST_FALL
POST_FALL → [静止 (|a| ≈ 1g) 2秒継続] → FALL_CONFIRMED → BLE通知
POST_FALL → [起き上がり動作 (|a| > 1.3g)] → NORMAL (誤検知として破棄)

誤検知対策:
- 着席・起立動作は除外 (y軸傾き変化でフィルタ)
- 「転んですぐ起き上がった場合」は通知しない (POST_FALLで正常復帰)
- ユーザーが10秒以内にI'm OKボタンを押せばキャンセル
```

---

## 5. BLE プロトコル設計

### サービス定義
```
KAGI Band Service: 128-bit UUID
  Base UUID: 494B4147-0000-1000-8000-00805F9B34FB  ("IKAG" in ASCII)
  Short UUID (16-bit): 0x4B47  ("KG")

Characteristics:
  0x4B01 - OK Button Event (Notify, 1byte)
           0x01 = ボタン押下, 0x00 = リリース

  0x4B02 - Vibration Command (Write Without Response, 4bytes)
           [pattern_id(1), intensity(1: 0-100%), repeat(1), interval_ms(1: ×10ms)]

  0x4B03 - Battery Level (Read + Notify, 1byte)
           0-100% (BAS: Battery Service互換)

  0x4B04 - Fall Detection Event (Notify, 2bytes)
           [event_type(1): 0x01=free-fall 0x02=impact 0x03=confirmed-fall, confidence(1)]

  0x4B05 - Device Status (Read, 4bytes)
           [battery%, fw_version(2), flags(1): b0=charging b1=paired b2=ble_connected]
```

### 接続シーケンス
```
1. Band起動 → BLE広告開始
   Advertising interval: 500ms (未接続時)
   Advertising data: Device name "KAGI-BAND-XXXX" (末尾4文字はデバイスID)

2. KAGI Hub/Lite がスキャン → アドバタイズ発見
   Hub/Lite側でUUID 0x4B47 フィルタリング

3. 接続確立 → GATT Discovery → Notify登録
   Connection interval: 500ms (省電力)
   Supervision timeout: 6秒

4. 接続維持中:
   - Band → Hub: OK Button / Fall Detection notify (イベント駆動)
   - Hub → Band: Vibration Command write (Tier1/2アラート時)
   - 1分ごと: Battery Level notify

5. 接続断 (WiFiダウン等) → Hub側でBand信号なし30分 → Safety ACSに-10点
```

---

## 6. PCBレイアウト指示

```
基板サイズ: 35mm × 30mm (2層)
厚み: 0.8mm (標準1.6mmより薄く、軽量化)
シルク: 白、KAGI ロゴ + "BAND v1.0"

コンポーネント配置:
┌─────────────────────────────────────┐
│  [USB-C]  [LED赤] [LED緑]           │  ← 下辺: 充電コネクタ、インジケーター
│                                     │
│     [ETA4054]  [AMS1117]            │  ← 電源段をまとめる
│                                     │
│  [ESP32-C3-MINI-1U 中央]            │  ← MCU中央配置
│                                     │
│    [LIS2DH12]   [2N7002]            │
│                                     │
│  ○[SW1 大型ボタン 12mm]○           │  ← 上辺: ボタン露出穴に合わせる
└─────────────────────────────────────┘
       ↑                    ↑
  バッテリー                振動モーター
  コネクタ                  (ケーブル引き出し)

ビア設計:
- 電源ビア (GND/3.3V): 0.4mm ドリル
- 信号ビア: 0.2mm ドリル
- ESP32-C3のGND放熱パッド: ソリッドビア×4

EMC対策:
- ESP32-C3アンテナ (uFL)周囲に銅箔ベタを置かない (2mm以上クリア)
- BLEアンテナがケースの外に出るよう配置を検討 (または非金属ケース使用)
- ETA4054の充電ループ面積を最小化 (VIN-LiPo間を短く)
```

---

## 7. ケース設計指示

```
外形: 35(L) × 30(W) × 9(H) mm 丸角R3mm
材質: ABS + UVコーティング (医療グレード白またはKAGI緑)
バンド幅: 22mm (Apple Watch幅互換、汎用シリコンバンド使用可)

穴・窓:
- 上面: SW1ボタン窓 13×13mm (シリコンOリングでIP54シール)
- 上面: LED窓 2×2mm ×2 (赤・緑)
- 底面: USB-C穴 10×4mm (シリコンキャップ付き)
- 側面: 振動モーター通気孔 (不要、コイン型は密封可)

バンド取り付け:
- ラグ幅 22mm バネ棒対応
- バンドを挿入するスロット形状 (工具不要交換)

組み立て順序:
1. PCBにLiPoをJST接続
2. 振動モーターをPCBにはんだまたはテープ固定
3. PCBをケース下蓋にスナップ固定 (ネジレス)
4. 上蓋を合わせてUV接着 (防水)
   ⚠️ ボタンのシリコンシールを先に嵌め込むこと

重量: PCB+部品 5g + LiPo 4g + ケース 4g + バンド 10g = **約23g**
```

---

## 8. 量産・認証

### 技適認証
- ESP32-C3-MINI-1Uは技適取得済み (証明番号: 209-J00143)
- カスタム基板でのモジュール使用なので本体の追加認証不要
- ただし最終製品として**「工事設計認証の範囲内での使用」**を確認すること

### JLCPCB SMT発注
```
Gerber: 標準設定
Part placement: LCSC部品はJLCPCB在庫から自動選択
組立: SMT両面 (ESP32-C3のみ Top面大型部品)
特記: LIS2DH12 (LGA-12) はJLCPCB拡張部品ライブラリを確認
Via in pad: ESP32-C3 GNDパッド → 埋め込みビア推奨 (追加費用$10程度)
```

### ファーストロット
- 試作: 10台 (SMT組立込み) ≈ $250 (JLCPCB見積)
- バンドとケースは別途 AliExpress / 国内問屋
- 組み立て (バンド+ケース): 工場ライン前は手作業 5分/台
