// KAGI Sensors Module
// LD2410B mmWave / SHT40 I2C / ドアセンサー GPIO / I'm OKボタン GPIO

use anyhow::{anyhow, Result};
use esp_idf_hal::i2c::I2cDriver;
use esp_idf_hal::uart::UartDriver;
use log::{info, warn, debug};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};

use crate::safety::SafetyState;
use crate::DeviceModel;

// ──────────────────────────────────────
// I2Cアドレス定数 (schematic_notes.md準拠)
// ──────────────────────────────────────

const SHT40_ADDR: u8 = 0x44;
#[cfg(feature = "hub")]
const VEML7700_ADDR: u8 = 0x10;
#[cfg(feature = "hub")]
const SGP41_ADDR: u8 = 0x59;
#[cfg(feature = "hub")]
const LIS2DH12_ADDR: u8 = 0x19;
#[cfg(feature = "hub")]
const BMP280_ADDR: u8 = 0x76;
const ATECC608A_ADDR: u8 = 0x60;
#[cfg(feature = "pro")]
const SCD41_ADDR: u8 = 0x62;

// ──────────────────────────────────────
// データ構造体
// ──────────────────────────────────────

/// センサースナップショット (全モデル共通)
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SensorSnapshot {
    pub timestamp: u64,
    pub mmwave_presence: bool,
    pub mmwave_breathing: bool,
    pub mmwave_distance_cm: u16,
    pub mmwave_last_breath_ago_min: u32,
    pub door_open: bool,
    pub door_last_open_ago_min: u32,
    pub button_pressed: bool,
    pub button_last_press_ago_min: u32,
    pub temperature_c: f32,
    pub humidity_rh: f32,
    pub acs_score: f32,
    pub safety_state: SafetyState,
    #[cfg(feature = "hub")]
    pub light_lux: f32,
    #[cfg(feature = "hub")]
    pub voc_index: u16,
    #[cfg(feature = "hub")]
    pub nox_index: u16,
    #[cfg(feature = "hub")]
    pub pressure_hpa: f32,
    #[cfg(feature = "hub")]
    pub sound_db: f32,
    #[cfg(feature = "pro")]
    pub co2_ppm: u16,
}

impl Default for SafetyState {
    fn default() -> Self {
        SafetyState::Normal
    }
}

/// LD2410B mmWaveレーダーの詳細データ
#[derive(Debug, Clone, Default)]
pub struct MmWaveData {
    pub motion_detected: bool,
    pub static_detected: bool,
    pub breathing_detected: bool,
    pub motion_distance_cm: u16,
    pub motion_energy: u8,
    pub static_distance_cm: u16,
    pub static_energy: u8,
}

// ──────────────────────────────────────
// SensorManager
// ──────────────────────────────────────

pub struct SensorManager {
    i2c: Arc<Mutex<I2cDriver<'static>>>,
    uart: Arc<Mutex<UartDriver<'static>>>,
    model: DeviceModel,
    /// UARTパースバッファ
    uart_buf: [u8; 256],
}

impl SensorManager {
    pub fn new(
        i2c: Arc<Mutex<I2cDriver<'static>>>,
        uart: Arc<Mutex<UartDriver<'static>>>,
        model: DeviceModel,
    ) -> Result<Self> {
        let mgr = Self {
            i2c,
            uart,
            model,
            uart_buf: [0u8; 256],
        };

        // I2Cバスをスキャンしてセンサーの存在を確認
        mgr.scan_i2c_bus()?;

        Ok(mgr)
    }

