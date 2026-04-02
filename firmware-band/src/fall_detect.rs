// LIS2DH12 転倒検知モジュール
// Free-Fall Detection (FF_THS + FF_DUR) → I2C読み出し → 状態機械
// INT1ピン (GPIO7) はアクティブHIGH、R_INT 10KΩプルアップ済み

use anyhow::Result;
use esp_idf_hal::i2c::I2cDriver;
use log::{info, warn};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const LIS2DH12_ADDR: u8 = 0x18; // SDO/SA0=GND (BOM_BAND.csvと一致)
const WHO_AM_I: u8 = 0x0F;
const WHO_AM_I_VAL: u8 = 0x33;

// レジスタアドレス (LIS2DH12 datasheet Table 18)
const CTRL_REG1: u8 = 0x20; // ODR + 軸有効
const CTRL_REG2: u8 = 0x21; // HPF
const CTRL_REG3: u8 = 0x22; // INT1ルーティング
const CTRL_REG4: u8 = 0x23; // フルスケール±2g, BDU
const CTRL_REG5: u8 = 0x24; // FIFO/LIR
const INT1_CFG: u8 = 0x30;  // INT1設定 (AOI + 軸方向)
const INT1_SRC: u8 = 0x31;  // INT1ステータス読み出し (読むとラッチクリア)
const INT1_THS: u8 = 0x32;  // INT1 閾値 (Free-fall判定レベル)
const INT1_DUR: u8 = 0x33;  // INT1 持続時間 (Free-fall最小継続時間)

/// 転倒イベントの重大度
#[derive(Debug, Clone, Copy)]
pub enum FallSeverity {
    Possible = 1, // Free-fall検知のみ
    Likely = 2,   // Free-fall + 衝撃
    Critical = 3, // Free-fall + 衝撃 + 動き停止
}

/// 転倒イベント
#[derive(Debug, Clone)]
pub struct FallEvent {
    pub severity: FallSeverity,
    pub duration_ms: u32,
}

/// 転倒検知状態機械
#[derive(Debug, Clone, PartialEq)]
enum State {
    Monitoring,
    FreeFallDetected { at: Instant },
    ImpactDetected { at: Instant },
    WaitingForConfirm { at: Instant }, // ユーザーがI'm OKを押すまで
}

pub struct FallDetector {
    i2c: Arc<Mutex<I2cDriver<'static>>>,
    state: State,
}

impl FallDetector {
    pub fn new(i2c: Arc<Mutex<I2cDriver<'static>>>) -> Result<Self> {
        let mut detector = Self {
            i2c,
            state: State::Monitoring,
        };
        detector.init_lis2dh12()?;
        Ok(detector)
    }

    fn write_reg(&self, reg: u8, val: u8) -> Result<()> {
        let mut i2c = self.i2c.lock().map_err(|_| anyhow::anyhow!("I2C lock failed"))?;
        i2c.write(LIS2DH12_ADDR, &[reg, val], 100)?;
        Ok(())
    }

    fn read_reg(&self, reg: u8) -> Result<u8> {
        let mut i2c = self.i2c.lock().map_err(|_| anyhow::anyhow!("I2C lock failed"))?;
        let mut buf = [0u8; 1];
        i2c.write_read(LIS2DH12_ADDR, &[reg], &mut buf, 100)?;
        Ok(buf[0])
    }

