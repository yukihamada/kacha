// KAGI Storage Module
// NVS設定保存 / 監査ログバッファ / 生活リズムデータ永続化

use anyhow::{anyhow, Result};
use esp_idf_svc::nvs::{EspDefaultNvsPartition, EspNvs, NvsDefault};
use log::{info, warn, debug};
use serde::{Deserialize, Serialize};

use crate::safety::{DailyPattern, SafetyConfig};
use crate::sensors::SensorSnapshot;

// ──────────────────────────────────────
// NVS キー定数
// ──────────────────────────────────────

const NVS_NAMESPACE: &str = "kagi";
const KEY_SAFETY_CONFIG: &str = "safety_cfg";
const KEY_RHYTHM_DATA: &str = "rhythm";
const KEY_DEVICE_ID: &str = "device_id";
const KEY_WIFI_SSID: &str = "wifi_ssid";
const KEY_WIFI_PASS: &str = "wifi_pass";
const KEY_LOG_HEAD: &str = "log_head";
const KEY_LOG_TAIL: &str = "log_tail";
const KEY_LOG_PREFIX: &str = "log_";

/// リングバッファの最大エントリ数
const MAX_LOG_ENTRIES: u32 = 100;

// ──────────────────────────────────────
// StorageManager
// ──────────────────────────────────────

pub struct StorageManager {
    nvs: EspNvs<NvsDefault>,
    /// リングバッファの書き込み位置
    log_head: u32,
    /// リングバッファの読み取り位置
    log_tail: u32,
}

impl StorageManager {
    pub fn new(partition: EspDefaultNvsPartition) -> Result<Self> {
        let nvs = EspNvs::new(partition, NVS_NAMESPACE, true)
            .map_err(|e| anyhow!("NVS open failed: {:?}", e))?;

        // リングバッファ位置を復元
        let log_head = nvs_get_u32(&nvs, KEY_LOG_HEAD).unwrap_or(0);
        let log_tail = nvs_get_u32(&nvs, KEY_LOG_TAIL).unwrap_or(0);

        info!("Storage初期化完了: log_head={}, log_tail={}", log_head, log_tail);

        Ok(Self {
            nvs,
            log_head,
            log_tail,
        })
    }

    // ──────────────────────────────────
    // Safety Config
    // ──────────────────────────────────

    /// Safety設定をNVSから読み込み (未設定時はデフォルト)
    pub fn load_safety_config(&self) -> Result<SafetyConfig> {
        match nvs_get_blob(&self.nvs, KEY_SAFETY_CONFIG) {
            Some(data) => {
                match serde_json::from_slice::<SafetyConfig>(&data) {
                    Ok(config) => {
                        info!("Safety設定をNVSから復元");
                        Ok(config)
                    }
                    Err(e) => {
                        warn!("Safety設定のデシリアライズ失敗: {:?} → デフォルト使用", e);
                        Ok(SafetyConfig::default())
                    }
                }
            }
            None => {
                info!("Safety設定未保存 → デフォルト使用");
                Ok(SafetyConfig::default())
            }
        }
    }

    /// Safety設定をNVSに保存
    pub fn save_safety_config(&mut self, config: &SafetyConfig) -> Result<()> {
        let data = serde_json::to_vec(config)
            .map_err(|e| anyhow!("Serialize failed: {:?}", e))?;

        nvs_set_blob(&mut self.nvs, KEY_SAFETY_CONFIG, &data)?;
        info!("Safety設定をNVSに保存完了");
        Ok(())
    }

    // ──────────────────────────────────
    // 生活リズムデータ
    // ──────────────────────────────────

    /// 生活リズムデータをNVSに保存
    pub fn save_rhythm_data(&mut self, pattern: &DailyPattern) -> Result<()> {
        let data = serde_json::to_vec(pattern)
            .map_err(|e| anyhow!("Serialize failed: {:?}", e))?;

        nvs_set_blob(&mut self.nvs, KEY_RHYTHM_DATA, &data)?;
        debug!("生活リズムデータ保存: 学習日数={}", pattern.days_learned);
        Ok(())
    }

    /// 生活リズムデータをNVSから読み込み
    pub fn load_rhythm_data(&self) -> Option<DailyPattern> {
        nvs_get_blob(&self.nvs, KEY_RHYTHM_DATA)
            .and_then(|data| serde_json::from_slice(&data).ok())
    }

    // ──────────────────────────────────
    // WiFi設定
    // ──────────────────────────────────

    /// WiFi認証情報を保存 (プロビジョニング時)
    pub fn save_wifi_credentials(&mut self, ssid: &str, password: &str) -> Result<()> {
        nvs_set_str(&mut self.nvs, KEY_WIFI_SSID, ssid)?;
        nvs_set_str(&mut self.nvs, KEY_WIFI_PASS, password)?;
        info!("WiFi認証情報をNVSに保存");
        Ok(())
    }

    /// WiFi認証情報を読み込み
    pub fn load_wifi_credentials(&self) -> Option<(String, String)> {
        let ssid = nvs_get_str(&self.nvs, KEY_WIFI_SSID)?;
        let password = nvs_get_str(&self.nvs, KEY_WIFI_PASS)?;
        Some((ssid, password))
    }

    // ──────────────────────────────────
    // デバイスID
    // ──────────────────────────────────

    /// デバイスIDを読み込み
    pub fn load_device_id(&self) -> Option<String> {
        nvs_get_str(&self.nvs, KEY_DEVICE_ID)
    }

