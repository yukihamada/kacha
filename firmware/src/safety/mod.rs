// KAGI Safety Module
// Safety Ladder + ACS計算 + 生活リズム学習
// MIT License -- このアルゴリズムはオープンソースで公開する

pub mod circadian;
pub mod streak;
pub mod weather;

use anyhow::Result;
use log::{info, warn};
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::sensors::{MmWaveData, SensorSnapshot};
use circadian::CircadianProfile;
use weather::WeatherRiskFactor;

// ──────────────────────────────────────
// 設定
// ──────────────────────────────────────

/// Safety設定 (safety_config.yml から読み込み)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SafetyConfig {
    pub learning_days: u16,
    pub sensor_weights: SensorWeights,
    pub half_life_minutes: HalfLifeMinutes,
    pub thresholds: Thresholds,
    pub tier1_response_window_minutes: u32,
    pub tier2_response_window_minutes: u32,
    pub tier3_opt_in: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SensorWeights {
    pub mmwave: f32,
    pub ok_button: f32,
    pub door: f32,
    #[cfg(feature = "hub")]
    pub audio: f32,
    #[cfg(feature = "pro")]
    pub co2: f32,
    pub temperature: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HalfLifeMinutes {
    pub mmwave: f32,
    pub ok_button: f32,
    pub door: f32,
    #[cfg(feature = "hub")]
    pub audio: f32,
    /// CO2: 呼気による上昇は即座なので減衰は遅め (4h = 240min)
    /// 換気後に急低下するため「最新値を重視」する設計
    #[cfg(feature = "pro")]
    pub co2: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Thresholds {
    pub normal: f32,   // ACS >= normal → 緑
    pub caution: f32,  // caution <= ACS < normal → 黄
    pub alert: f32,    // ACS < alert → Tier1
}

impl Default for SafetyConfig {
    fn default() -> Self {
        Self {
            learning_days: 7,
            sensor_weights: SensorWeights {
                mmwave: 5.0,
                ok_button: 4.0,
                door: 3.0,
                #[cfg(feature = "hub")]
                audio: 2.0,
                #[cfg(feature = "pro")]
                co2: 2.0,
                temperature: 1.0,
            },
            half_life_minutes: HalfLifeMinutes {
                mmwave: 90.0,
                ok_button: 720.0,
                door: 720.0,
                #[cfg(feature = "hub")]
                audio: 120.0,
                #[cfg(feature = "pro")]
                co2: 240.0,  // 4時間 (換気後の自然低下速度に合わせる)
            },
            thresholds: Thresholds {
                normal: 0.6,
                caution: 0.3,
                alert: 0.3,
            },
            tier1_response_window_minutes: 30,
            tier2_response_window_minutes: 60,
            tier3_opt_in: false,
        }
    }
}

// ──────────────────────────────────────
// 状態機械
// ──────────────────────────────────────

/// Safety Ladder の状態
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum SafetyState {
    /// 正常 (ACS >= 0.6, 緑LED)
    Normal,
    /// 注意 (0.3 <= ACS < 0.6, 黄LED)
    Caution,
    /// Tier1準備中 (ACS < 0.3, チャタリング防止で10秒待機)
    Tier1Pending,
    /// Tier1: 本人確認中 (LED黄点滅 + ブザー, 30分カウント)
    Tier1Active,
    /// Tier2: 家族通知済み (60分カウント)
    Tier2Active,
    /// Tier3: 緊急連絡先に通知済み
    Tier3Active,
}

/// Safety Monitorが返すアクション指示
#[derive(Debug, Clone, PartialEq)]
pub enum SafetyAction {
    None,
    Tier1Alert,
    Tier2Notify,
    Tier3Emergency,
    ResetToNormal,
}

// ──────────────────────────────────────
// センサーシグナル (時間減衰つき)
// ──────────────────────────────────────

/// 各センサーの最終検知情報
#[derive(Debug, Clone, Serialize, Deserialize)]
struct SensorSignal {
    /// 生の信号値 (0.0 - 1.0)
    raw_value: f32,
    /// 最終検知時刻 (UNIX epoch seconds)
    last_detected_at: u64,
}

impl SensorSignal {
    fn new() -> Self {
        Self {
            raw_value: 0.0,
            last_detected_at: 0,
        }
    }

    /// 時間減衰を適用した現在の信号値を計算
    /// s_i(t) = s_i_raw * exp(-lambda_i * (t - t_last))
    fn decayed_value(&self, now: u64, half_life_minutes: f32) -> f32 {
        if self.last_detected_at == 0 || half_life_minutes <= 0.0 {
            return 0.0;
        }

        let elapsed_minutes = (now.saturating_sub(self.last_detected_at)) as f32 / 60.0;
        let lambda = (2.0_f32).ln() / half_life_minutes;
        let decay = (-lambda * elapsed_minutes).exp();

        self.raw_value * decay
    }

    /// 信号を更新
    fn update(&mut self, value: f32, timestamp: u64) {
        self.raw_value = value;
        self.last_detected_at = timestamp;
    }

    /// 最後の検知からの経過分数
    fn minutes_since_last(&self, now: u64) -> u32 {
        if self.last_detected_at == 0 {
            return u32::MAX;
        }
        ((now.saturating_sub(self.last_detected_at)) / 60) as u32
    }
}

// ──────────────────────────────────────
// 生活リズム学習 (ベイズ推定)
// ──────────────────────────────────────

/// 時間帯別のポアソン過程パラメータ (ベイズ事後分布)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DailyPattern {
    /// Gamma事後パラメータ alpha (時間帯別 0-23)
    alpha: [f32; 24],
    /// Gamma事後パラメータ beta (時間帯別 0-23)
    beta: [f32; 24],
    /// 起床時刻の推定 (時, 分)
    pub wake_time: (u8, u8),
    /// 就寝時刻の推定 (時, 分)
    pub sleep_time: (u8, u8),
    /// ドアが開く最長間隔 (分)
    pub max_door_interval: u32,
    /// 通常の静止時間 (分)
    pub typical_quiet_duration: u32,
    /// 学習日数
    pub days_learned: u16,
}

impl DailyPattern {
    fn new() -> Self {
        Self {
            // 弱い事前分布: alpha_0=2.0, beta_0=1.0
            alpha: [2.0; 24],
            beta: [1.0; 24],
            wake_time: (7, 0),    // デフォルト起床推定
            sleep_time: (23, 0),  // デフォルト就寝推定
            max_door_interval: 1440, // 24時間 (保守的)
            typical_quiet_duration: 480, // 8時間 (保守的)
            days_learned: 0,
        }
    }

    /// 新しいデータで事後分布を更新 (オンライン学習)
    pub fn update(&mut self, hour: u8, event_count: u32) {
        let h = (hour as usize).min(23);
        self.alpha[h] += event_count as f32;
        self.beta[h] += 1.0;
    }

    /// 1日分の学習完了を記録し、要約統計量を更新
    pub fn finish_day(&mut self, wake_hour: u8, sleep_hour: u8, max_door_gap: u32, max_quiet: u32) {
        self.days_learned = self.days_learned.saturating_add(1);

        // 指数移動平均で起床・就寝時刻を更新
        let alpha_smooth = 0.3_f32;
        self.wake_time.0 = lerp_u8(self.wake_time.0, wake_hour, alpha_smooth);
        self.sleep_time.0 = lerp_u8(self.sleep_time.0, sleep_hour, alpha_smooth);
        self.max_door_interval = lerp_u32(self.max_door_interval, max_door_gap, alpha_smooth);
        self.typical_quiet_duration = lerp_u32(self.typical_quiet_duration, max_quiet, alpha_smooth);
    }

    /// 現在時刻での異常スコアを計算
    /// lambda_h * (経過時間/60) -- 大きいほど異常
    pub fn anomaly_score(&self, hour: u8, minutes_since_last_event: u32) -> f32 {
        let h = (hour as usize).min(23);
        let lambda = self.alpha[h] / self.beta[h];
        let t_hours = minutes_since_last_event as f32 / 60.0;
        lambda * t_hours
    }

    /// 適応的閾値: 学習データに基づく安全係数
    pub fn adaptive_safety_factor(&self) -> f32 {
        if self.days_learned < 7 {
            2.0 // 保守的
        } else if self.days_learned < 30 {
            1.5 + 0.5 * (1.0 - self.days_learned as f32 / 30.0)
        } else {
            1.5
        }
    }

    /// 学習期間中か (通知を抑制する)
    pub fn is_learning(&self) -> bool {
        self.days_learned < 7
    }

    /// 現在が睡眠時間帯かどうかの推定
    pub fn is_sleep_time(&self, hour: u8) -> bool {
        let wake = self.wake_time.0;
        let sleep = self.sleep_time.0;
        if sleep > wake {
            // 通常パターン: 23時就寝 → 7時起床
            hour >= sleep || hour < wake
        } else {
            // 夜型パターン: 3時就寝 → 11時起床
            hour >= sleep && hour < wake
        }
    }
}

fn lerp_u8(old: u8, new: u8, alpha: f32) -> u8 {
    ((old as f32) * (1.0 - alpha) + (new as f32) * alpha) as u8
}

fn lerp_u32(old: u32, new: u32, alpha: f32) -> u32 {
    ((old as f32) * (1.0 - alpha) + (new as f32) * alpha) as u32
}

// ──────────────────────────────────────
// Safety Monitor (中核)
// ──────────────────────────────────────

pub struct SafetyMonitor {
    config: SafetyConfig,
    state: SafetyState,
    /// 各センサーのシグナル
    mmwave_signal: SensorSignal,
    button_signal: SensorSignal,
    door_signal: SensorSignal,
    temp_signal: SensorSignal,
    /// 計算されたACS
    acs: f32,
    /// 状態遷移した時刻
    state_entered_at: u64,
    /// 最新のセンサースナップショット
    snapshot: SensorSnapshot,
    /// 生活リズム学習データ (ベイズ推定ベース)
    rhythm: DailyPattern,
    /// 概日リズム学習プロファイル (時間帯別行動パターン)
    /// ACS 計算時の異常倍率として使用する
    circadian: CircadianProfile,
    /// 気象リスク係数 (外気温による心疾患リスク補正)
    /// 1 時間ごとに fetch() で更新し、最終 ACS に乗算する
    weather: WeatherRiskFactor,
    /// センサー故障フラグ
    mmwave_fault: bool,
    door_fault: bool,
    /// 旅行モード
    travel_mode: bool,
}

impl SafetyMonitor {
    pub fn new(config: SafetyConfig) -> Result<Self> {
        Ok(Self {
            config,
            state: SafetyState::Normal,
            mmwave_signal: SensorSignal::new(),
            button_signal: SensorSignal::new(),
            door_signal: SensorSignal::new(),
            temp_signal: SensorSignal::new(),
            acs: 1.0,
            state_entered_at: now_epoch(),
            snapshot: SensorSnapshot::default(),
            rhythm: DailyPattern::new(),
            // 概日リズム: 起動直後はニュートラル (学習データがない状態)
            circadian: CircadianProfile::new(),
            // 気象リスク: 起動直後はニュートラル (ネット接続前)
            weather: WeatherRiskFactor::neutral(),
            mmwave_fault: false,
            door_fault: false,
            travel_mode: false,
        })
    }

    /// mmWave OUTピンの在室情報を更新
    pub fn on_radar_presence(&mut self, present: bool) {
        if present {
            self.mmwave_signal.update(1.0, now_epoch());
        }
        self.snapshot.mmwave_presence = present;
    }

    /// mmWave UARTの詳細データを更新
    pub fn update_mmwave(&mut self, data: &MmWaveData) {
        self.snapshot.mmwave_breathing = data.breathing_detected;
        self.snapshot.mmwave_distance_cm = data.static_distance_cm;
        self.mmwave_fault = false; // データが来ればfaultクリア

        if data.breathing_detected {
            self.mmwave_signal.update(1.0, now_epoch());
        } else if data.motion_detected {
            self.mmwave_signal.update(0.8, now_epoch());
        }
    }

    /// ドアセンサーイベント
    pub fn on_door_event(&mut self, is_open: bool) {
        self.snapshot.door_open = is_open;
        self.door_fault = false;

        if is_open {
            // ドアが開いた = 生存シグナル
            self.door_signal.update(0.8, now_epoch());
        }
    }

    /// I'm OKボタン押下
    pub fn on_ok_button_pressed(&mut self) {
        info!("OK ボタン押下 → ACSリセット");
        self.button_signal.update(1.0, now_epoch());
        self.snapshot.button_pressed = true;

        // 概日リズム学習: 何時に OK を押す習慣があるかを記録
        let hour = current_hour();
        self.circadian.record_ok_press(hour);

        // 即座にNormalに戻す (どの状態からでも)
        self.transition_to(SafetyState::Normal);
    }

    /// 環境センサーデータを更新
    pub fn update_environmental(&mut self, snapshot: &SensorSnapshot) {
        self.snapshot.temperature_c = snapshot.temperature_c;
        self.snapshot.humidity_rh = snapshot.humidity_rh;

        // 温度が生活環境範囲内なら微弱な生存シグナル
        if snapshot.temperature_c >= 20.0 && snapshot.temperature_c <= 28.0 {
            self.temp_signal.update(0.3, now_epoch());
        }

        // 生活リズム学習: 時間帯別イベントカウント更新
        let hour = current_hour();
        self.rhythm.update(hour, 1);
    }

    /// メイン評価ロジック (10秒ごとに呼ばれる)
    pub fn evaluate(&mut self) -> SafetyAction {
        // 旅行モード中は全てスキップ
        if self.travel_mode {
            return SafetyAction::None;
        }

        // 学習期間中は通知しない (ログは記録する)
        let in_learning = self.rhythm.is_learning();

        // ── ACS計算 ─────────────────────────────────────────────────────
        // Step1: センサー重みつき加重平均 (基本ACS)
        let base_acs = self.compute_acs();

        // Step2: 概日リズム異常倍率を適用
        // circadian.anomaly_multiplier() は学習期間中 (7日未満) は 1.0 を返し、
        // 学習が完了した後は「この時間帯に活動がないのはどれほど異常か」を
        // 1.0〜3.0 で表す。倍率が高いほど ACS を厳しく補正する。
        //
        // ACS は「高いほど安全」なので、異常倍率は ACS を低下させる方向に働く。
        // 計算: acs_after_circadian = base_acs / anomaly_multiplier
        //   - anomaly 1.0 (正常) → ACS 変化なし
        //   - anomaly 2.0 (要注意) → ACS が半分になり Caution/Alert 判定が早まる
        //   - anomaly 3.0 (高異常) → ACS が 1/3 になり即座に Tier1 候補
        let hour = current_hour();
        let current_activity = self.mmwave_signal.raw_value;
        let anomaly = self.circadian.anomaly_multiplier(hour, current_activity);
        let acs_after_circadian = (base_acs / anomaly).clamp(0.0, 1.0);

        // Step3: 気象リスク倍率を最終 ACS に乗算
        // weather.risk_multiplier は 1.0〜1.5 の範囲。
        // 寒冷時は ACS 閾値が実質的に上がり、より早い段階で Caution/Alert に遷移する。
        // 実装: ACS を risk_multiplier で割ることで、同じ閾値基準で厳しく判定する。
        //   - risk 1.0 (温暖) → ACS 変化なし
        //   - risk 1.5 (極寒+急落) → ACS が 2/3 に低下 → 早期アラート
        let acs_final = (acs_after_circadian / self.weather.risk_multiplier).clamp(0.0, 1.0);

        self.acs = acs_final;
        self.snapshot.acs_score = self.acs;

        let now = now_epoch();
        let minutes_in_state = ((now.saturating_sub(self.state_entered_at)) / 60) as u32;

        match self.state {
            SafetyState::Normal => {
                if self.acs < self.config.thresholds.alert {
                    if !in_learning {
                        self.transition_to(SafetyState::Tier1Pending);
                    }
                } else if self.acs < self.config.thresholds.normal {
                    self.transition_to(SafetyState::Caution);
                }
                SafetyAction::None
            }

            SafetyState::Caution => {
                if self.acs >= self.config.thresholds.normal {
                    self.transition_to(SafetyState::Normal);
                    SafetyAction::ResetToNormal
                } else if self.acs < self.config.thresholds.alert && !in_learning {
                    self.transition_to(SafetyState::Tier1Pending);
                    SafetyAction::None
                } else {
                    SafetyAction::None
                }
            }

            SafetyState::Tier1Pending => {
                // チャタリング防止: evaluate()は10秒ごとに呼ばれる。
                // minutes_in_state >= 1 → 60秒間ACS低値が持続した場合にTier1発動。
                // 瞬間的なセンサーノイズや一時的な遮蔽で誤発報しない。
                if self.acs >= self.config.thresholds.alert {
                    // ACSが回復 → Normalへ (一時的ノイズだった)
                    self.transition_to(SafetyState::Normal);
                    SafetyAction::ResetToNormal
                } else if minutes_in_state >= 1 {
                    // 60秒以上ACS閾値割れ → Tier1発動
                    self.transition_to(SafetyState::Tier1Active);
                    SafetyAction::Tier1Alert
                } else {
                    SafetyAction::None
                }
            }

            SafetyState::Tier1Active => {
                if self.acs >= self.config.thresholds.caution {
                    // 生存シグナル復帰 → Normal
                    self.transition_to(SafetyState::Normal);
                    SafetyAction::ResetToNormal
                } else if minutes_in_state >= self.config.tier1_response_window_minutes {
                    // 30分無応答 → Tier2
                    self.transition_to(SafetyState::Tier2Active);
                    SafetyAction::Tier2Notify
                } else {
                    SafetyAction::None
                }
            }

            SafetyState::Tier2Active => {
                if self.acs >= self.config.thresholds.caution {
                    self.transition_to(SafetyState::Normal);
                    SafetyAction::ResetToNormal
                } else if minutes_in_state >= self.config.tier2_response_window_minutes
                    && self.config.tier3_opt_in
                {
                    // 60分無応答 + opt-in済み → Tier3
                    self.transition_to(SafetyState::Tier3Active);
                    SafetyAction::Tier3Emergency
                } else {
                    SafetyAction::None
                }
            }

            SafetyState::Tier3Active => {
                if self.acs >= self.config.thresholds.caution {
                    self.transition_to(SafetyState::Normal);
                    SafetyAction::ResetToNormal
                } else {
                    SafetyAction::None
                }
            }
        }
    }

    /// ACS (Alive Confidence Score) を計算
    /// ACS = Σ(w_i * s_i(t)) / Σ(w_i)
    fn compute_acs(&self) -> f32 {
        let now = now_epoch();
        let mut weighted_sum: f32 = 0.0;
        let mut weight_total: f32 = 0.0;

        // mmWave
        if !self.mmwave_fault {
            let s = self.mmwave_signal.decayed_value(now, self.config.half_life_minutes.mmwave);
            weighted_sum += self.config.sensor_weights.mmwave * s;
            weight_total += self.config.sensor_weights.mmwave;
        }

        // I'm OK ボタン
        let s = self.button_signal.decayed_value(now, self.config.half_life_minutes.ok_button);
        weighted_sum += self.config.sensor_weights.ok_button * s;
        weight_total += self.config.sensor_weights.ok_button;

        // ドアセンサー
        if !self.door_fault {
            let s = self.door_signal.decayed_value(now, self.config.half_life_minutes.door);
            weighted_sum += self.config.sensor_weights.door * s;
            weight_total += self.config.sensor_weights.door;
        }

        // 温度 (減衰なし: 現在値のみ)
        weighted_sum += self.config.sensor_weights.temperature * self.temp_signal.raw_value;
        weight_total += self.config.sensor_weights.temperature;

        if weight_total > 0.0 {
            (weighted_sum / weight_total).clamp(0.0, 1.0)
        } else {
            0.0
        }
    }

    /// 状態遷移
    fn transition_to(&mut self, new_state: SafetyState) {
        if self.state != new_state {
            info!("Safety状態遷移: {:?} → {:?} (ACS={:.2})", self.state, new_state, self.acs);
            self.state = new_state;
            self.state_entered_at = now_epoch();
        }
    }

    /// 現在のスナップショットを取得
    pub fn last_snapshot(&self) -> SensorSnapshot {
        let mut snap = self.snapshot.clone();
        snap.acs_score = self.acs;
        snap.safety_state = self.state;
        snap.timestamp = now_epoch();
        snap.mmwave_last_breath_ago_min = self.mmwave_signal.minutes_since_last(now_epoch());
        snap.door_last_open_ago_min = self.door_signal.minutes_since_last(now_epoch());
        snap.button_last_press_ago_min = self.button_signal.minutes_since_last(now_epoch());
        snap
    }

    /// 生活リズムデータへの参照
    pub fn rhythm_data(&self) -> &DailyPattern {
        &self.rhythm
    }

    /// 生活リズムデータを復元 (NVSから読み込み時)
    pub fn restore_rhythm(&mut self, pattern: DailyPattern) {
        self.rhythm = pattern;
        info!("生活リズムデータ復元完了: 学習日数={}", self.rhythm.days_learned);
    }

    /// 概日リズムプロファイルを NVS から復元
    ///
    /// 起動時に NVS の "kagi_safety"/"circadian_v1" から読み込んで呼ぶ。
    pub fn restore_circadian(&mut self, profile: CircadianProfile) {
        info!(
            "概日リズムプロファイル復元: 学習日数={}",
            profile.sample_days
        );
        self.circadian = profile;
    }

    /// 概日リズムプロファイルへの参照 (NVS保存時に使う)
    pub fn circadian_profile(&self) -> &CircadianProfile {
        &self.circadian
    }

    /// センサーイベントを概日リズム学習に反映
    ///
    /// update_environmental() / on_radar_presence() の後に呼ぶことを推奨。
    /// hour は JST での現在時刻 (current_hour() で取得)。
    pub fn update_circadian(&mut self, hour: u8, activity_level: f32) {
        self.circadian.record_activity(hour, activity_level);
    }

    /// I'm OK ボタン押下を概日リズム学習に反映
    ///
    /// on_ok_button_pressed() から内部で呼ばれる。
    /// 時刻別 OK 習慣パターンを学習する。
    pub fn record_circadian_ok(&mut self, hour: u8) {
        self.circadian.record_ok_press(hour);
    }

    /// 気象リスク係数を更新 (1時間ごとに呼ぶ)
    ///
    /// WeatherRiskFactor::fetch() で取得した値をセットする。
    /// ネット接続失敗時は WeatherRiskFactor::neutral() をセットすること。
    pub fn set_weather(&mut self, factor: WeatherRiskFactor) {
        info!(
            "気象リスク更新: temp={:.1}°C, delta={:.1}°C, multiplier={:.2}",
            factor.outdoor_temp_c, factor.temp_delta_from_yesterday, factor.risk_multiplier
        );
        self.weather = factor;
    }

    /// 現在の気象リスク係数への参照
    pub fn weather_factor(&self) -> &WeatherRiskFactor {
        &self.weather
    }

    /// 旅行モード設定
    pub fn set_travel_mode(&mut self, enabled: bool) {
        self.travel_mode = enabled;
        info!("旅行モード: {}", if enabled { "ON" } else { "OFF" });
    }

    /// 家族がTier2を解除
    pub fn on_family_confirms_ok(&mut self) {
        info!("家族が「問題なし」を確認 → Normal");
        self.transition_to(SafetyState::Normal);
    }

    /// 家族が「確認中」→ タイマー延長
    pub fn on_family_checking(&mut self) {
        info!("家族が確認中 → Tier2タイマー延長30分");
        // state_entered_atを現在時刻にリセットして実質30分延長
        self.state_entered_at = now_epoch();
    }

    /// 現在の状態を取得
    pub fn current_state(&self) -> SafetyState {
        self.state
    }

    /// 現在のACSを取得
    pub fn current_acs(&self) -> f32 {
        self.acs
    }
}

// ──────────────────────────────────────
// ユーティリティ
// ──────────────────────────────────────

/// 現在のUNIX epoch (秒)
fn now_epoch() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

/// 現在の時 (0-23, ローカルタイム JST=UTC+9)
fn current_hour() -> u8 {
    let epoch = now_epoch();
    let jst_epoch = epoch + 9 * 3600; // UTC+9
    ((jst_epoch % 86400) / 3600) as u8
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_signal_decay() {
        let mut signal = SensorSignal::new();
        signal.update(1.0, 1000);

        // 90分後 (半減期=90分): 0.5
        let value = signal.decayed_value(1000 + 90 * 60, 90.0);
        assert!((value - 0.5).abs() < 0.01);

        // 180分後 (2半減期): 0.25
        let value = signal.decayed_value(1000 + 180 * 60, 90.0);
        assert!((value - 0.25).abs() < 0.01);
    }

    #[test]
    fn test_acs_all_fresh_signals() {
        let config = SafetyConfig::default();
        let mut monitor = SafetyMonitor::new(config).unwrap();

        // 全センサーがアクティブ
        monitor.mmwave_signal.update(1.0, now_epoch());
        monitor.button_signal.update(1.0, now_epoch());
        monitor.door_signal.update(0.8, now_epoch());
        monitor.temp_signal.update(0.3, now_epoch());

        let acs = monitor.compute_acs();
        // (5*1.0 + 4*1.0 + 3*0.8 + 1*0.3) / (5+4+3+1) = 11.7/13 ≈ 0.90
        assert!(acs > 0.85 && acs < 0.95, "ACS={}", acs);
    }

    #[test]
    fn test_anomaly_score() {
        let mut pattern = DailyPattern::new();
        // 午前10時に高い活動量を学習
        for _ in 0..30 {
            pattern.update(10, 8);
        }

        let score = pattern.anomaly_score(10, 120); // 2時間無活動
        assert!(score > 5.0, "活発な時間帯に2時間無活動は異常度高");

        let score_night = pattern.anomaly_score(3, 120); // 午前3時に2時間無活動
        assert!(score_night < score, "深夜は異常度低い");
    }
}
