# KAGI — JLCPCB 発注手順

> 3製品 (Lite / Band / Koe) すべてのPCBAを JLCPCB でワンストップ発注する手順。

---

## 1. 必要ファイル一覧

| 製品 | Gerber ZIP | BOM CSV | CPL CSV | 状態 |
|------|-----------|---------|---------|------|
| KAGI Lite | 要KiCad出力 | `manufacturing/jlcpcb/kagi-lite/BOM-JLCPCB.csv` | `manufacturing/jlcpcb/kagi-lite/CPL-JLCPCB.csv` | BOM/CPL✅ Gerber要作成 |
| KAGI Band | 要KiCad出力 | `manufacturing/jlcpcb/kagi-band/BOM-JLCPCB.csv` | `manufacturing/jlcpcb/kagi-band/CPL-JLCPCB.csv` | BOM/CPL✅ Gerber要作成 |
| Koe COIN | 要KiCad出力 | `../koe-device/hardware/jlcpcb/BOM-JLCPCB.csv` | `../koe-device/hardware/jlcpcb/CPL-JLCPCB.csv` | BOM/CPL✅ Gerber要作成 |

---

## 2. KiCad → Gerber 出力手順 (EasyEDA経由が最速)

### Option A: EasyEDA (推奨・最速)

1. https://easyeda.com/editor を開く
2. `File` → `Import` → `KiCad` → `.kicad_sch` を選択
3. PCBエディタに切り替えて自動配置 → 手動調整
4. `Fabrication` → `Generate PCB Fabrication File (Gerber)` → ZIP保存

### Option B: KiCad 7/8 (より精密)

```bash
# KiCadをインストール済みの場合
# PCBエディタで File → Plot → Gerber出力
# Layers: F.Cu, B.Cu, In1.Cu, In2.Cu (4層), F.Mask, B.Mask, F.Silkscreen, Edge.Cuts
# Drill: Generate Drill Files → Excellon format
```

---

## 3. JLCPCB 発注フロー (PCBAフル実装)

### Step 1: PCB仕様

| 項目 | KAGI Lite | KAGI Band | Koe COIN |
|------|-----------|-----------|----------|
| サイズ | 55×55mm | 26×52mm 角丸R3 | 30×40mm |
| 層数 | 4層 | 2層 | 2層 |
| 銅厚 | 1oz | 1oz | 1oz |
| 表面処理 | HASL(無鉛) | HASL(無鉛) | HASL(無鉛) |
| カラー | 白 | 黒 | 白 |
| 数量 | 5枚 (試作) | 5枚 | 5枚 |

### Step 2: JLCPCB アップロード

1. https://jlcpcb.com → **Quote Now**
2. GerberZIPをドラッグ&ドロップ
3. PCB仕様を上表の通り設定
4. **PCB Assembly** を ON
5. PCBA側: `Assemble top side` → `Next`

### Step 3: BOM & CPL アップロード

1. **Add BOM File** → `BOM-JLCPCB.csv` を選択
2. **Add CPL File** → `CPL-JLCPCB.csv` を選択
3. マッチング確認:
   - LCSC Part# が自動マッチングされる
   - マッチしない部品は手動選択
   - `Do not place` に設定するもの: DOOR1(MC-38), SPK1(スピーカー), BT1(電池)
4. `Save BOM & CPL` → `Next`

### Step 4: 最終確認 & 発注

- BOM合計金額を確認
- 未実装部品リストを確認
- 数量: 最小5枚 (PCBA最小ロット)
- 支払い: クレジットカード / PayPal

---

## 4. コスト概算 (5枚ロット)

| 製品 | PCB | 部品 | 実装 | 合計/枚 |
|------|-----|------|------|---------|
| KAGI Lite | ~$2 | ~$11 | ~$8 | **~$21** |
| KAGI Band | ~$2 | ~$8 | ~$6 | **~$16** |
| Koe COIN | ~$2 | ~$13 | ~$8 | **~$23** |

> 量産100枚以上で部品コスト約40%減。

---

## 5. 別途手配が必要なもの

### KAGI Lite
- **LD2410B レーダーモジュール** — AliExpressで発注 (~$2/個)
  - 検索: "LD2410B mmWave radar"
  - URL: AliExpress → LD2410B 35x7mm UART 60GHz
- **MC-38 ドアセンサー** — AliExpress (~$1.2/個)
- **CR2032電池** — 近くのコンビニ or Amazon

### KAGI Band
- **ERM振動モーター** — AliExpress (~$0.3/個)
  - 検索: "ERM vibration motor 10x2.7mm"
