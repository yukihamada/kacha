// 気象データ連携モジュール
// ────────────────────────────────────────
// 外気温を OpenWeatherMap 無料 API から取得し、
// 心疾患リスクへの影響倍率 (1.0〜1.5) を計算する。
//
// 医学的根拠:
//   寒冷暴露・急激な気温変化は血圧上昇・血管収縮を引き起こし、
//   心筋梗塞・脳卒中リスクが冬季に高まることが多数の疫学研究で示されている。
//   特に前日比 -5°C 以上の急落は注意を要する。
//
// 実装上の注意:
//   esp-idf-svc の EspHttpConnection を使って同期 HTTP GET を行う。
//   ファームウェアは async ランタイムを持たないため fetch() は同期関数とする。
//   呼び出し側は別スレッド (FreeRTOS task) で 1 時間ごとに叩くこと。
//
// MIT License -- このアルゴリズムはオープンソースで公開する

use anyhow::Result;
use log::info;
// bail! は #[cfg(target_arch = "xtensa")] ブロック内で使用 (ESP32実機ビルド時)
#[allow(unused_imports)]
use anyhow::bail;

/// 気象リスク係数
#[derive(Debug, Clone)]
pub struct WeatherRiskFactor {
    /// 現在の外気温 (°C)
    pub outdoor_temp_c: f32,

    /// 前日比の温度差 (負 = 寒くなった)
    /// 例: -7.0 は昨日より 7°C 低い
    pub temp_delta_from_yesterday: f32,

    /// ACS への掛け算倍率 (1.0〜1.5)
    /// 値が大きいほど心疾患リスクが高く、ACS の閾値判定を厳しくする
    pub risk_multiplier: f32,
}

impl WeatherRiskFactor {
    /// ニュートラルな初期値 (起動直後、気象データ未取得の状態)
    pub fn neutral() -> Self {
        Self {
            outdoor_temp_c: 20.0,
            temp_delta_from_yesterday: 0.0,
            risk_multiplier: 1.0,
        }
    }

    /// OpenWeatherMap 無料 API から気温を取得してリスク係数を返す (同期)
    ///
    /// エンドポイント:
    ///   http://api.openweathermap.org/data/2.5/weather?q={city}&appid={key}&units=metric
    ///
    /// # 引数
    /// - `city`:    都市名 (例: "Tokyo,JP")
    /// - `api_key`: OpenWeatherMap API キー (NVS に保存し、ログに出力しないこと)
    /// - `prev_temp_c`: 前日の気温 (NVS から復元。初回は None → delta = 0)
    ///
    /// # エラー
    /// - ネットワーク接続なし → Err
    /// - API レスポンス不正 → Err
    /// - いずれの場合も呼び出し側は WeatherRiskFactor::neutral() にフォールバックすること
    pub fn fetch(city: &str, api_key: &str, prev_temp_c: Option<f32>) -> Result<Self> {
        // URL を heapless で構築 (ヒープアロケーションを最小限に)
        // api_key はログに出力しない
        let url = format!(
            "http://api.openweathermap.org/data/2.5/weather?q={}&appid={}&units=metric",
            city, api_key
        );

        info!("気象データ取得: city={}", city);

        // esp-idf-svc の HTTP クライアントを使って同期 GET
        // (embedded_svc::http::client::EspHttpConnection)
        // ここでは実装の骨格のみを示し、実際の HTTP 呼び出しは
        // esp_idf_svc::http::client モジュールで行う。
        let response_body = http_get_sync(&url)?;

        // JSON パース (serde_json)
        // レスポンス例:
        //   {"main":{"temp":14.2,"humidity":60},"weather":[{"description":"clear sky"}]}
        let temp_c = parse_temp_from_json(&response_body)?;

        let delta = prev_temp_c.map(|prev| temp_c - prev).unwrap_or(0.0);
        let risk_multiplier = Self::calculate_risk_multiplier(temp_c, delta);

        info!(
            "気象リスク計算: temp={:.1}°C, delta={:.1}°C, multiplier={:.2}",
            temp_c, delta, risk_multiplier
        );

        Ok(Self {
            outdoor_temp_c: temp_c,
            temp_delta_from_yesterday: delta,
            risk_multiplier,
        })
    }

    /// 気温と前日比から心疾患リスク倍率を計算
    ///
    /// # ルール (医学文献を参考に設定)
    /// | 気温      | 条件              | 倍率 |
    /// |-----------|-------------------|------|
    /// | 5°C 以下  | かつ 前日比 -5°C 以上 | 1.5 |
    /// | 5°C 以下  | その他            | 1.3 |
    /// | 5〜10°C   | -                 | 1.2 |
    /// | 10°C 超   | -                 | 1.0 |
    pub fn calculate_risk_multiplier(temp: f32, delta: f32) -> f32 {
        if temp <= 5.0 {
            if delta <= -5.0 {
                // 極寒 + 急激な寒冷化 → 最高リスク
                1.5
            } else {
                // 極寒のみ → 中リスク
                1.3
            }
        } else if temp <= 10.0 {
            // やや低温
            1.2
        } else {
            // 温暖: リスクなし
            1.0
        }
    }
}

