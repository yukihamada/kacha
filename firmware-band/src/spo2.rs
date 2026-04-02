//! MAX30102 SpO2・心拍センサードライバー
//!
//! I2C アドレス: 0x57 (固定)
//! 対応機能:
//!   - SpO2（血中酸素飽和度）測定: 赤色(660nm) / IR(880nm) 二波長
//!   - 心拍数測定: IRピーク間隔から算出
//!   - 転倒・異常時アラート通知

use esp_idf_hal::i2c::I2cDriver;

// ==================== レジスタ定義 ====================

/// MAX30102 I2C スレーブアドレス（固定値、変更不可）
pub const MAX30102_ADDR: u8 = 0x57;

// レジスタアドレス
const REG_INTR_STATUS_1: u8 = 0x00;
const REG_INTR_ENABLE_1: u8 = 0x02;
const REG_FIFO_WR_PTR: u8 = 0x04;
const REG_OVF_COUNTER: u8 = 0x05;
const REG_FIFO_RD_PTR: u8 = 0x06;
const REG_FIFO_DATA: u8 = 0x07;
const REG_FIFO_CONFIG: u8 = 0x08;
const REG_MODE_CONFIG: u8 = 0x09;
const REG_SPO2_CONFIG: u8 = 0x0A;
const REG_LED1_PA: u8 = 0x0C; // 赤色LEDパルス振幅
const REG_LED2_PA: u8 = 0x0D; // IR LEDパルス振幅

// ==================== アラート閾値定数 ====================

/// SpO2が この値を下回ると低酸素アラート（単位: %）
/// 94%未満は医療的に要注意域（WHO基準参考）
pub const SPO2_CRITICAL: u8 = 94;

/// 心拍数がこの値を下回ると徐脈アラート（単位: bpm）
pub const HR_LOW: u8 = 40;

/// 心拍数がこの値を超えると頻脈アラート（単位: bpm）
pub const HR_HIGH: u8 = 150;

// IR サンプルバッファサイズ（心拍計算用）
const HR_SAMPLE_BUF: usize = 100;

// ==================== アラート種別 ====================

/// 健康状態アラート列挙型
///
/// BLEノティフィケーションおよびバイブレーションパターンに対応させる:
/// - Normal         → 振動なし
/// - LowSpO2        → 短振動×3
/// - AbnormalHR     → 長振動×1
/// - PossibleCardiac→ 長振動×3 + アプリへ緊急通知
#[derive(Debug, Clone, PartialEq)]
pub enum HealthAlert {
    /// 正常範囲内
    Normal,
    /// SpO2が閾値未満（値: 実測%）
    LowSpO2(u8),
    /// 心拍数が範囲外（値: 実測bpm）
    AbnormalHR(u8),
    /// SpO2低下 + 心拍異常の複合：心臓イベント疑い
    PossibleCardiacEvent,
}

// ==================== ドライバー実装 ====================

/// MAX30102 センサードライバー構造体
pub struct Max30102<'d> {
    i2c: I2cDriver<'d>,
}

impl<'d> Max30102<'d> {
    /// 新規インスタンスを作成し、センサーを初期化する
    ///
    /// # 初期化手順
    /// 1. ソフトリセット（REG_MODE_CONFIG bit6）
    /// 2. SpO2モード設定（MODE=0x02）
    /// 3. サンプリングレート・LED電流設定
    /// 4. FIFO リセット
    pub fn new(i2c: I2cDriver<'d>) -> Result<Self, esp_idf_hal::sys::EspError> {
        let mut sensor = Max30102 { i2c };
        sensor.init()?;
        Ok(sensor)
    }

