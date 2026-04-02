# KAGI Sensor Hub - 発注ガイド

## 概要

このガイドでは、KAGI Sensor Hubの基板設計から発注、受領、ファームウェア書き込みまでの
全ステップを解説する。

---

## Step 1: KiCadで基板設計 → Gerber出力

### 1.1 KiCadプロジェクト作成
```bash
# KiCadインストール (macOS)
brew install kicad

# プロジェクト作成
mkdir -p /Users/yuki/workspace/kacha/hardware/kicad
cd /Users/yuki/workspace/kacha/hardware/kicad
# KiCad GUIでプロジェクトを新規作成: kagi-sensor-hub.kicad_pro
```

### 1.2 回路図設計 (Schematic)
1. KiCadのSchematic Editorを開く
2. `schematic_notes.md` のピンアサインに従って回路図を作成
3. ERC (Electrical Rules Check) を実行してエラーゼロを確認
4. フットプリントを各シンボルに割り当て

### 1.3 基板レイアウト (PCB)
1. PCB Editorに回路図をインポート
2. 基板外形を 55mm x 55mm に設定
3. 4層基板の設計ルール:
   - 最小配線幅: 0.15mm (JLCPCB 4層基板の最小値)
   - 最小ビア: 0.3mm径 / 0.15mm穴
   - 最小クリアランス: 0.15mm
4. 部品配置 → 配線 → DRC (Design Rules Check) 実行

### 1.4 Gerberファイル出力
```
KiCad → File → Plot
  - 出力フォーマット: Gerber (RS-274X)
  - 出力レイヤー:
    □ F.Cu (前面銅箔)
    □ In1.Cu (内層1)
    □ In2.Cu (内層2)
    □ B.Cu (背面銅箔)
    □ F.SilkS (前面シルク)
    □ B.SilkS (背面シルク)
    □ F.Mask (前面ソルダーマスク)
    □ B.Mask (背面ソルダーマスク)
    □ Edge.Cuts (基板外形)
    □ F.Paste (前面ペースト)
    □ B.Paste (背面ペースト)
  - 座標精度: 4.6
  - 「Use Protel filename extensions」にチェック

KiCad → File → Fabrication Outputs → Drill Files
  - フォーマット: Excellon
  - 「PTH and NPTH in single file」にチェック
  - 座標精度: 3:3 (metric)
```

### 1.5 出力ファイル確認
```bash
# Gerberビューアで確認 (KiCad内蔵 or gerbv)
ls hardware/kicad/gerber/
# 期待するファイル:
# kagi-sensor-hub-F_Cu.gbr
# kagi-sensor-hub-In1_Cu.gbr
# kagi-sensor-hub-In2_Cu.gbr
# kagi-sensor-hub-B_Cu.gbr
# kagi-sensor-hub-F_SilkS.gbr
# kagi-sensor-hub-B_SilkS.gbr
# kagi-sensor-hub-F_Mask.gbr
# kagi-sensor-hub-B_Mask.gbr
# kagi-sensor-hub-Edge_Cuts.gbr
# kagi-sensor-hub-F_Paste.gbr
# kagi-sensor-hub-B_Paste.gbr
# kagi-sensor-hub.drl

# zipに圧縮
cd hardware/kicad/gerber && zip ../kagi-sensor-hub-gerber.zip *
```

---

## Step 2: BOM + CPLファイル準備

### 2.1 JLCPCB用BOMフォーマット
KiCadのBOMエクスポートを以下の形式に整形する:

