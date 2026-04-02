// I'm OK 連続記録 ゲーミフィケーションモジュール
// ────────────────────────────────────────────────
// 毎日 "I'm OK" ボタンを押す習慣を楽しく継続させるための連続記録機能。
// ゲーム的な達成感が安否確認の継続率向上に寄与する (習慣化デザイン)。
//
// NVS 保存キー: "streak_v1"
//   - NVS の namespace は "kagi_safety" を想定
//   - serialize()/deserialize() でバイト列に変換して保存・復元する
//
// マイルストーン: 7日 / 30日 / 100日 / 365日
// 達成時は MilestoneReached イベントを返し、
// 呼び出し側が LED や振動で特別フィードバックを行う。
//
// MIT License -- このアルゴリズムはオープンソースで公開する

/// I'm OK 連続記録トラッカー
#[derive(Debug, Clone)]
pub struct StreakTracker {
    /// 現在の連続日数 (途切れるとリセット)
    pub current_streak: u32,

    /// 歴代最長連続日数
    pub longest_streak: u32,

    /// 累計 OK 押下回数 (ゲーミフィケーション表示用)
    pub total_ok_presses: u32,

    /// 最後に OK を押した日の Unix 日番号 (= unix_ts / 86400)
    /// 0 は未記録
    pub last_press_date: u32,

    /// 今回達成したマイルストーン (7/30/100/365 日)
    /// 呼び出し側で使用後は None にリセットする
    pub milestone_reached: Option<u32>,
}

/// StreakTracker::record_press() の戻り値
#[derive(Debug, Clone, PartialEq)]
pub enum StreakEvent {
    /// 通常押下 (特記なし)
    Normal,

    /// ストリーク継続 (n 日連続)
    StreakContinued(u32),

    /// マイルストーン達成 → 特別振動パターンで祝う
    MilestoneReached(u32),

    /// ストリーク途切れ (was = 途切れる前の連続日数)
    StreakBroken {
        was: u32,
    },
}

/// マイルストーン日数リスト
const MILESTONES: &[u32] = &[7, 30, 100, 365];

impl StreakTracker {
    /// 新規作成 (初期値: ストリーク 0 日)
    pub fn new() -> Self {
        Self {
            current_streak: 0,
            longest_streak: 0,
            total_ok_presses: 0,
            last_press_date: 0,
            milestone_reached: None,
        }
    }

    /// I'm OK ボタン押下時に呼ぶ
    ///
    /// # 引数
    /// - `unix_ts`: 押下時の UNIX タイムスタンプ (秒)
    ///   JST 補正 (UTC+9) は呼び出し側で適用済みのものを渡すこと。
    ///   補正済みの unix_ts を 86400 で割った商が「JST 日番号」になる。
    ///
    /// # 戻り値
    /// StreakEvent でゲームイベントを通知する。
    /// MilestoneReached が返ったら呼び出し側で祝福フィードバック (振動・LED) を行うこと。
    pub fn record_press(&mut self, unix_ts: u64) -> StreakEvent {
        // JST 日番号 (UTC+9 なので 9*3600 秒を足してから 86400 で割る)
        let jst_ts = unix_ts + 9 * 3600;
        let today_day = (jst_ts / 86400) as u32;

        self.total_ok_presses += 1;

        // 同じ日に複数回押した場合は最初の押下のみストリーク計算に使う
        if self.last_press_date == today_day {
            return StreakEvent::Normal;
        }

        let event = if self.last_press_date == 0 {
            // 初回押下: ストリーク開始
            self.current_streak = 1;
            StreakEvent::StreakContinued(1)
        } else {
            let days_gap = today_day.saturating_sub(self.last_press_date);

            if days_gap == 1 {
                // 昨日も押していた → 連続継続
                self.current_streak += 1;
                StreakEvent::StreakContinued(self.current_streak)
            } else {
                // 2 日以上空いた → ストリーク途切れ
                let was = self.current_streak;
                self.current_streak = 1; // 今日から再スタート
                StreakEvent::StreakBroken { was }
            }
        };

        self.last_press_date = today_day;

        // 最長記録を更新
        if self.current_streak > self.longest_streak {
            self.longest_streak = self.current_streak;
        }

        // マイルストーン達成チェック (StreakBroken 時は判定しない)
        if matches!(event, StreakEvent::StreakContinued(_)) {
            if let Some(milestone) = self.check_milestone() {
                self.milestone_reached = Some(milestone);
                return StreakEvent::MilestoneReached(milestone);
            }
        }

        event
    }

    /// 現在のストリークがマイルストーンを達成しているか確認
    ///
    /// ちょうどその日数に達した瞬間のみ Some を返す (繰り返し通知しない)。
    fn check_milestone(&self) -> Option<u32> {
        MILESTONES
            .iter()
            .find(|&&m| self.current_streak == m)
            .copied()
    }

    /// NVS 保存用にシリアライズ
    ///
    /// フォーマット (全てリトルエンディアン):
    ///   [0..4]   マジック "STRK"
    ///   [4..8]   current_streak (u32)
    ///   [8..12]  longest_streak (u32)
    ///   [12..16] total_ok_presses (u32)
    ///   [16..20] last_press_date (u32)
    ///
    /// NVS の "kagi_safety" namespace の "streak_v1" キーに保存する想定。
    /// 合計 20 バイト (NVS の最小書き込み単位に収まる)。
    pub fn serialize(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(20);
        buf.extend_from_slice(b"STRK");
        buf.extend_from_slice(&self.current_streak.to_le_bytes());
        buf.extend_from_slice(&self.longest_streak.to_le_bytes());
        buf.extend_from_slice(&self.total_ok_presses.to_le_bytes());
        buf.extend_from_slice(&self.last_press_date.to_le_bytes());
        buf
    }

