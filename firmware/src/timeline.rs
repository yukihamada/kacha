// KAGI タイムライン — 家族アプリ向け「最後の1分」表示
//
// 設計思想:
//   家族が一番知りたいのは「今日の何時まで元気だったか」。
//   アラートだけでなく、時系列の活動ログを提供することで
//   家族の不安を解消し、不必要な緊急連絡を減らす。
//
// プライバシー設計:
//   「何時に呼吸を検知」「何時にドアが開いた」のみ記録。
//   映像・音声・会話内容は一切記録しない。

use serde::{Deserialize, Serialize};

/// タイムラインエントリ (1イベント)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimelineEntry {
    /// Unix timestamp (秒)
    pub ts: u64,
    /// イベント種別
    pub event: TimelineEvent,
    /// その時点のACS (0.0-1.0)
    pub acs: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TimelineEvent {
    /// I'm OKボタン押下
    OkButton { streak_days: u32 },
    /// mmWaveレーダーで呼吸検知 (定期サマリー)
    BreathingActive,
    /// ドア開閉
    DoorOpened,
    DoorClosed,
    /// 転倒アラート
    FallAlert { severity: u8 },
    /// SpO2/心拍アラート
    HealthAlert { spo2: u8, hr: u8 },
    /// 入室 / 退室
    PresenceDetected,
    PresenceLost { inactive_minutes: u32 },
    /// システム
    DeviceBooted,
    WifiConnected,
    WifiLost,
    BatteryLow { percent: u8 },
    /// Tier遷移
    Tier1Started,
    Tier2Started,
    AlertResolved,
}

/// タイムラインリング (最大 N エントリ、古いものを自動削除)
pub struct Timeline {
    entries: std::collections::VecDeque<TimelineEntry>,
    max_entries: usize,
}

impl Timeline {
    /// 最大 288 エントリ = 5分ごとに記録して24時間分
    pub fn new() -> Self {
        Self {
            entries: std::collections::VecDeque::with_capacity(288),
            max_entries: 288,
        }
    }

    /// イベントを追加
    pub fn push(&mut self, ts: u64, event: TimelineEvent, acs: f32) {
        if self.entries.len() >= self.max_entries {
            self.entries.pop_front(); // 古いエントリを削除
        }
        self.entries.push_back(TimelineEntry { ts, event, acs });
    }

    /// 直近 N 件を返す (家族アプリ用)
    pub fn recent(&self, n: usize) -> Vec<&TimelineEntry> {
        self.entries.iter().rev().take(n).collect()
    }

    /// 最後の活動イベント (OkButton / Breathing / DoorOpened) を返す
    pub fn last_activity(&self) -> Option<&TimelineEntry> {
        self.entries.iter().rev().find(|e| {
            matches!(
                e.event,
                TimelineEvent::OkButton { .. }
                    | TimelineEvent::BreathingActive
                    | TimelineEvent::DoorOpened
                    | TimelineEvent::PresenceDetected
            )
        })
    }

    /// 最後の活動からの経過分数
    pub fn minutes_since_last_activity(&self, now: u64) -> Option<u32> {
        self.last_activity()
            .map(|e| ((now.saturating_sub(e.ts)) / 60) as u32)
    }

    /// 家族アプリに送るJSONサマリー (最新24時間、5分バケット)
    pub fn to_json_summary(&self, now: u64) -> String {
        let last = self.last_activity();
        let inactive_min = last
            .map(|e| ((now.saturating_sub(e.ts)) / 60) as u32)
            .unwrap_or(u32::MAX);

        let recent: Vec<_> = self.recent(20).iter().map(|e| {
            serde_json::json!({
                "ts": e.ts,
                "event": format!("{:?}", e.event),
                "acs": (e.acs * 100.0) as u8,
            })
        }).collect();

        serde_json::json!({
            "last_activity_ts": last.map(|e| e.ts),
            "inactive_minutes": inactive_min,
            "status": classify_status(inactive_min),
            "recent_events": recent,
        })
        .to_string()
    }
}

/// 不活動時間からステータス文字列を返す (家族アプリ表示用)
fn classify_status(inactive_min: u32) -> &'static str {
    match inactive_min {
        0..=120 => "active",       // 2時間以内
        121..=480 => "quiet",      // 2〜8時間 (睡眠可能性)
        481..=1440 => "check",     // 8〜24時間 → 要確認
        _ => "alert",              // 24時間超
    }
}

/// SafetyMonitor から定期的に呼ばれるスナップショット記録
pub fn record_periodic_snapshot(
    timeline: &mut Timeline,
    ts: u64,
    acs: f32,
    breathing_detected: bool,
) {
    // 5分ごとに呼吸状態をサマリー記録
    if breathing_detected {
        timeline.push(ts, TimelineEvent::BreathingActive, acs);
    }
    // ACSが急変した場合のみ記録 (ストレージ節約)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_last_activity() {
        let mut tl = Timeline::new();
        tl.push(1000, TimelineEvent::BreathingActive, 0.9);
        tl.push(2000, TimelineEvent::DoorOpened, 0.8);
        tl.push(3000, TimelineEvent::WifiLost, 0.8);

        // WifiLostは活動とみなさない
        assert_eq!(tl.last_activity().unwrap().ts, 2000);
        assert_eq!(tl.minutes_since_last_activity(3060).unwrap(), 17);
    }

    #[test]
    fn test_ring_buffer_overflow() {
        let mut tl = Timeline::new();
        for i in 0..300u64 {
            tl.push(i * 300, TimelineEvent::BreathingActive, 0.9);
        }
        assert_eq!(tl.entries.len(), 288); // max_entries を超えない
        assert_eq!(tl.entries.front().unwrap().ts, 12 * 300); // 古いものが削除された
    }

    #[test]
    fn test_classify_status() {
        assert_eq!(classify_status(60), "active");
        assert_eq!(classify_status(300), "quiet");
        assert_eq!(classify_status(600), "check");
        assert_eq!(classify_status(2000), "alert");
    }
}