```csv
Comment,Designator,Footprint,LCSC Part #
ESP32-S3-MINI-1-N8,U1,MODULE_ESP32-S3-MINI-1,C2913206
SHT45-AD1B-R2,U2,DFN-4_2.5x2.5mm_P1.25mm,C5765842
EKMC1603111,U3,TO-5_D9.9mm,
BH1750FVI-TR,U4,WSOF-6_3x1.6mm,C78960
SGP40-D-R4,U5,DFN-6_2.44x2.44mm,C2688230
INMP441ACEZ-R7,U6,LGA-4_4.72x3.76mm,C2889089
LIS2DH12TR,U7,LGA-16_2x2mm_P0.4mm,C110926
BMP280,U8,LGA-8_2x2.5mm,C83291
AMS1117-3.3,U9,SOT-223,C6186
USBLC6-2SC6,U10,SOT-23-6,C7519
TYPE-C-31-M-12,J1,USB-C_SMD_16P,C165948
B2B-PH-K-S,J2,JST_PH_2.0mm_2P,C131337
CR2032 Holder,BT1,BAT_CR2032_SMD,C75811
WS2812B-2020,D1,LED_2020,C965555
1N5819W,D2,SOD-123,C191023
PTS636,SW1,SW_SMD_3x4x2mm,C2837610
PTS636,SW2,SW_SMD_3x4x2mm,C2837610
10K,R1 R2 R3 R4,0402,C25744
5.1K,R5 R6,0402,C25905
100K,R7 R8,0402,C25741
10uF,C1a C1b,0805,C15850
100nF,C2a C2b C2c C2d C2e C2f C2g C2h,0402,C1525
22uF,C3 C4,0805,C45783
```

**注意**: EKMC1603111 (PIRセンサー) はLCSCに在庫がない場合が多い。
その場合は手動実装 (手はんだ) するか、AM312 (C82857) を代替として使用する。

### 2.2 JLCPCB用CPLフォーマット
KiCadからComponent Placement Listをエクスポート:
```
KiCad PCB Editor → File → Fabrication Outputs → Component Placement (.pos file)
```

CSVに変換し、以下のヘッダーに合わせる:
```csv
Designator,Val,Package,Mid X,Mid Y,Rotation,Layer
U1,ESP32-S3-MINI-1-N8,MODULE,27.50,27.50,0,top
U2,SHT45,DFN-4,10.00,45.00,0,top
...
```

**注意**: JLCPCBではCPLの座標原点が基板左下。KiCadは左上が原点のため、Y座標の変換が必要:
```
JLCPCB_Y = Board_Height - KiCad_Y
```

### 2.3 KiCadプラグインで自動生成 (推奨)
```bash
# JLCPCBプラグインをインストール (KiCad Plugin Manager)
# "Fabrication Toolkit" で検索
# 1クリックでBOM + CPL + Gerberを出力可能
```

---

## Step 3: 発注

### 3.1 JLCPCB発注手順 (推奨)

1. **アカウント作成**: https://jlcpcb.com でアカウント作成
2. **見積もりページ**: https://cart.jlcpcb.com/quote
3. **Gerberアップロード**: zipファイルをドラッグ&ドロップ
4. **基板仕様設定**:
   | 項目 | 設定値 |
   |------|--------|
   | Base Material | FR-4 |
   | Layers | 4 |
   | Dimensions | 55mm x 55mm (自動検出) |
   | PCB Qty | 10 |
   | PCB Thickness | 1.6mm |
   | PCB Color | Black |
   | Surface Finish | LeadFree HASL |
   | Copper Weight | 1oz (outer) / 0.5oz (inner) |
   | Via Covering | Tented |
   | Remove Order Number | Yes (+$1.50) |

5. **SMT Assembly有効化**:
   - 「PCB Assembly」をクリック
   - PCBA Type: Economic
   - Assembly Side: Top Side
   - PCBA Qty: 10
   - BOMファイルをアップロード
   - CPLファイルをアップロード

6. **部品確認**:
   - 在庫あり部品: 自動で緑チェック
   - 在庫切れ部品: 赤表示 → 代替品を検索 or 手動実装に変更
   - Extended Parts (追加料金$3/種類): 一部のセンサーICが該当

7. **確認・決済**:
   - 部品配置プレビューを確認
   - 注文確認 → PayPal or クレジットカードで決済
   - 配送: DHL Express (5-7日, $20前後)

### 3.2 手動実装部品

以下の部品はSMT実装に含めず、受領後に手はんだする:
| 部品 | 理由 | 手はんだ難易度 |
|------|------|--------------|
| EKMC1603111 (PIR) | スルーホール部品、LCSC在庫なし | 簡単 |
| MC-38 (ドアセンサー) | 外部ケーブル接続 | 簡単 |
| CR2032電池 | 組立時に挿入 | 不要 (スナップイン) |

### 3.3 別途購入部品
| 部品 | 購入先 | 数量 | 単価 |
|------|--------|------|------|
| MC-38 ドアセンサー | Amazon/AliExpress | 10 | $1.20 |
| CR2032 電池 | Amazon | 10 | $0.30 |
| USB-Cケーブル (1m) | Amazon | 10 | $1.50 |
| USB充電器 (5V/1A) | Amazon | 10 | $2.00 |