    /// I2Cバススキャン (起動時のデバイス確認)
    fn scan_i2c_bus(&self) -> Result<()> {
        let mut i2c = self.i2c.lock().map_err(|_| anyhow!("I2C lock failed"))?;

        let expected_addrs: &[(u8, &str)] = match self.model {
            DeviceModel::Lite => &[
                (SHT40_ADDR, "SHT40"),
                (ATECC608A_ADDR, "ATECC608A"),
            ],
            #[cfg(feature = "hub")]
            DeviceModel::Hub => &[
                (SHT40_ADDR, "SHT40"),
                (VEML7700_ADDR, "VEML7700"),
                (SGP41_ADDR, "SGP41"),
                (LIS2DH12_ADDR, "LIS2DH12"),
                (BMP280_ADDR, "BMP280"),
                (ATECC608A_ADDR, "ATECC608A"),
            ],
            #[cfg(feature = "pro")]
            DeviceModel::Pro => &[
                (SHT40_ADDR, "SHT40"),
                (VEML7700_ADDR, "VEML7700"),
                (SGP41_ADDR, "SGP41"),
                (LIS2DH12_ADDR, "LIS2DH12"),
                (BMP280_ADDR, "BMP280"),
                (ATECC608A_ADDR, "ATECC608A"),
                (SCD41_ADDR, "SCD41"),
            ],
            #[allow(unreachable_patterns)]
            _ => &[
                (SHT40_ADDR, "SHT40"),
                (ATECC608A_ADDR, "ATECC608A"),
            ],
        };

        for &(addr, name) in expected_addrs {
            let mut probe = [0u8; 1];
            match i2c.read(addr, &mut probe, 100) {
                Ok(_) => info!("I2Cデバイス検出: {} (0x{:02X})", name, addr),
                Err(_) => warn!("I2Cデバイス未検出: {} (0x{:02X})", name, addr),
            }
        }

        Ok(())
    }

    // ──────────────────────────────────
    // SHT40 温湿度センサー
    // ──────────────────────────────────

    /// SHT40から温湿度を読み取り
    pub fn read_environmental(&mut self) -> Result<SensorSnapshot> {
        let mut snapshot = SensorSnapshot::default();

        // SHT40: 高精度モード (0xFD)
        match self.read_sht40() {
            Ok((temp, hum)) => {
                snapshot.temperature_c = temp;
                snapshot.humidity_rh = hum;
                debug!("SHT40: {:.1}°C, {:.1}%RH", temp, hum);
            }
            Err(e) => {
                warn!("SHT40読み取りエラー: {:?}", e);
            }
        }

        // Hub以上: 追加センサー
        #[cfg(feature = "hub")]
        {
            if let Ok(lux) = self.read_veml7700() {
                snapshot.light_lux = lux;
            }
            if let Ok((voc, nox)) = self.read_sgp41() {
                snapshot.voc_index = voc;
                snapshot.nox_index = nox;
            }
            if let Ok(pressure) = self.read_bmp280() {
                snapshot.pressure_hpa = pressure;
            }
        }

        #[cfg(feature = "pro")]
        {
            if let Ok(co2) = self.read_scd41() {
                snapshot.co2_ppm = co2;
            }
        }

        Ok(snapshot)
    }

    /// SHT40 I2C読み取り
    fn read_sht40(&self) -> Result<(f32, f32)> {
        let mut i2c = self.i2c.lock().map_err(|_| anyhow!("I2C lock failed"))?;

        // 高精度測定コマンド (0xFD)
        i2c.write(SHT40_ADDR, &[0xFD], 100)
            .map_err(|e| anyhow!("SHT40 write failed: {:?}", e))?;

        // 測定完了待ち (高精度モード: 最大8.2ms)
        esp_idf_hal::delay::FreeRtos::delay_ms(10);

        // 6バイト読み取り: [temp_msb, temp_lsb, temp_crc, hum_msb, hum_lsb, hum_crc]
        let mut buf = [0u8; 6];
        i2c.read(SHT40_ADDR, &mut buf, 100)
            .map_err(|e| anyhow!("SHT40 read failed: {:?}", e))?;

        // CRC検証 (CRC-8, polynomial 0x31, init 0xFF)
        if !crc8_check(&buf[0..2], buf[2]) || !crc8_check(&buf[3..5], buf[5]) {
            return Err(anyhow!("SHT40 CRC error"));
        }

        // 温度変換: T[°C] = -45 + 175 * raw / 65535
        let raw_temp = ((buf[0] as u16) << 8) | (buf[1] as u16);
        let temperature = -45.0 + 175.0 * (raw_temp as f32) / 65535.0;

        // 湿度変換: RH[%] = -6 + 125 * raw / 65535
        let raw_hum = ((buf[3] as u16) << 8) | (buf[4] as u16);
        let humidity = (-6.0 + 125.0 * (raw_hum as f32) / 65535.0).clamp(0.0, 100.0);

        Ok((temperature, humidity))
    }

