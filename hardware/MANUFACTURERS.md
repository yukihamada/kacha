# KAGI Sensor Hub - 製造パートナーガイド

## 1. JLCPCB (中国・深圳) - 推奨

- **URL**: https://jlcpcb.com
- **特徴**: PCB製造 + SMT実装の一括発注が可能。価格が最も安い
- **SMT Assembly**: Economic PCBA (部品をJLCPCBの在庫から自動実装)
- **最小ロット**: PCB 5枚〜 / SMT 2枚〜
- **リードタイム**: PCB 2-3日 + SMT 3-5日 + 配送 5-7日 = 合計約10-15日
- **品質**: ISO 9001, UL認証
- **支払い**: クレジットカード, PayPal

### 必要ファイル一覧
| ファイル | 形式 | 説明 |
|---------|------|------|
| Gerber files | .zip (RS-274X) | KiCadから「プロット」→ Gerber出力 |
| Drill files | .drl (Excellon) | KiCadから「ドリルファイル」出力 |
| BOM | .csv | LCSC Part#, Designation, Footprint, Quantity |
| CPL (Component Placement List) | .csv | Designator, Mid X, Mid Y, Rotation, Layer |

### BOMフォーマット (JLCPCB用)
```csv
Comment,Designator,Footprint,LCSC Part #
ESP32-S3-MINI-1-N8,U1,ESP32-S3-MINI,C2913206
SHT45-AD1B-R2,U2,DFN-4_2.5x2.5mm,C5765842
...
```

### CPLフォーマット (JLCPCB用)
```csv
Designator,Mid X,Mid Y,Rotation,Layer
U1,27.5,27.5,0,top
U2,10.0,40.0,0,top
...
```

### 発注手順
1. https://cart.jlcpcb.com/quote にアクセス
2. 「Add Gerber File」でGerber zipをアップロード
3. 基板仕様を選択:
   - Layers: 4
   - PCB Thickness: 1.6mm
   - Surface Finish: HASL(有鉛) or LeadFree HASL
   - PCB Color: 黒 (KAGIブランドカラー推奨)
4. 「SMT Assembly」をON
   - Assembly Side: Top Side
   - BOMとCPLファイルをアップロード
5. 部品の在庫確認 → 在庫切れ部品は手動実装 or 代替品選択
6. カートに追加 → 決済

### コスト概算 (10台の場合)
| 項目 | 単価 | 備考 |
|------|------|------|
| PCB (4層, 55x55mm) | $4.50/枚 | 10枚で$45 |
| SMT実装費 | $8.00/枚 | セットアップ$8 + 部品単価 |
| 部品代 | $25.00/枚 | BOM合計 |
| 配送 (DHL) | $20.00 | 全体 |
| **合計** | **約$37.50/台** | 10台合計 $375 |

---

## 2. PCBWay (中国・深圳)

- **URL**: https://pcbway.com
- **特徴**: 高品質PCB + フレキシブル基板にも対応。日本語サポートあり
- **SMT Assembly**: Turnkey (部品調達込み) or Kitted (部品支給)
- **最小ロット**: PCB 5枚〜 / SMT 5枚〜
- **リードタイム**: PCB 3-5日 + SMT 5-7日 + 配送 5-7日 = 合計約13-19日
- **品質**: IPC Class 2/3, ISO 9001, IATF 16949
- **支払い**: クレジットカード, PayPal, 銀行振込

### 必要ファイル一覧
| ファイル | 形式 | 説明 |
|---------|------|------|
| Gerber files | .zip (RS-274X) | JLCPCBと同じ |
| BOM | .xlsx or .csv | Qty, Description, Designator, MPN, Package |
| Pick and Place | .csv | Ref, PosX, PosY, Rot, Side |
| Assembly Drawing | .pdf | 部品配置図 (KiCadの3Dビューからエクスポート) |