    /// デバイスIDを保存 (工場プロビジョニング時、1回のみ)
    pub fn save_device_id(&mut self, device_id: &str) -> Result<()> {
        if self.load_device_id().is_some() {
            return Err(anyhow!("デバイスIDは既に設定済み (上書き禁止)"));
        }
        nvs_set_str(&mut self.nvs, KEY_DEVICE_ID, device_id)?;
        info!("デバイスID設定: {}", device_id);
        Ok(())
    }

    // ──────────────────────────────────
    // 監査ログ リングバッファ
    // ──────────────────────────────────

    /// ログエントリをリングバッファに追加
    pub fn buffer_log_entry(&mut self, snapshot: &SensorSnapshot) -> Result<()> {
        let log_json = serde_json::to_string(snapshot)
            .map_err(|e| anyhow!("Serialize failed: {:?}", e))?;

        let key = format!("{}{}", KEY_LOG_PREFIX, self.log_head % MAX_LOG_ENTRIES);
        nvs_set_str(&mut self.nvs, &key, &log_json)?;

        self.log_head = self.log_head.wrapping_add(1);
        nvs_set_u32(&mut self.nvs, KEY_LOG_HEAD, self.log_head)?;

        // リングバッファ: headがtailを追い越したらtailを進める
        let count = self.pending_count();
        if count > MAX_LOG_ENTRIES {
            self.log_tail = self.log_head.wrapping_sub(MAX_LOG_ENTRIES);
            nvs_set_u32(&mut self.nvs, KEY_LOG_TAIL, self.log_tail)?;
        }

        debug!("ログバッファ追加: head={}, tail={}, count={}",
               self.log_head, self.log_tail, self.pending_count());
        Ok(())
    }

    /// 未送信ログをmax_count件取得し、バッファから削除
    pub fn drain_pending_logs(&mut self, max_count: u32) -> Vec<String> {
        let mut logs = Vec::new();
        let count = self.pending_count().min(max_count);

        for _ in 0..count {
            let key = format!("{}{}", KEY_LOG_PREFIX, self.log_tail % MAX_LOG_ENTRIES);
            if let Some(log_str) = nvs_get_str(&self.nvs, &key) {
                logs.push(log_str);
            }
            self.log_tail = self.log_tail.wrapping_add(1);
        }

        // tail位置を保存
        if count > 0 {
            nvs_set_u32(&mut self.nvs, KEY_LOG_TAIL, self.log_tail).ok();
            debug!("ログバッファから{}件取得: tail={}", count, self.log_tail);
        }

        logs
    }

    /// 未送信ログ件数
    pub fn pending_count(&self) -> u32 {
        self.log_head.wrapping_sub(self.log_tail)
    }

    // ──────────────────────────────────
    // 工場リセット
    // ──────────────────────────────────

    /// 全データを消去 (WiFi認証情報 + 学習データ + ログ)
    /// デバイスIDとATECC608Aの鍵は保持
    pub fn factory_reset(&mut self) -> Result<()> {
        warn!("工場リセット実行");

        // WiFi認証情報を消去
        self.nvs.remove(KEY_WIFI_SSID).ok();
        self.nvs.remove(KEY_WIFI_PASS).ok();

        // 学習データを消去
        self.nvs.remove(KEY_RHYTHM_DATA).ok();

        // Safety設定をデフォルトに戻す
        self.save_safety_config(&SafetyConfig::default())?;

        // ログバッファをクリア
        self.log_head = 0;
        self.log_tail = 0;
        nvs_set_u32(&mut self.nvs, KEY_LOG_HEAD, 0)?;
        nvs_set_u32(&mut self.nvs, KEY_LOG_TAIL, 0)?;

        info!("工場リセット完了 (デバイスID/ATECC608A鍵は保持)");
        Ok(())
    }
}

// ──────────────────────────────────────
// NVSヘルパー関数
// ──────────────────────────────────────

fn nvs_get_u32(nvs: &EspNvs<NvsDefault>, key: &str) -> Option<u32> {
    nvs.get_u32(key).ok().flatten()
}

fn nvs_set_u32(nvs: &mut EspNvs<NvsDefault>, key: &str, value: u32) -> Result<()> {
    nvs.set_u32(key, value)
        .map_err(|e| anyhow!("NVS set_u32 failed ({}): {:?}", key, e))
}

fn nvs_get_str(nvs: &EspNvs<NvsDefault>, key: &str) -> Option<String> {
    // NVS文字列読み取り: まずサイズを取得してからバッファ確保
    let mut buf = [0u8; 512];
    match nvs.get_str(key, &mut buf) {
        Ok(Some(s)) => Some(s.to_string()),
        _ => None,
    }
}

fn nvs_set_str(nvs: &mut EspNvs<NvsDefault>, key: &str, value: &str) -> Result<()> {
    nvs.set_str(key, value)
        .map_err(|e| anyhow!("NVS set_str failed ({}): {:?}", key, e))
}

fn nvs_get_blob(nvs: &EspNvs<NvsDefault>, key: &str) -> Option<Vec<u8>> {
    let mut buf = [0u8; 2048];
    match nvs.get_raw(key, &mut buf) {
        Ok(Some(data)) => Some(data.to_vec()),
        _ => None,
    }
}

fn nvs_set_blob(nvs: &mut EspNvs<NvsDefault>, key: &str, data: &[u8]) -> Result<()> {
    nvs.set_raw(key, data)
        .map(|_| ())
        .map_err(|e| anyhow!("NVS set_raw failed ({}): {:?}", key, e))
}