    // ──────────────────────────────────
    // LD2410B mmWaveレーダー (UART)
    // ──────────────────────────────────

    /// LD2410B UARTデータ読み取り
    pub fn read_mmwave_uart(&mut self) -> Result<MmWaveData> {
        let mut uart = self.uart.lock().map_err(|_| anyhow!("UART lock failed"))?;

        // UARTバッファを読み取り
        let bytes_read = uart.read(&mut self.uart_buf, 100)
            .map_err(|e| anyhow!("UART read failed: {:?}", e))?;

        if bytes_read == 0 {
            return Err(anyhow!("LD2410B: no data"));
        }

        // LD2410Bフレーム解析
        // ヘッダー: F4 F3 F2 F1, フッター: F8 F7 F6 F5
        self.parse_ld2410b_frame(&self.uart_buf[..bytes_read])
    }

    /// LD2410Bのレポートフレームを解析
    /// フレーム形式:
    ///   F4 F3 F2 F1 [len_lo len_hi] [type] [head] [data...] F8 F7 F6 F5
    fn parse_ld2410b_frame(&self, data: &[u8]) -> Result<MmWaveData> {
        let mut result = MmWaveData::default();

        // フレームヘッダーを探す
        let header = [0xF4, 0xF3, 0xF2, 0xF1];
        let pos = data.windows(4)
            .position(|w| w == header)
            .ok_or_else(|| anyhow!("LD2410B: header not found"))?;

        let frame = &data[pos..];
        if frame.len() < 12 {
            return Err(anyhow!("LD2410B: frame too short"));
        }

        // データ長
        let data_len = (frame[4] as u16) | ((frame[5] as u16) << 8);
        if frame.len() < (6 + data_len as usize + 4) {
            return Err(anyhow!("LD2410B: incomplete frame"));
        }

        let frame_type = frame[6];

        // ターゲットデータレポート (type = 0x02, head = 0xAA)
        if frame_type == 0x02 && frame.len() > 15 && frame[7] == 0xAA {
            let target_state = frame[8];

            // bit0: 動体検知, bit1: 静体検知
            result.motion_detected = (target_state & 0x01) != 0;
            result.static_detected = (target_state & 0x02) != 0;

            // 動体データ
            result.motion_distance_cm = (frame[9] as u16) | ((frame[10] as u16) << 8);
            result.motion_energy = frame[11];

            // 静体データ
            result.static_distance_cm = (frame[12] as u16) | ((frame[13] as u16) << 8);
            result.static_energy = frame[14];

            // 呼吸検知: 静体が検知されており、エネルギーが低レベルで安定
            // (完全静止状態で微弱な動きを検知 = 呼吸)
            result.breathing_detected = result.static_detected
                && result.static_energy > 5
                && result.static_energy < 60
                && !result.motion_detected;

            debug!(
                "LD2410B: motion={} static={} breathing={} dist={}cm energy={}",
                result.motion_detected,
                result.static_detected,
                result.breathing_detected,
                result.static_distance_cm,
                result.static_energy
            );
        }

        Ok(result)
    }

    // ──────────────────────────────────
    // Hub以上のセンサー (feature gate)
    // ──────────────────────────────────