- **3.7V LiPoバッテリー** — AliExpress (~$2.5/個)
  - 型番: 402535 (4×25×35mm, 250mAh) ← 超薄型バンド用
  - または 401830 (4×18×30mm, 150mAh) ← 最薄型
- **腕時計バンド** — AliExpress or MUJI (18mm幅)

### Koe COIN
- **8Ω 1510スピーカー** — AliExpress (~$0.5/個)
  - 検索: "1510 8ohm 0.5W micro speaker"
- **3.7V LiPo 802535** — AliExpress (~$2.5/個)

---

## 6. 声も発注したい → ElevenLabs 音声クローン

### 音声アラート生成

```bash
# ElevenLabs API で音声クローン作成
# 1. 録音 (30秒〜1分の音声)
# 2. ElevenLabs → Voice Lab → Add Voice → Instant Voice Clone
# 3. APIで音声生成

curl -X POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id} \
  -H "xi-api-key: $ELEVENLABS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "I am OK. Family has been notified.",
    "model_id": "eleven_multilingual_v2",
    "voice_settings": {"stability": 0.5, "similarity_boost": 0.8}
  }' \
  --output ok_confirm_en.mp3
```

### デバイス内音声ファイル (ESP32-S3 SPIFFS)

| ファイル | 内容 | 長さ |
|---------|------|------|
| `/spiffs/ok.mp3` | "大丈夫です。家族に通知しました。" | 2秒 |
| `/spiffs/alert.mp3` | "安否確認: 3日間応答がありません" | 3秒 |
| `/spiffs/fall.mp3` | "転倒を検知しました。助けを呼んでいます。" | 3秒 |
| `/spiffs/startup.mp3` | "KAGIが起動しました。見守りを開始します。" | 3秒 |
| `/spiffs/battery.mp3` | "電池残量が少なくなっています。" | 2秒 |

### 音声ファイル作成コマンド

```bash
# ディレクトリ準備
mkdir -p /Users/yuki/workspace/kacha/firmware/spiffs/

# ElevenLabs一括生成スクリプト
python3 << 'EOF'
import requests, os

API_KEY = os.environ["ELEVENLABS_API_KEY"]
VOICE_ID = "your_cloned_voice_id"  # ElevenLabs Voice Labで取得

texts = {
    "ok": "大丈夫です。家族に通知しました。",
    "alert": "安否確認: 3日間応答がありません",
    "fall": "転倒を検知しました。助けを呼んでいます。",
    "startup": "KAGIが起動しました。見守りを開始します。",
    "battery": "電池残量が少なくなっています。充電してください。",
}

for name, text in texts.items():
    r = requests.post(
        f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}",
        headers={"xi-api-key": API_KEY, "Content-Type": "application/json"},
        json={"text": text, "model_id": "eleven_multilingual_v2",
              "voice_settings": {"stability": 0.5, "similarity_boost": 0.8}}
    )
    with open(f"firmware/spiffs/{name}.mp3", "wb") as f:
        f.write(r.content)
    print(f"✅ {name}.mp3 ({len(r.content)} bytes)")
EOF
```

### ESP32-S3 への音声ファイル書き込み

```bash
# SPIFFSイメージ作成 & 書き込み
cd /Users/yuki/workspace/kacha/firmware

# mkspiffs でイメージ作成 (サイズはpartitions.csvに合わせる)
# SPIFFS partition: 0x3E0000 (4MB flash の残り)
mkspiffs -c spiffs/ -s 0x3E0000 -b 4096 -p 256 spiffs.bin

# espflash で書き込み
espflash write-bin --chip esp32s3 0x420000 spiffs.bin
```

---

## 7. チェックリスト

### Gerber出力前
- [ ] KiCadでERC (電気ルール確認) → エラーゼロ
- [ ] KiCadでDRC (デザインルール確認) → エラーゼロ
- [ ] 部品フットプリントを全確認
- [ ] シルクが銅箔にオーバーラップしていない

### JLCPCB発注前
- [ ] BOM-JLCPCB.csv の LCSC Part# を全確認
- [ ] CPL-JLCPCB.csv の向きを確認 (特にIC類)
- [ ] `Do not place` リストを確認 (外付け部品)
- [ ] ガーバービューアーで目視確認

### 入荷後
- [ ] ハンダブリッジ目視確認
- [ ] 電源ON前にショートテスト (テスターで3.3V-GND間)
- [ ] 電源ON: 電流計で確認 (正常は~80mA)
- [ ] ファームウェア書き込み: `cargo run --release`
- [ ] BLE接続テスト
- [ ] I'm OKボタン動作確認