    /// センサー初期化
    fn init(&mut self) -> Result<(), esp_idf_hal::sys::EspError> {
        // ソフトリセット: MODE_CONFIG の bit6 を 1 にセット
        // リセット完了後 bit6 は自動クリアされる（最大1ms待機）
        self.write_reg(REG_MODE_CONFIG, 0x40)?;
        // リセット完了まで待機（組込み環境では esp_idf_hal::delay::FreeRtos::delay_ms を使う）
        // ここでは簡易ビジーウェイト
        for _ in 0..10_000u32 {}

        // SpO2 モード (MODE[2:0] = 010)
        // 0x02 = SpO2モード（赤色 + IR 両チャンネルを有効化）
        self.write_reg(REG_MODE_CONFIG, 0x02)?;

        // SpO2 コンフィグ: 0x27
        //   SPO2_ADC_RNG[1:0] = 01 → フルスケール 4096nA
        //   SPO2_SR[2:0]      = 001 → 100sps（サンプリングレート）
        //   LEW_PW[1:0]       = 11  → 18bit / パルス幅411μs（最高精度）
        // ※400spsは高速すぎてESP32-C3の処理が追いつかないため100spsを採用
        self.write_reg(REG_SPO2_CONFIG, 0x27)?;

        // LED1（赤色）電流 0x1F = 6.2mA
        // 手首装着のため肌色・毛量差を吸収できる適切な電流値
        self.write_reg(REG_LED1_PA, 0x1F)?;

        // LED2（IR）電流 0x1F = 6.2mA
        self.write_reg(REG_LED2_PA, 0x1F)?;

        // FIFO コンフィグ: SMP_AVE=4サンプル平均、FIFO_ROLLOVER_EN=1
        self.write_reg(REG_FIFO_CONFIG, 0x4F)?;

        // FIFO ポインタをリセット
        self.write_reg(REG_FIFO_WR_PTR, 0x00)?;
        self.write_reg(REG_OVF_COUNTER, 0x00)?;
        self.write_reg(REG_FIFO_RD_PTR, 0x00)?;

        // FIFO_A_FULL 割り込み有効（32サンプル蓄積でINT#アサート）
        self.write_reg(REG_INTR_ENABLE_1, 0xC0)?;

        Ok(())
    }

    // ==================== I2C 読み書きヘルパー ====================

    fn write_reg(&mut self, reg: u8, val: u8) -> Result<(), esp_idf_hal::sys::EspError> {
        let buf = [reg, val];
        self.i2c.write(MAX30102_ADDR, &buf, 100)
    }

    fn read_reg(&mut self, reg: u8) -> Result<u8, esp_idf_hal::sys::EspError> {
        let mut buf = [0u8; 1];
        self.i2c.write_read(MAX30102_ADDR, &[reg], &mut buf, 100)?;
        Ok(buf[0])
    }

    // ==================== FIFO データ読み出し ====================

    /// FIFO から赤色・IR の生データを1サンプル取得する
    ///
    /// MAX30102 の FIFO は1サンプル6バイト（赤色3B + IR3B）
    /// 各チャンネルは18bit精度（上位2bitはゼロ）
    ///
    /// # 戻り値
    /// `(red_raw, ir_raw)` — 赤色LED反射光、IR反射光（0〜262143）
    pub fn read_fifo(&mut self) -> Result<(u32, u32), esp_idf_hal::sys::EspError> {
        let mut buf = [0u8; 6];
        self.i2c.write_read(MAX30102_ADDR, &[REG_FIFO_DATA], &mut buf, 100)?;

        // 各チャンネル: 3バイト → 18bit（上位14bit目まで有効、MSB側から）
        let red = ((buf[0] as u32 & 0x03) << 16) | ((buf[1] as u32) << 8) | (buf[2] as u32);
        let ir  = ((buf[3] as u32 & 0x03) << 16) | ((buf[4] as u32) << 8) | (buf[5] as u32);

        Ok((red, ir))
    }

    /// 割り込みフラグをクリアする（INT# ピン解放）
    pub fn clear_interrupt(&mut self) -> Result<(), esp_idf_hal::sys::EspError> {
        let _ = self.read_reg(REG_INTR_STATUS_1)?;
        Ok(())
    }

    // ==================== SpO2 計算 ====================

    /// 赤色・IR の生データから SpO2(%) を算出する
    ///
    /// # アルゴリズム
    /// 比率 R = (AC_red / DC_red) / (AC_ir / DC_ir)
    ///
    /// 経験式（Maxim Application Note 6595 準拠）:
    ///   SpO2 ≈ -45.060 × R² + 30.354 × R + 94.845
    ///
    /// # 引数
    /// - `red`: 赤色LEDの反射光強度（DC近似値として使用）
    /// - `ir`: IR LEDの反射光強度（DC近似値として使用）
    ///
    /// # 注意
    /// 単一サンプルではノイズが大きい。実用上は複数サンプルで
    /// ローパスフィルタをかけてから本関数に渡すこと。
    pub fn calculate_spo2(red: u32, ir: u32) -> u8 {
        if ir == 0 || red == 0 {
            // センサー未装着またはデータ異常
            return 0;
        }

        // 簡易 AC/DC 分離:
        // ここでは red と ir そのものを DC 成分と見なし、
        // 変動分（AC）をサンプル間差分として扱う近似を使う。
        // より正確な実装では 25〜100サンプルのリングバッファで
        // 高周波成分（脈動）を分離すること。
        let r_red = red as f32;
        let r_ir  = ir  as f32;

        // R 値の計算（赤/IR の比）
        // DC ≈ 平均値、AC ≈ 振幅。ここでは比率のみで近似。
        let ratio = r_red / r_ir;

        // 経験式によるSpO2換算
        let spo2 = -45.060_f32 * ratio * ratio + 30.354_f32 * ratio + 94.845_f32;

        // クランプ: 0〜100% の範囲に収める
        let spo2_clamped = spo2.max(0.0).min(100.0) as u8;
        spo2_clamped
    }