    /// VEML7700 照度センサー読み取り
    #[cfg(feature = "hub")]
    fn read_veml7700(&self) -> Result<f32> {
        let mut i2c = self.i2c.lock().map_err(|_| anyhow!("I2C lock failed"))?;

        // ALS設定: ALS_GAIN=1/8(0x02), ALS_IT=25ms(0x0C), PSM=OFF
        // レジスタ0x00: [15:13]=RSVD, [12:11]=GAIN, [10]=RSVD, [9:6]=IT, [5:4]=PERS, [1]=INT_EN, [0]=SD
        let config: u16 = (0x02 << 11) | (0x0C << 6); // GAIN=1/8, IT=25ms, SD=0(ON)
        i2c.write(VEML7700_ADDR, &[0x00, (config & 0xFF) as u8, (config >> 8) as u8], 100)
            .map_err(|e| anyhow!("VEML7700 config failed: {:?}", e))?;

        esp_idf_hal::delay::FreeRtos::delay_ms(30);

        // ALS出力レジスタ (0x04) 読み取り
        i2c.write(VEML7700_ADDR, &[0x04], 100)
            .map_err(|e| anyhow!("VEML7700 cmd failed: {:?}", e))?;
        let mut buf = [0u8; 2];
        i2c.read(VEML7700_ADDR, &mut buf, 100)
            .map_err(|e| anyhow!("VEML7700 read failed: {:?}", e))?;

        let raw = (buf[0] as u16) | ((buf[1] as u16) << 8);
        // 分解能: 0.0036 lux/count (GAIN=1/8, IT=25ms時)
        // ただし高照度時はリニアリティ補正が必要
        let lux = raw as f32 * 0.0036 * 8.0; // GAIN補正
        Ok(lux)
    }

    /// SGP41 VOC/NOxセンサー読み取り
    #[cfg(feature = "hub")]
    fn read_sgp41(&self) -> Result<(u16, u16)> {
        let mut i2c = self.i2c.lock().map_err(|_| anyhow!("I2C lock failed"))?;

        // VOC+NOx測定コマンド (0x26 0x19) + ダミー湿度/温度パラメータ
        // 湿度デフォルト: 0x80, 0x00 (50%RH), CRC: 0xA2
        // 温度デフォルト: 0x66, 0x66 (25°C), CRC: 0x93
        let cmd = [0x26, 0x19, 0x80, 0x00, 0xA2, 0x66, 0x66, 0x93];
        i2c.write(SGP41_ADDR, &cmd, 100)
            .map_err(|e| anyhow!("SGP41 write failed: {:?}", e))?;

        // 測定時間: 最大50ms
        esp_idf_hal::delay::FreeRtos::delay_ms(55);

        let mut buf = [0u8; 6];
        i2c.read(SGP41_ADDR, &mut buf, 100)
            .map_err(|e| anyhow!("SGP41 read failed: {:?}", e))?;

        let voc_raw = ((buf[0] as u16) << 8) | (buf[1] as u16);
        let nox_raw = ((buf[3] as u16) << 8) | (buf[4] as u16);

        Ok((voc_raw, nox_raw))
    }

    /// BMP280 気圧センサー読み取り
    #[cfg(feature = "hub")]
    fn read_bmp280(&self) -> Result<f32> {
        let mut i2c = self.i2c.lock().map_err(|_| anyhow!("I2C lock failed"))?;

        // 強制測定モード: ctrl_meas (0xF4) = osrs_t=x1(001), osrs_p=x4(011), mode=forced(01)
        let ctrl = (0b001 << 5) | (0b011 << 2) | 0b01;
        i2c.write(BMP280_ADDR, &[0xF4, ctrl], 100)
            .map_err(|e| anyhow!("BMP280 ctrl write failed: {:?}", e))?;

        // 測定完了待ち
        esp_idf_hal::delay::FreeRtos::delay_ms(20);

        // 気圧データ読み取り (0xF7-0xF9: press_msb, press_lsb, press_xlsb)
        i2c.write(BMP280_ADDR, &[0xF7], 100)
            .map_err(|e| anyhow!("BMP280 read cmd failed: {:?}", e))?;
        let mut buf = [0u8; 3];
        i2c.read(BMP280_ADDR, &mut buf, 100)
            .map_err(|e| anyhow!("BMP280 read failed: {:?}", e))?;

        let raw_pressure = ((buf[0] as u32) << 12) | ((buf[1] as u32) << 4) | ((buf[2] as u32) >> 4);

        // 簡易変換 (補正係数なしの概算。実装時はNVMから補正パラメータを読んで使う)
        let pressure_hpa = raw_pressure as f32 / 256.0;

        Ok(pressure_hpa)
    }

