// I'm OK連続記録トラッカー (Band用シンプル版)
// NVSキー: "kagi_streak" namespace "band"

use log::info;

/// 連続記録を管理するトラッカー
#[derive(Debug, Clone, Copy)]
pub struct StreakTracker {
    pub current_streak: u32,
    pub longest_streak: u32,
    pub total_ok_presses: u32,
    last_press_day: u32, // Unix日数 (秒/86400)
}

/// ボタン押下時のイベント種別
#[derive(Debug, Clone, Copy)]
pub enum StreakEvent {
    /// 初回または通常の押下（連続記録なし）
    Normal,
    /// 連続記録が継続した (current_streak 日数)
    StreakContinued(u32),
    /// マイルストーン達成 (7, 30, 100, 365 日)
    MilestoneReached(u32),
    /// 連続記録が途切れた (was: 途切れる前のストリーク日数)
    StreakBroken { was: u32 },
}

impl StreakTracker {
    /// 新規ストラッカーを返す (全フィールドをゼロ初期化)
    pub fn new() -> Self {
        Self {
            current_streak: 0,
            longest_streak: 0,
            total_ok_presses: 0,
            last_press_day: 0,
        }
    }

    /// NVS から読み込む
    /// TODO: esp_idf_svc::nvs::EspNvs を使ってNamespace "band" / Key "kagi_streak" から
    ///       bincode/postcard でデシリアライズする実装を追加する。
    ///       NVS が読めない場合やキーが存在しない場合は new() を返す。
    pub fn load_from_nvs() -> Self {
        // TODO: NVS実装
        // let nvs = EspNvsPartition::<NvsDefault>::take().ok();
        // if let Some(nvs) = nvs {
        //     let ns = EspNvs::new(nvs, "band", true).ok();
        //     if let Some(ns) = ns { ... }
        // }
        info!("StreakTracker: NVS未実装のためデフォルト値を使用");
        Self::new()
    }

    /// NVS へ保存する
    /// TODO: esp_idf_svc::nvs::EspNvs を使ってNamespace "band" / Key "kagi_streak" に
    ///       bincode/postcard でシリアライズして書き込む実装を追加する。
    pub fn save_to_nvs(&self) {
        // TODO: NVS実装
        // let nvs = EspNvsPartition::<NvsDefault>::take().ok();
        // if let Some(nvs) = nvs { ... }
        info!(
            "StreakTracker: save_to_nvs未実装 (current={}, longest={}, total={})",
            self.current_streak, self.longest_streak, self.total_ok_presses
        );
    }

    /// I'm OKボタン押下を記録し、StreakEvent を返す
    ///
    /// - `unix_ts`: Unix エポック秒 (u64)
    pub fn record_press(&mut self, unix_ts: u64) -> StreakEvent {
        let today = (unix_ts / 86400) as u32;
        self.total_ok_presses += 1;

        // 初回押下
        if self.last_press_day == 0 {
            self.current_streak = 1;
            self.longest_streak = 1;
            self.last_press_day = today;
            info!("Streak: 初回記録 day={}", today);
            return StreakEvent::Normal;
        }

        // 同日の重複押下は無視 (ストリーク変化なし)
        if today == self.last_press_day {
            info!("Streak: 同日押下 (current={})", self.current_streak);
            return StreakEvent::StreakContinued(self.current_streak);
        }

        let event = if self.is_consecutive_day(self.last_press_day, today) {
            self.current_streak += 1;
            if self.current_streak > self.longest_streak {
                self.longest_streak = self.current_streak;
            }
            info!(
                "Streak: 継続! current={} longest={}",
                self.current_streak, self.longest_streak
            );

            if let Some(milestone) = Self::check_milestone(self.current_streak) {
                info!("Streak: マイルストーン達成! {} 日", milestone);
                StreakEvent::MilestoneReached(milestone)
            } else {
                StreakEvent::StreakContinued(self.current_streak)
            }
        } else {
            let broken_at = self.current_streak;
            info!(
                "Streak: 途切れ! was={} (last_day={}, today={})",
                broken_at, self.last_press_day, today
            );
            self.current_streak = 1;
            StreakEvent::StreakBroken { was: broken_at }
        };

        self.last_press_day = today;
        event
    }

    /// 前日と今日が連続しているか判定 (1日差なら true)
    fn is_consecutive_day(&self, last_day: u32, new_day: u32) -> bool {
        new_day.saturating_sub(last_day) == 1
    }

    /// マイルストーン判定: 7 / 30 / 100 / 365 日
    fn check_milestone(streak: u32) -> Option<u32> {
        match streak {
            7 | 30 | 100 | 365 => Some(streak),
            _ => None,
        }
    }
}

impl Default for StreakTracker {
    fn default() -> Self {
        Self::new()
    }
}