### 発注手順
1. https://www.pcbway.com/orderonline.aspx にアクセス
2. Gerberファイルをアップロード
3. 基板仕様を選択 (JLCPCBと同様)
4. 「PCB Assembly」をクリック
5. Assembly Type: Turnkey (推奨)
6. BOM + Pick and Place をアップロード
7. エンジニアレビュー (1-2営業日) → 見積もり確認
8. 決済 → 製造開始

### コスト概算 (10台の場合)
| 項目 | 単価 | 備考 |
|------|------|------|
| PCB (4層, 55x55mm) | $5.00/枚 | 10枚 |
| SMT実装費 | $12.00/枚 | Turnkey |
| 部品代 | $25.00/枚 | BOM合計 |
| 配送 (DHL) | $25.00 | 全体 |
| **合計** | **約$42.00/台** | 10台合計 $420 |

### JLCPCBとの比較
- **価格**: JLCPCBの方が10-20%安い
- **品質**: PCBWayの方がIPC Class 3対応で高品質
- **サポート**: PCBWayは日本語対応あり、エンジニアレビューが丁寧
- **推奨**: プロトタイプ → JLCPCB、量産 → PCBWay

---

## 3. 日本の製造パートナー

### 3a. P板.com (ピーバンドットコム)

- **URL**: https://www.p-ban.com
- **特徴**: 日本語完全対応。高品質。技適関連の相談可能
- **SMT Assembly**: あり (別途見積もり)
- **最小ロット**: 1枚〜
- **リードタイム**: PCB 3-5営業日 (国内配送含む)
- **品質**: JIS規格準拠
- **支払い**: 銀行振込, クレジットカード

**発注ファイル**: Gerber (RS-274X) + ドリル (Excellon)
**注意**: SMT実装は別途見積もり。部品は別途手配が必要な場合あり

### 3b. Elecrow (中国・深圳、日本語サポートあり)

- **URL**: https://www.elecrow.com
- **特徴**: PCB + SMT + 3Dプリント + レーザーカットの一括発注可能
- **最小ロット**: 5枚〜
- **リードタイム**: PCB 5-7日 + 配送 5-7日
- **支払い**: PayPal, クレジットカード

**筐体も同時発注可能** → PCB + 3Dプリント筐体をまとめて発注できるメリット

### 3c. スイッチサイエンス (日本・東京)

- **URL**: https://www.switch-science.com
- **特徴**: 製造というより販売プラットフォーム。完成品の委託販売に最適
- **PCBA製造**: 直接の製造受託は行っていないが、OEM相談可能
- **用途**: 完成品の日本国内販売チャネル

### 日本での製造を選ぶケース
- 技適認証のサポートが必要な場合 (ESP32-S3-MINI-1は認証済みなので通常不要)
- 日本国内での短納期が必要な場合
- 品質保証を日本の規格で行いたい場合

---

## 4. 推奨製造フロー

### プロトタイプ (1-10台)
```
KiCad設計 → JLCPCB (PCB + SMT) → 3Dプリント筐体 (JLCPCB or Elecrow)
                                 → MC-38ドアセンサーは別途購入
                                 → ファームウェア書き込み (USB-C経由)
```

### 小ロット量産 (10-100台)
```
KiCad設計確定 → PCBWay (Turnkey Assembly) → 3Dプリント筐体 (MJF/SLS)
                                           → 個別部品購入 (MC-38等)
                                           → 組立 + テスト + ファームウェア
```

### 量産 (100台以上)
```
設計確定 → 射出成形金型発注 → PCBWay or JLCPCB (量産Assembly)
                             → 筐体射出成形
                             → 組立ライン構築
                             → QCテスト → 出荷
```

---

## 5. 技適に関する注意

ESP32-S3-MINI-1 (Espressif) は技適認証済み (認証番号: 201-220017)。
モジュールをそのまま使用し、アンテナパターンを変更しない限り、
追加の技適認証は不要。

ただし以下の場合は再認証が必要:
- 外部アンテナを追加する場合
- モジュールのRF回路を改造する場合
- シールドを追加してRF特性が変わる場合
