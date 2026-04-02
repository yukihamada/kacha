// 概日リズム (Circadian Rhythm) 学習モジュール
// ──────────────────────────────────────────────
// 過去30日の行動パターンを時間帯別に学習し、
// 「この時間帯にこのレベルの活動がないのはどれほど異常か」を定量化する。
//
// NVS 保存キー: "circadian_v1"
//   - NVS の namespace は "kagi_safety" を想定
//   - serialize()/deserialize() でバイト列に変換して保存・復元する
//
// MIT License -- このアルゴリズムはオープンソースで公開する

/// 概日リズムプロファイル
///
/// 24時間を1時間単位で区切り、各時間帯の活動確率を EMA (指数移動平均) で学習する。
/// 学習に必要な最小日数は 7 日。それ以前は anomaly_multiplier が常に 1.0 を返し、
/// ACS に影響を与えない (誤検知を防ぐ保守的設計)。
#[derive(Debug, Clone)]
pub struct CircadianProfile {
    /// 各時間帯 (0-23h) の平均活動確率 (0.0=非活動, 1.0=フル活動)
    /// EMA で更新: new = old * (1 - alpha) + sample * alpha
    pub hourly_activity: [f32; 24],

    /// 平均起床時刻 (hour, 0-23)
    /// 連続7日以上学習後に推定が安定する
    pub typical_wakeup: Option<u8>,

    /// 平均就寝時刻 (hour, 0-23)
    pub typical_sleep: Option<u8>,

    /// I'm OK を押す習慣がある時刻リスト (重複除去, 最大 8 個)
    /// この時刻に OK が来なかった場合、異常スコアを微増させる用途
    pub ok_press_hours: Vec<u8>,

    /// 学習に使ったデータ日数 (7 日未満は学習中扱い)
    pub sample_days: u16,

    /// 直近の起床時刻履歴 (最大 30 日, EMA 計算用)
    wakeup_samples: Vec<u8>,

    /// 直近の就寝時刻履歴 (最大 30 日)
    sleep_samples: Vec<u8>,
}

impl CircadianProfile {
    /// 新規作成。デフォルトは全時間帯 0.5 (中立的な事前分布)。
    pub fn new() -> Self {
        Self {
            // 事前分布: 全時間帯 0.5 (何も知らない状態)
            // 学習が進むにつれて実際の行動パターンに収束する
            hourly_activity: [0.5; 24],
            typical_wakeup: None,
            typical_sleep: None,
            ok_press_hours: Vec::new(),
            sample_days: 0,
            wakeup_samples: Vec::new(),
            sleep_samples: Vec::new(),
        }
    }

    /// センサーイベントを記録して学習を更新
    ///
    /// # 引数
    /// - `hour`: イベントが発生した時刻 (0-23)
    /// - `activity_level`: 活動強度 (0.0-1.0)
    ///   例) mmWave 呼吸検知=1.0, ドア開閉=0.8, 温度変化=0.3
    pub fn record_activity(&mut self, hour: u8, activity_level: f32) {
        let h = (hour as usize).min(23);
        let level = activity_level.clamp(0.0, 1.0);

        // EMA 平滑化係数: 0.05 = 約20サンプルで新旧均衡
        // 新しいデータに徐々に追従し、単一ノイズで大きく動かない
        const EMA_ALPHA: f32 = 0.05;
        self.hourly_activity[h] =
            self.hourly_activity[h] * (1.0 - EMA_ALPHA) + level * EMA_ALPHA;
    }

    /// I'm OK ボタン押下を記録
    ///
    /// 同じ時刻に複数回押された場合はまとめて 1 エントリとして扱う。
    /// リストは最大 8 個 (ESP32 ヒープ節約のため上限あり)。
    pub fn record_ok_press(&mut self, hour: u8) {
        let h = hour.min(23);

        // 既存の時刻と近い (±1h) エントリがあれば追加しない
        // 朝一番に押す習慣なら 7 か 8 に集中するはず
        let already_recorded = self.ok_press_hours.iter().any(|&existing| {
            (existing as i16 - h as i16).abs() <= 1
        });

        if !already_recorded && self.ok_press_hours.len() < 8 {
            self.ok_press_hours.push(h);
            self.ok_press_hours.sort_unstable();
        }

        // OK 押下時刻も活動記録として学習に加える
        self.record_activity(h, 1.0);
    }