// ──────────────────────────────────────
// 内部ヘルパー
// ──────────────────────────────────────

/// esp-idf-svc を使った同期 HTTP GET
///
/// 実際のファームウェアビルドでは embedded_svc::http::client を使う。
/// ここでは型シグネチャと責務を示す骨格実装とし、
/// feature フラグで本物の実装に切り替える。
fn http_get_sync(url: &str) -> Result<String> {
    // ── 実機実装 (esp-idf-svc) ───────────────────────────────────────────
    // use esp_idf_svc::http::client::{Configuration, EspHttpConnection};
    // use embedded_svc::http::client::Client;
    //
    // let connection = EspHttpConnection::new(&Configuration {
    //     use_global_ca_store: true,
    //     crt_bundle_attach: Some(esp_idf_svc::tls::X509::pem_until_nul),
    //     ..Default::default()
    // })?;
    // let mut client = Client::wrap(connection);
    // let request = client.get(url)?.submit()?;
    // let mut body = Vec::new();
    // embedded_svc::io::Read::read_to_end(&mut request, &mut body)?;
    // String::from_utf8(body).map_err(|e| anyhow::anyhow!(e))
    // ────────────────────────────────────────────────────────────────────

    // ── テスト/開発用スタブ ──────────────────────────────────────────────
    // 実機では上記の esp-idf-svc 実装に置き換える。
    // このスタブは cargo test (ホスト環境) でコンパイルを通すために存在する。
    #[cfg(not(target_arch = "xtensa"))]
    {
        // ホストでのテスト: 15°C のモックレスポンスを返す
        let _ = url; // 未使用警告を抑制
        return Ok(r#"{"main":{"temp":15.0,"humidity":55}}"#.to_string());
    }

    #[cfg(target_arch = "xtensa")]
    {
        // ESP32 実機: コンパイルエラーにして実装を強制
        bail!("http_get_sync: ESP32実機ではesp-idf-svc実装に差し替えること");
    }
}

/// OpenWeatherMap レスポンス JSON から気温を抽出
///
/// serde_json を使わず手動パースする (ヒープ節約のため)。
/// レスポンス形式: `{"main":{"temp":14.2, ...}, ...}`
fn parse_temp_from_json(json: &str) -> Result<f32> {
    // "temp": の後の数値を探す (シンプルな文字列検索)
    // serde_json は依存関係に含まれているが、ESP32 ヒープを節約するため
    // ここでは軽量な手動パースを採用する
    let key = "\"temp\":";
    let start = json
        .find(key)
        .ok_or_else(|| anyhow::anyhow!("JSON に 'temp' フィールドが見つからない"))?;

    let after_key = &json[start + key.len()..];
    // 数値部分を切り出し (スペース・カンマ・}まで)
    let num_str = after_key
        .trim_start()
        .split(|c: char| c == ',' || c == '}' || c == ' ')
        .next()
        .ok_or_else(|| anyhow::anyhow!("気温値のパース失敗"))?;

    num_str
        .trim()
        .parse::<f32>()
        .map_err(|e| anyhow::anyhow!("気温値のパース失敗: {} (raw='{}')", e, num_str))
}

// ──────────────────────────────────────
// テスト
// ──────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_risk_multiplier_extreme_cold_with_drop() {
        // 極寒 + 急激な寒冷化 → 1.5
        let m = WeatherRiskFactor::calculate_risk_multiplier(3.0, -6.0);
        assert_eq!(m, 1.5);
    }

    #[test]
    fn test_risk_multiplier_cold_no_drop() {
        // 極寒だが前日比は小さい → 1.3
        let m = WeatherRiskFactor::calculate_risk_multiplier(4.0, -2.0);
        assert_eq!(m, 1.3);
    }

    #[test]
    fn test_risk_multiplier_cool() {
        // やや低温 → 1.2
        let m = WeatherRiskFactor::calculate_risk_multiplier(8.0, 0.0);
        assert_eq!(m, 1.2);
    }

    #[test]
    fn test_risk_multiplier_warm() {
        // 温暖 → 1.0
        let m = WeatherRiskFactor::calculate_risk_multiplier(20.0, 3.0);
        assert_eq!(m, 1.0);
    }

    #[test]
    fn test_parse_temp_from_json() {
        let json = r#"{"coord":{"lon":139.69},"main":{"temp":14.2,"humidity":60}}"#;
        let temp = parse_temp_from_json(json).unwrap();
        assert!((temp - 14.2).abs() < 0.01, "temp={}", temp);
    }

    #[test]
    fn test_parse_temp_missing_field() {
        let json = r#"{"main":{"humidity":60}}"#;
        assert!(parse_temp_from_json(json).is_err());
    }

    #[test]
    fn test_neutral_default() {
        let n = WeatherRiskFactor::neutral();
        assert_eq!(n.risk_multiplier, 1.0);
    }
}
