// 振動モーターPWM制御 (GPIO1, LEDC)
// ERM (Eccentric Rotating Mass) モーター
// MOSFET gate経由でPWM制御 → デューティ比で強度調整

use anyhow::Result;
use esp_idf_hal::ledc::{LedcDriver, LedcTimerDriver, config::TimerConfig, Resolution};
use esp_idf_hal::prelude::*;
use log::info;
use std::thread;
use std::time::Duration;

/// 振動パターン定義
#[derive(Debug, Clone, Copy)]
pub enum VibPattern {
    /// I'm OK確認 (短い1回 150ms)
    OkConfirm,
    /// Tier1アラート (強い3回)
    Tier1Alert,
    /// 転倒検知 (緊急3回強)
    FallDetected,
    /// ペアリング完了 (2回弱)
    PairingComplete,
    /// バッテリー低下警告 (弱い2回)
    LowBattery,
    /// カスタム (duty%, on_ms, off_ms, repeat)
    Custom { duty: u8, on_ms: u32, off_ms: u32, repeat: u8 },
}

pub struct Vibrator {
    driver: LedcDriver<'static>,
    max_duty: u32,
}

impl Vibrator {
    pub fn new(
        timer0: impl esp_idf_hal::ledc::LedcTimer + 'static,
        channel0: impl esp_idf_hal::ledc::LedcChannel + 'static,
        pin: esp_idf_hal::gpio::Gpio1,
    ) -> Result<Self> {
        let timer_config = TimerConfig::default()
            .frequency(1.kHz().into())
            .resolution(Resolution::Bits8);
        // Box::leak → ファームウェアは終了しないため意図的な'static昇格
        let timer: &'static LedcTimerDriver<'static> =
            Box::leak(Box::new(LedcTimerDriver::new(timer0, &timer_config)?));
        let driver = LedcDriver::new(channel0, timer, pin)?;
        let max_duty = driver.get_max_duty();
        Ok(Self { driver, max_duty })
    }

    /// パターン実行
    pub fn execute(&mut self, pattern: VibPattern) -> Result<()> {
        match pattern {
            VibPattern::OkConfirm => {
                self.pulse(80, 150, 0, 1)?;
            }
            VibPattern::Tier1Alert => {
                self.pulse(100, 300, 200, 3)?;
            }
            VibPattern::FallDetected => {
                // 強い3回バースト
                self.pulse(100, 400, 150, 3)?;
            }
            VibPattern::PairingComplete => {
                self.pulse(60, 100, 100, 2)?;
            }
            VibPattern::LowBattery => {
                self.pulse(30, 80, 200, 2)?;
            }
            VibPattern::Custom { duty, on_ms, off_ms, repeat } => {
                self.pulse(duty, on_ms, off_ms, repeat)?;
            }
        }
        Ok(())
    }

    /// duty%でon_ms振動、off_ms停止、repeat回繰り返し
    fn pulse(&mut self, duty_pct: u8, on_ms: u32, off_ms: u32, repeat: u8) -> Result<()> {
        let duty = (self.max_duty as u64 * duty_pct as u64 / 100) as u32;
        for i in 0..repeat {
            self.driver.set_duty(duty)?;
            thread::sleep(Duration::from_millis(on_ms as u64));
            self.driver.set_duty(0)?;
            if i < repeat - 1 && off_ms > 0 {
                thread::sleep(Duration::from_millis(off_ms as u64));
            }
        }
        Ok(())
    }

    /// 停止
    pub fn stop(&mut self) -> Result<()> {
        self.driver.set_duty(0)?;
        Ok(())
    }
}