    /// 1 日分のデータ記録完了を通知し、sample_days をインクリメント
    ///
    /// # 引数
    /// - `wakeup_hour`: その日の推定起床時刻
    /// - `sleep_hour`:  その日の推定就寝時刻
    pub fn finish_day(&mut self, wakeup_hour: u8, sleep_hour: u8) {
        self.sample_days = self.sample_days.saturating_add(1);

        // 最大 30 日分のサンプルを保持 (古いものを削除)
        if self.wakeup_samples.len() >= 30 {
            self.wakeup_samples.remove(0);
        }
        if self.sleep_samples.len() >= 30 {
            self.sleep_samples.remove(0);
        }

        self.wakeup_samples.push(wakeup_hour);
        self.sleep_samples.push(sleep_hour);

        // 7 日以上たったら中央値で起床・就寝時刻を推定
        if self.sample_days >= 7 {
            self.typical_wakeup = median_hour(&self.wakeup_samples);
            self.typical_sleep = median_hour(&self.sleep_samples);
        }
    }

    /// 現在時刻・活動レベルの異常スコア倍率を返す
    ///
    /// # 戻り値
    /// - 1.0: 正常 (この時間帯にこの活動レベルは普通)
    /// - 1.0〜2.0: 要注意
    /// - 2.0〜3.0: 高異常 (この時間帯に活動がないのは非常に珍しい)
    ///
    /// # アルゴリズム
    /// 期待活動量 (hourly_activity[h]) と実際の activity の乖離を基に計算。
    /// 学習日数 7 日未満の場合は常に 1.0 を返す (誤検知防止)。
    pub fn anomaly_multiplier(&self, hour: u8, activity: f32) -> f32 {
        // 学習期間中はニュートラル (ACS に影響させない)
        if self.sample_days < 7 {
            return 1.0;
        }

        let h = (hour as usize).min(23);
        let expected = self.hourly_activity[h];
        let actual = activity.clamp(0.0, 1.0);

        // 就寝中は活動がなくても異常ではない
        if let Some(sleep) = self.typical_sleep {
            if let Some(wakeup) = self.typical_wakeup {
                if is_sleep_hour(hour, sleep, wakeup) {
                    // 睡眠時間帯: 活動ゼロでも異常ではない → 倍率 1.0
                    return 1.0;
                }
            }
        }

        // 期待値と実績の差: 期待 0.7 なのに実際 0.0 → 差 0.7 (大きな異常)
        let deficit = (expected - actual).max(0.0);

        // deficit を 0〜2.0 のスコアにマッピング
        // deficit 0.0 → 倍率 1.0 (正常)
        // deficit 0.5 → 倍率 2.0 (要注意)
        // deficit 1.0 → 倍率 3.0 (高異常)
        let multiplier = 1.0 + deficit * 2.0;
        multiplier.clamp(1.0, 3.0)
    }

    /// 学習データを NVS 保存用にシリアライズ
    ///
    /// フォーマット (全てリトルエンディアン):
    ///   [0..4]   マジック "CADR"
    ///   [4..6]   sample_days (u16)
    ///   [6..102] hourly_activity x24 (f32 x24 = 96 bytes)
    ///   [102]    typical_wakeup (u8, 0xFF = None)
    ///   [103]    typical_sleep  (u8, 0xFF = None)
    ///   [104]    ok_press_hours の個数 (u8)
    ///   [105..]  ok_press_hours の内容 (各 u8)
    ///
    /// NVS の "kagi_safety" namespace の "circadian_v1" キーに保存する想定。
    pub fn serialize(&self) -> Vec<u8> {
        let mut buf: Vec<u8> = Vec::with_capacity(120);

        // マジックバイト (フォーマット識別用)
        buf.extend_from_slice(b"CADR");

        // sample_days (u16 LE)
        buf.extend_from_slice(&self.sample_days.to_le_bytes());

        // hourly_activity (f32 x24)
        for &val in &self.hourly_activity {
            buf.extend_from_slice(&val.to_le_bytes());
        }

        // typical_wakeup / typical_sleep (0xFF = None)
        buf.push(self.typical_wakeup.unwrap_or(0xFF));
        buf.push(self.typical_sleep.unwrap_or(0xFF));

        // ok_press_hours
        buf.push(self.ok_press_hours.len() as u8);
        buf.extend_from_slice(&self.ok_press_hours);

        buf
    }