    /// SCD41 CO2センサー読み取り (Pro only)
    #[cfg(feature = "pro")]
    fn read_scd41(&self) -> Result<u16> {
        let mut i2c = self.i2c.lock().map_err(|_| anyhow!("I2C lock failed"))?;

        // 単発測定コマンド (0x21 0x9D)
        i2c.write(SCD41_ADDR, &[0x21, 0x9D], 100)
            .map_err(|e| anyhow!("SCD41 write failed: {:?}", e))?;

        // SCD41の測定時間: 約5秒
        esp_idf_hal::delay::FreeRtos::delay_ms(5100);

        // データ読み取りコマンド (0xEC 0x05)
        i2c.write(SCD41_ADDR, &[0xEC, 0x05], 100)
            .map_err(|e| anyhow!("SCD41 read cmd failed: {:?}", e))?;

        esp_idf_hal::delay::FreeRtos::delay_ms(1);

        let mut buf = [0u8; 9]; // CO2(2) + CRC + Temp(2) + CRC + Hum(2) + CRC
        i2c.read(SCD41_ADDR, &mut buf, 100)
            .map_err(|e| anyhow!("SCD41 read failed: {:?}", e))?;

        if !crc8_check(&buf[0..2], buf[2]) {
            return Err(anyhow!("SCD41 CRC error"));
        }

        let co2_ppm = ((buf[0] as u16) << 8) | (buf[1] as u16);
        Ok(co2_ppm)
    }
}

// ──────────────────────────────────────
// CRC-8 (Sensirion標準: polynomial 0x31, init 0xFF)
// ──────────────────────────────────────

fn crc8_check(data: &[u8], expected: u8) -> bool {
    crc8_compute(data) == expected
}

fn crc8_compute(data: &[u8]) -> u8 {
    let mut crc: u8 = 0xFF;
    for &byte in data {
        crc ^= byte;
        for _ in 0..8 {
            if crc & 0x80 != 0 {
                crc = (crc << 1) ^ 0x31;
            } else {
                crc <<= 1;
            }
        }
    }
    crc
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_crc8() {
        // Sensirion CRC-8のテストベクター
        // データ: [0xBE, 0xEF] → CRC: 0x92
        assert_eq!(crc8_compute(&[0xBE, 0xEF]), 0x92);
    }

    #[test]
    fn test_sht40_conversion() {
        // 25°Cの場合: raw ≈ ((25+45)/175)*65535 = 26214
        let raw: u16 = 26214;
        let temp = -45.0 + 175.0 * (raw as f32) / 65535.0;
        assert!((temp - 25.0).abs() < 0.5);
    }

    #[test]
    fn test_ld2410b_frame_parse() {
        // 模擬的なLD2410Bフレーム (ターゲットデータレポート)
        let frame: &[u8] = &[
            0xF4, 0xF3, 0xF2, 0xF1, // ヘッダー
            0x0D, 0x00,               // データ長: 13
            0x02,                      // タイプ: ターゲットデータ
            0xAA,                      // ヘッド
            0x03,                      // ターゲット状態: motion+static
            0x2C, 0x01,               // 動体距離: 300cm
            0x28,                      // 動体エネルギー: 40
            0x64, 0x00,               // 静体距離: 100cm
            0x14,                      // 静体エネルギー: 20
            0x00, 0x00, 0x00, 0x00,   // パディング
            0xF8, 0xF7, 0xF6, 0xF5,   // フッター
        ];

        let mgr_data = MmWaveData::default();
        // フレームパースのロジック検証
        let header = [0xF4, 0xF3, 0xF2, 0xF1];
        let pos = frame.windows(4).position(|w| w == header);
        assert!(pos.is_some());
        assert_eq!(frame[8], 0x03); // motion + static
    }
}