---

## Step 4: 受領 → 組立 → ファームウェア書き込み

### 4.1 受領チェック
1. PCBの外観検査 (はんだブリッジ、欠品、歪み)
2. テスターで3.3V電源ラインのショートチェック (USB-C接続前に)
3. 部品の実装位置確認

### 4.2 手動実装
```
必要な工具:
- はんだごて (温度調節機能付き, 350°C)
- 鉛フリーはんだ (0.6mm径)
- フラックス
- ピンセット
- ルーペ or 顕微鏡

手順:
1. PIRセンサー (U3) のリード線をスルーホールに挿入してはんだ付け
2. JST PHコネクタ (J2) にMC-38のケーブルをはんだ付け
3. CR2032電池ホルダーに電池を挿入
```

### 4.3 ファームウェア書き込み
```bash
# ESP32-S3のファームウェア書き込み (USB-C経由)
# ESP32-S3-MINI-1はUSB-OTG対応のため、直接USB-Cから書き込み可能

# 1. Rust + ESP toolchain インストール
rustup target add riscv32imc-unknown-none-elf
cargo install espup
espup install
source ~/export-esp.sh

# 2. ファームウェアビルド
cd /Users/yuki/workspace/kacha/firmware
cargo build --release --target xtensa-esp32s3-none-elf

# 3. 書き込み
espflash flash --monitor target/xtensa-esp32s3-none-elf/release/kagi-sensor-hub

# 4. 動作確認
# - ステータスLED (WS2812B) が点滅 → 起動OK
# - シリアルモニタでセンサー読み値を確認
# - WiFi APモード (KAGI-SETUP-XXXX) が出現 → プロビジョニング準備OK
```

### 4.4 機能テスト
| テスト項目 | 確認方法 | 合格基準 |
|-----------|---------|---------|
| 電源投入 | USB-C接続 | LED点灯、3.3V出力 |
| WiFi接続 | スマホでAP確認 | KAGI-SETUP-XXXX出現 |
| 温湿度 | シリアルモニタ | 妥当な値 (20-30°C, 30-70%RH) |
| PIR | 手を振る | GPIO割り込み発生 |
| 照度 | ライトを当てる/遮る | 値が変化 |
| VOC | アルコール綿棒を近づける | VOC Index上昇 |
| マイク | 手を叩く | dB値スパイク |
| 加速度 | 基板を傾ける | XYZ値変化 |
| 気圧 | 息を吹きかける | 微小変化 |
| ドアセンサー | 磁石を近づける/離す | GPIO変化 |
| BLE | SwitchBotを近くに置く | アドバタイズ検出 |
| バックアップ電池 | USB-C抜く | 停電通知送信 |

---

## Step 5: コスト概算

### 1台あたりのコスト (10台発注の場合)

| カテゴリ | 内訳 | コスト (USD) |
|---------|------|-------------|
| **PCB製造** | 4層, 55x55mm, 黒, HASL | $4.50 |
| **SMT実装費** | セットアップ + 実装 | $8.00 |
| **部品代 (SMT)** | ESP32 + センサー + 受動部品 | $23.50 |
| **手動実装部品** | PIR + MC-38 + CR2032 | $6.30 |
| **筐体 (3Dプリント)** | PA12, SLS/MJF, 60x60x25mm | $10.00 |
| **配送 (按分)** | DHL Express | $2.00 |
| **USB-Cケーブル+充電器** | 付属品 | $3.50 |
| **合計** | | **$57.80** |

### スケール別コスト
| 数量 | 1台あたり | 合計 | 備考 |
|------|----------|------|------|
| 10台 | $57.80 | $578 | プロトタイプ |
| 50台 | $42.00 | $2,100 | 部品のボリュームディスカウント |
| 100台 | $35.00 | $3,500 | 筐体を射出成形に切替可能 |
| 500台 | $28.00 | $14,000 | 金型費$4,000含む |

### 希望小売価格の目安
- **原価**: $35-58 (数量による)
- **推奨小売価格**: $99-129 (約15,000-20,000円)
- **粗利率**: 50-70%