    fn init_lis2dh12(&mut self) -> Result<()> {
        // WHO_AM_I確認
        let who = self.read_reg(WHO_AM_I)?;
        if who != WHO_AM_I_VAL {
            return Err(anyhow::anyhow!("LIS2DH12 not found (got 0x{:02X})", who));
        }
        info!("LIS2DH12 検出済み");

        // CTRL_REG1: ODR=25Hz (0x30), LP_EN=0 (Normal mode), XYZ全有効
        // 0x37 = ODR[3:0]=0011(25Hz), LPen=0, Zen=Yen=Xen=1
        self.write_reg(CTRL_REG1, 0x37)?;

        // CTRL_REG2: HPF有効 (INT1用High-Pass filter) FDS=1, HPIS1=1
        // 0x09 = HPM=00(Normal mode), HPCF=00, FDS=1, HPIS2=0, HPIS1=1
        self.write_reg(CTRL_REG2, 0x09)?;

        // CTRL_REG3: INT1にIA1割り込みをルーティング (I1_IA1=1)
        // 0x40 = I1_IA1=1, その他=0
        self.write_reg(CTRL_REG3, 0x40)?;

        // CTRL_REG4: ±2g (FS=00), BDU=1 (連続読み出し保護)
        // 0x80 = BDU=1, BLE=0, FS=00(±2g), HR=0, ST=00, SIM=0
        self.write_reg(CTRL_REG4, 0x80)?;

        // CTRL_REG5: LIR_INT1=1 (INT1ラッチ: INT1_SRC読み出しでクリア)
        // 0x08 = BOOT=0, FIFO_EN=0, -, -, LIR_INT1=1, D4D_INT1=0, LIR_INT2=0, D4D_INT2=0
        self.write_reg(CTRL_REG5, 0x08)?;

        // INT1_THS: Free-fall閾値 = 0x10 (= 16 LSB × 16mg/LSB@±2g = 256mg ≈ 0.25g)
        // Free-fallは全軸合成加速度 < 閾値で検知 (AOI=1モード)
        self.write_reg(INT1_THS, 0x10)?;

        // INT1_DUR: Free-fall持続時間 = 5 (= 5/25Hz = 200ms)
        // 200ms継続してフリーフォール条件を満たした場合のみINT1発火
        self.write_reg(INT1_DUR, 0x05)?;

        // INT1_CFG: Free-fallモード (AOI=1, 6D=0, ZLIE=YLIE=XLIE=1)
        // 0x95 = AOI=1, 6D=0, ZHIE=0, ZLIE=1, YHIE=0, YLIE=1, XHIE=0, XLIE=1
        // AOI=1かつ全軸LOW(XLIE+YLIE+ZLIE): 全軸が閾値以下でAND条件 = Free-fall
        self.write_reg(INT1_CFG, 0x95)?;

        info!("LIS2DH12 初期化完了 (ODR=25Hz, FF閾値=256mg, 持続=200ms)");
        Ok(())
    }

    /// ポーリング: INT1がHIGHのときに呼ぶ
    pub fn poll(&mut self) -> Option<FallEvent> {
        // INT1_SRCを読んでラッチをクリア
        let src = match self.read_reg(INT1_SRC) {
            Ok(v) => v,
            Err(e) => {
                warn!("LIS2DH12 I2C読み出しエラー: {:?}", e);
                return None;
            }
        };

        // IA (Interrupt Active) ビット確認
        if src & 0x40 == 0 {
            return None; // フォールス
        }

        let now = Instant::now();

        match &self.state {
            State::Monitoring => {
                // Free-fall開始
                info!("Free-fall検知 (INT1_SRC=0x{:02X})", src);
                self.state = State::FreeFallDetected { at: now };
                None
            }
            State::FreeFallDetected { at } => {
                // 衝撃確認 (200ms以内)
                let elapsed = at.elapsed();
                if elapsed < Duration::from_millis(500) {
                    info!("衝撃確認 ({:?}後)", elapsed);
                    self.state = State::ImpactDetected { at: now };
                } else {
                    // タイムアウト → キャンセル
                    self.state = State::Monitoring;
                }
                None
            }
            State::ImpactDetected { at } => {
                let elapsed = at.elapsed();
                let severity = if elapsed.as_secs() > 5 {
                    FallSeverity::Critical // 5秒以上動かない
                } else {
                    FallSeverity::Likely
                };
                info!("転倒確定: severity={:?}", severity);
                self.state = State::WaitingForConfirm { at: now };
                Some(FallEvent {
                    severity,
                    duration_ms: elapsed.as_millis() as u32,
                })
            }
            State::WaitingForConfirm { at } => {
                // 10秒後にリセット (I'm OKボタンが押されなかった)
                if at.elapsed() > Duration::from_secs(10) {
                    self.state = State::Monitoring;
                }
                None
            }
        }
    }

    /// I'm OKボタンが押されたときに呼ぶ (アラートキャンセル)
    pub fn cancel_alert(&mut self) {
        if matches!(self.state, State::WaitingForConfirm { .. }) {
            info!("転倒アラートキャンセル (I'm OK)");
            self.state = State::Monitoring;
        }
    }
}