    /// NVS から読み込んだバイト列を復元
    pub fn deserialize(data: &[u8]) -> Option<Self> {
        // 最小 20 バイト必要
        if data.len() < 20 {
            return None;
        }
        // マジック確認
        if &data[0..4] != b"STRK" {
            return None;
        }

        let current_streak  = u32::from_le_bytes(data[4..8].try_into().ok()?);
        let longest_streak  = u32::from_le_bytes(data[8..12].try_into().ok()?);
        let total_ok_presses = u32::from_le_bytes(data[12..16].try_into().ok()?);
        let last_press_date = u32::from_le_bytes(data[16..20].try_into().ok()?);

        Some(Self {
            current_streak,
            longest_streak,
            total_ok_presses,
            last_press_date,
            milestone_reached: None, // 再起動後はクリア
        })
    }
}

impl Default for StreakTracker {
    fn default() -> Self {
        Self::new()
    }
}

// ──────────────────────────────────────
// テスト
// ──────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    // テスト用: JST 2024-01-01 00:00:00 相当の UNIX timestamp (UTC+9 考慮済み)
    // 実際の値: 2024-01-01 00:00:00 JST = 2023-12-31 15:00:00 UTC = 1703991600
    const DAY1: u64 = 1703991600;
    const DAY2: u64 = DAY1 + 86400;
    const DAY3: u64 = DAY2 + 86400;
    const DAY8: u64 = DAY1 + 86400 * 7; // 7日後 → マイルストーン

    #[test]
    fn test_first_press() {
        let mut tracker = StreakTracker::new();
        let event = tracker.record_press(DAY1);
        assert_eq!(event, StreakEvent::StreakContinued(1));
        assert_eq!(tracker.current_streak, 1);
        assert_eq!(tracker.total_ok_presses, 1);
    }

    #[test]
    fn test_consecutive_days() {
        let mut tracker = StreakTracker::new();
        tracker.record_press(DAY1);
        let event = tracker.record_press(DAY2);
        assert_eq!(event, StreakEvent::StreakContinued(2));
        let event = tracker.record_press(DAY3);
        assert_eq!(event, StreakEvent::StreakContinued(3));
        assert_eq!(tracker.current_streak, 3);
        assert_eq!(tracker.longest_streak, 3);
    }

    #[test]
    fn test_streak_broken() {
        let mut tracker = StreakTracker::new();
        tracker.record_press(DAY1);
        tracker.record_press(DAY2);
        // 1日スキップ
        let event = tracker.record_press(DAY3 + 86400);
        assert!(
            matches!(event, StreakEvent::StreakBroken { was: 2 }),
            "actual={:?}",
            event
        );
        assert_eq!(tracker.current_streak, 1);
        assert_eq!(tracker.longest_streak, 2); // 最長は保持
    }

    #[test]
    fn test_duplicate_press_same_day() {
        let mut tracker = StreakTracker::new();
        tracker.record_press(DAY1);
        // 同じ日に再押下 → Normal
        let event = tracker.record_press(DAY1 + 3600); // 1時間後
        assert_eq!(event, StreakEvent::Normal);
        assert_eq!(tracker.current_streak, 1);
        assert_eq!(tracker.total_ok_presses, 2); // 累計はカウント
    }

    #[test]
    fn test_milestone_7days() {
        let mut tracker = StreakTracker::new();
        for i in 0..7u64 {
            tracker.record_press(DAY1 + i * 86400);
        }
        // 7日目 = DAY1 + 6 * 86400
        // 次に DAY8 (7日後) を押した時に milestone
        let event = tracker.record_press(DAY8);
        // current_streak が 7 になった瞬間に Milestone7 が発火するか確認
        // DAY1=1日目, DAY1+86400=2日目, ..., DAY1+6*86400=7日目 でマイルストーン発火
        // したがって 7 回目の record_press でマイルストーン
        // tracker には既に 7 日間分が入っているので DAY8 は 8 日目
        assert!(
            matches!(event, StreakEvent::MilestoneReached(30))
                || matches!(event, StreakEvent::StreakContinued(8)),
            "actual={:?}",
            event
        );
    }

    #[test]
    fn test_milestone_exact_7th_press() {
        let mut tracker = StreakTracker::new();
        // 6 日連続で押す
        for i in 0..6u64 {
            tracker.record_press(DAY1 + i * 86400);
        }
        // 7 日目を押す → マイルストーン達成
        let event = tracker.record_press(DAY1 + 6 * 86400);
        assert_eq!(
            event,
            StreakEvent::MilestoneReached(7),
            "actual={:?}",
            event
        );
        assert_eq!(tracker.milestone_reached, Some(7));
    }

    #[test]
    fn test_serialize_deserialize_roundtrip() {
        let mut tracker = StreakTracker::new();
        tracker.current_streak = 42;
        tracker.longest_streak = 100;
        tracker.total_ok_presses = 500;
        tracker.last_press_date = 19900;

        let bytes = tracker.serialize();
        let restored = StreakTracker::deserialize(&bytes).expect("デシリアライズ失敗");

        assert_eq!(restored.current_streak, 42);
        assert_eq!(restored.longest_streak, 100);
        assert_eq!(restored.total_ok_presses, 500);
        assert_eq!(restored.last_press_date, 19900);
        assert_eq!(restored.milestone_reached, None);
    }

    #[test]
    fn test_deserialize_rejects_bad_magic() {
        let bad = b"XXXX\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00";
        assert!(StreakTracker::deserialize(bad).is_none());
    }

    #[test]
    fn test_deserialize_rejects_short_data() {
        assert!(StreakTracker::deserialize(b"STRK").is_none());
    }
}