    // ==================== 心拍数計算 ====================

    /// IR サンプル列からピーク間隔を検出し心拍数(bpm)を算出する
    ///
    /// # アルゴリズム（Pan-Tompkins 簡易版）
    /// 1. ピーク検出: 前後サンプルより大きい点をピークとしてカウント
    /// 2. 平均ピーク間隔 × サンプリングレート(100sps) → bpm換算
    ///
    /// # 引数
    /// - `ir_samples`: IR チャンネルのサンプル列（最低25サンプル推奨）
    ///
    /// # 戻り値
    /// 心拍数 (bpm)。検出不能な場合は 0 を返す。
    pub fn calculate_hr(ir_samples: &[u32]) -> u8 {
        const SAMPLE_RATE: u32 = 100; // sps（REG_SPO2_CONFIG に合わせること）
        const MIN_PEAK_DIST: usize = 20; // 最小ピーク間隔: 20サンプル = 300bpm 上限

        if ir_samples.len() < 3 {
            return 0;
        }

        // ピーク位置を収集
        let mut peak_indices: heapless::Vec<usize, 32> = heapless::Vec::new();
        let mut last_peak: usize = 0;

        for i in 1..ir_samples.len() - 1 {
            let prev = ir_samples[i - 1];
            let curr = ir_samples[i];
            let next = ir_samples[i + 1];

            // 局所最大値かつ前回ピークから MIN_PEAK_DIST 以上離れているか
            if curr > prev && curr > next && (i - last_peak) >= MIN_PEAK_DIST {
                let _ = peak_indices.push(i);
                last_peak = i;
            }
        }

        if peak_indices.len() < 2 {
            // ピークが2点未満では算出不能
            return 0;
        }

        // ピーク間隔の平均を計算
        let mut interval_sum: usize = 0;
        let num_intervals = peak_indices.len() - 1;
        for i in 0..num_intervals {
            interval_sum += peak_indices[i + 1] - peak_indices[i];
        }

        let avg_interval = interval_sum / num_intervals;
        if avg_interval == 0 {
            return 0;
        }

        // bpm = SAMPLE_RATE * 60 / avg_interval
        let bpm = (SAMPLE_RATE as usize * 60) / avg_interval;

        // 生理的にありえない値はゼロ返し
        if bpm < HR_LOW as usize || bpm > 250 {
            return 0;
        }

        bpm.min(255) as u8
    }

    // ==================== アラート判定 ====================

    /// SpO2 と心拍数からアラートレベルを判定する
    ///
    /// 優先度: PossibleCardiacEvent > LowSpO2 > AbnormalHR > Normal
    ///
    /// # 使い方（メインループから呼び出す例）
    /// ```ignore
    /// let (red, ir) = sensor.read_fifo()?;
    /// let spo2 = Max30102::calculate_spo2(red, ir);
    /// let hr   = Max30102::calculate_hr(&ir_buf);
    /// match Max30102::evaluate_alert(spo2, hr) {
    ///     HealthAlert::PossibleCardiacEvent => vibrate_sos(),
    ///     HealthAlert::LowSpO2(v) => vibrate_short(3),
    ///     HealthAlert::AbnormalHR(v) => vibrate_long(1),
    ///     HealthAlert::Normal => {}
    /// }
    /// ```
    pub fn evaluate_alert(spo2: u8, hr: u8) -> HealthAlert {
        let spo2_low = spo2 > 0 && spo2 < SPO2_CRITICAL;
        let hr_abnormal = hr > 0 && (hr < HR_LOW || hr > HR_HIGH);

        if spo2_low && hr_abnormal {
            // SpO2低下 + 心拍異常の複合 → 心臓イベント疑いで緊急通知
            HealthAlert::PossibleCardiacEvent
        } else if spo2_low {
            HealthAlert::LowSpO2(spo2)
        } else if hr_abnormal {
            HealthAlert::AbnormalHR(hr)
        } else {
            HealthAlert::Normal
        }
    }
}