    /// NVS から読み込んだバイト列を復元
    ///
    /// フォーマットが不正な場合は None を返す (安全側フェールオーバー)。
    pub fn deserialize(data: &[u8]) -> Option<Self> {
        // 最小サイズ確認: マジック4 + days2 + hourly96 + wakeup1 + sleep1 + count1 = 105
        if data.len() < 105 {
            return None;
        }

        // マジック確認
        if &data[0..4] != b"CADR" {
            return None;
        }

        let sample_days = u16::from_le_bytes([data[4], data[5]]);

        // hourly_activity
        let mut hourly_activity = [0.0f32; 24];
        for (i, chunk) in data[6..102].chunks_exact(4).enumerate() {
            let bytes: [u8; 4] = chunk.try_into().ok()?;
            let val = f32::from_le_bytes(bytes);
            // NaN / Inf チェック (NVS の破損対策)
            if !val.is_finite() || val < 0.0 || val > 1.0 {
                return None;
            }
            hourly_activity[i] = val;
        }

        let typical_wakeup = match data[102] {
            0xFF => None,
            h if h <= 23 => Some(h),
            _ => None,
        };
        let typical_sleep = match data[103] {
            0xFF => None,
            h if h <= 23 => Some(h),
            _ => None,
        };

        let ok_count = data[104] as usize;
        // ok_press_hours が範囲外参照しないか確認
        if data.len() < 105 + ok_count {
            return None;
        }
        let ok_press_hours = data[105..105 + ok_count]
            .iter()
            .filter(|&&h| h <= 23)
            .copied()
            .collect::<Vec<u8>>();

        Some(Self {
            hourly_activity,
            typical_wakeup,
            typical_sleep,
            ok_press_hours,
            sample_days,
            wakeup_samples: Vec::new(), // 再学習で埋まる
            sleep_samples: Vec::new(),
        })
    }
}

impl Default for CircadianProfile {
    fn default() -> Self {
        Self::new()
    }
}

// ──────────────────────────────────────
// ヘルパー関数
// ──────────────────────────────────────

/// 時刻のリストから中央値を返す
fn median_hour(samples: &[u8]) -> Option<u8> {
    if samples.is_empty() {
        return None;
    }
    let mut sorted = samples.to_vec();
    sorted.sort_unstable();
    Some(sorted[sorted.len() / 2])
}

/// 指定時刻が就寝時間帯かどうかを判定
/// sleep=23, wakeup=7 なら 23:00〜06:59 が就寝帯
fn is_sleep_hour(hour: u8, sleep: u8, wakeup: u8) -> bool {
    if sleep > wakeup {
        // 通常パターン (夜型でない): 23 就寝 → 7 起床
        // hour >= sleep OR hour < wakeup
        hour >= sleep || hour < wakeup
    } else {
        // 朝型/深夜型: 3 就寝 → 11 起床
        hour >= sleep && hour < wakeup
    }
}

// ──────────────────────────────────────
// テスト
// ──────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_learning_period_returns_neutral() {
        let profile = CircadianProfile::new();
        // 7 日未満は常に 1.0 (学習中フラグ)
        assert_eq!(profile.anomaly_multiplier(10, 0.0), 1.0);
    }

    #[test]
    fn test_anomaly_after_learning() {
        let mut profile = CircadianProfile::new();
        // 7 日学習済みとして手動設定
        profile.sample_days = 7;
        // 午前 10 時は高活動 (0.9) を期待
        profile.hourly_activity[10] = 0.9;
        // 実際には無活動 → 高異常
        let mult = profile.anomaly_multiplier(10, 0.0);
        assert!(mult > 1.5, "活発な時間帯に無活動 → 倍率 > 1.5, actual={}", mult);
    }

    #[test]
    fn test_sleep_hour_returns_neutral() {
        let mut profile = CircadianProfile::new();
        profile.sample_days = 7;
        profile.typical_sleep = Some(23);
        profile.typical_wakeup = Some(7);
        // 深夜 2 時は就寝帯 → 無活動でも異常なし
        assert_eq!(profile.anomaly_multiplier(2, 0.0), 1.0);
    }

    #[test]
    fn test_serialize_deserialize_roundtrip() {
        let mut profile = CircadianProfile::new();
        profile.sample_days = 14;
        profile.hourly_activity[9] = 0.8;
        profile.typical_wakeup = Some(7);
        profile.typical_sleep = Some(23);
        profile.ok_press_hours = vec![8, 21];

        let bytes = profile.serialize();
        let restored = CircadianProfile::deserialize(&bytes).expect("デシリアライズ失敗");

        assert_eq!(restored.sample_days, 14);
        assert!((restored.hourly_activity[9] - 0.8).abs() < 0.001);
        assert_eq!(restored.typical_wakeup, Some(7));
        assert_eq!(restored.typical_sleep, Some(23));
        assert_eq!(restored.ok_press_hours, vec![8, 21]);
    }

    #[test]
    fn test_deserialize_rejects_corrupted_data() {
        // 不正マジック
        assert!(CircadianProfile::deserialize(b"XXXX").is_none());
        // 短すぎるデータ
        assert!(CircadianProfile::deserialize(b"CADR").is_none());
    }

    #[test]
    fn test_ok_press_dedup() {
        let mut profile = CircadianProfile::new();
        profile.record_ok_press(8);
        profile.record_ok_press(8); // 重複
        profile.record_ok_press(9); // ±1h で重複とみなす
        // 8 しか入らないはず
        assert_eq!(profile.ok_press_hours.len(), 1);
    }
}
