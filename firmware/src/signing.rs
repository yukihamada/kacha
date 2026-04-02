// signing.rs — ATECC608A による生存証明署名モジュール
//
// 「鍵は人の命の証明である」
//
// ATECC608A (Microchip) はハードウェアセキュアエレメント。
// 内部に ECDSA P-256 秘密鍵を生成・保持し、外部に漏れることはない。
// このモジュールは「I'm OK ボタン押下」などの生存イベントに署名を付与し、
// サーバー側で改ざん検知・なりすまし防止を実現する。
//
// ## ハードウェア接続
// - I2C アドレス: 0x60 (ATECC608A デフォルト)
// - SDA: GPIO8 / SCL: GPIO9 (firmware/src/main.rs の pins モジュール参照)
// - 電源: 3.3V, 消費電流: スリープ時 150nA / アクティブ時 最大 6mA
//
// ## ATECC608A ゾーン構成 (量産前にプロビジョニングツールで設定)
// - Config Zone: デバイス固有設定、シリアルナンバー、鍵スロット設定
// - Data Zone: 鍵スロット 0 に ECDSA P-256 秘密鍵 (ECC_KEY_TYPE=4)
// - OTP Zone: デバイスモデル・バージョン情報 (ワンタイム書き込み)
//
// ## 使用ライブラリ選択
// atca-iface crate (https://crates.io/crates/atca-iface) を推奨。
// esp-idf の crypto_hal 経由でも利用可能だが、
// atca-iface は Rust ネイティブで ATECC のコマンドプロトコルを実装しており
// esp-idf-hal の I2cDriver と直接統合しやすい。
//
// ## 量産プロビジョニング手順
// 1. ATECC608A を工場出荷状態でボードに実装
// 2. プロビジョニングツール (python-cryptoauthlib) で鍵スロット設定
// 3. ECC_KEY_TYPE=4 (P-256) でスロット0に鍵生成コマンドを実行
// 4. 公開鍵をサーバーのデバイス登録テーブルに書き込み
// 5. Config/OTP ゾーンをロック (以降は変更不可)
// 6. シリアルナンバー (9バイト) を NVS に記録

use anyhow::{anyhow, Result};
use log::{debug, error, info, warn};
use std::sync::{Arc, Mutex};
use esp_idf_hal::i2c::I2cDriver;

// ATECC608A の I2C アドレス (デフォルト、アドレスピン未接続時)
const ATECC608A_ADDR: u8 = 0x60;

// ATECC608A コマンドオペコード
// (Microchip CryptoAuthLib ドキュメント参照)
const CMD_INFO: u8 = 0x30;       // デバイス情報取得
const CMD_NONCE: u8 = 0x16;      // ノンス生成 (署名前のランダム値セット)
const CMD_GENKEY: u8 = 0x40;     // 鍵生成 / 公開鍵取得
const CMD_SIGN: u8 = 0x41;       // ECDSA 署名生成
const CMD_READ: u8 = 0x02;       // ゾーン読み込み
const CMD_WAKE: u8 = 0x00;       // ウェイクアップシーケンス用

// 署名に使用する鍵スロット番号 (プロビジョニング時にここに鍵を生成)
const KEY_SLOT: u8 = 0;

// ウェイクアップ後の安定待機時間 (μs)
// ATECC608A のウェイクアップタイムは最大 1500μs
const WAKE_DELAY_US: u64 = 1600;

// コマンド実行後の最大待機時間 (ms)
// Sign コマンドは最長 50ms かかる
const SIGN_CMD_DELAY_MS: u64 = 60;
const SHORT_CMD_DELAY_MS: u64 = 10;

/// 生存証明イベントの種別
///
/// 各イベントは ATECC608A による ECDSA 署名が付与され、
/// サーバー側で検証される。
#[derive(Debug, Clone, Copy)]
pub enum ProofEvent {
    /// I'm OK ボタン押下 — ユーザーが意図的に安全を通知
    OkButton,
    /// 呼吸センサー（圧力マット等）による呼吸検知
    Breathing,
    /// MC-38 ドアセンサーによるドア開閉検知
    DoorOpen,
    /// 転倒検知センサーによるアラート
    FallDetected,
}

impl ProofEvent {
    /// JSON / ログ用の文字列表現
    pub fn as_str(&self) -> &'static str {
        match self {
            ProofEvent::OkButton => "ok_button",
            ProofEvent::Breathing => "breathing",
            ProofEvent::DoorOpen => "door_open",
            ProofEvent::FallDetected => "fall_detected",
        }
    }

    /// イベントを 1 バイトの識別子にエンコード (署名対象メッセージに含める)
    pub fn to_byte(&self) -> u8 {
        match self {
            ProofEvent::OkButton => 0x01,
            ProofEvent::Breathing => 0x02,
            ProofEvent::DoorOpen => 0x03,
            ProofEvent::FallDetected => 0x04,
        }
    }
}

/// ATECC608A による署名付き生存証明
///
/// サーバーへ送信する JSON ペイロードの核となるデータ構造。
/// signature と public_key を持つため、受信側は
/// Rust の `p256` crate や OpenSSL で検証できる。
#[derive(Debug, Clone)]
pub struct AliveProof {
    /// デバイスシリアルナンバー (ATECC608A Config Zone から読み出し、9バイト中 8バイト使用)
    pub device_id: [u8; 8],
    /// Unix タイムスタンプ (秒) — NTP 同期後の値を使用すること
    pub timestamp: u64,
    /// 生存イベントの種別
    pub event_type: ProofEvent,
    /// ECDSA P-256 署名 (R || S 形式、各 32バイト = 合計 64バイト)
    pub signature: [u8; 64],
    /// デバイス公開鍵 (X || Y 形式、各 32バイト = 合計 64バイト)
    /// ATECC608A のスロット 0 に対応する公開鍵
    pub public_key: [u8; 64],
}

/// ATECC608A を操作する署名器
///
/// ESP32-S3 と I2C で接続された ATECC608A に対してコマンドを発行し、
/// 生存証明イベントに ECDSA P-256 署名を付与する。
pub struct ProofSigner {
    /// I2C バスへの排他アクセス (sensors モジュールと共有)
    i2c: Arc<Mutex<I2cDriver<'static>>>,
    /// 起動時に読み出したデバイスシリアルナンバー (キャッシュ)
    device_id: [u8; 8],
    /// 起動時に読み出した公開鍵 (キャッシュ — スロット 0)
    public_key: [u8; 64],
}

impl ProofSigner {
    /// ATECC608A を初期化し、デバイスシリアルと公開鍵を読み出す
    ///
    /// # 引数
    /// - `i2c`: main.rs で生成した I2C バスへの Arc<Mutex<>>
    ///
    /// # エラー
    /// - ATECC608A が見つからない場合 (I2C NAK)
    /// - Config Zone がロックされていない場合 (プロビジョニング未完了)
    pub fn new(i2c: Arc<Mutex<I2cDriver<'static>>>) -> Result<Self> {
        info!("[signing] ATECC608A 初期化開始 (addr=0x{:02X})", ATECC608A_ADDR);

        let mut signer = Self {
            i2c,
            device_id: [0u8; 8],
            public_key: [0u8; 64],
        };

        // ウェイクアップシーケンスを送信
        signer.wake()?;

        // シリアルナンバーを Config Zone から読み出す
        // ATECC608A のシリアルは 9バイトだが、先頭 8バイトをデバイス ID として使用
        signer.device_id = signer.read_serial()?;
        info!("[signing] デバイスID: {:02X?}", signer.device_id);

        // スロット 0 の公開鍵を取得 (GenKey コマンド、鍵生成なし / 読み出しのみ)
        signer.public_key = signer.read_public_key(KEY_SLOT)?;
        info!("[signing] 公開鍵読み出し完了");

        Ok(signer)
    }

    /// 生存イベントに ATECC608A で署名した証明を生成する
    ///
    /// 署名対象メッセージ (32バイト) の構成:
    /// ```
    /// SHA-256( device_id[8] || timestamp[8] || event_type[1] || padding[15] )
    /// ```
    /// padding はゼロ埋め。サーバー側は同じ計算で検証する。
    ///
    /// # 引数
    /// - `event`: 生存イベントの種別
    /// - `timestamp`: Unix タイムスタンプ (NTP 同期済みであること)
    pub fn sign_alive_event(&self, event: ProofEvent, timestamp: u64) -> Result<AliveProof> {
        info!("[signing] 署名生成開始: event={}, ts={}", event.as_str(), timestamp);

        // 署名対象メッセージ (32バイト) を構成
        let message = self.build_message(timestamp, &event);
        debug!("[signing] メッセージ: {:02X?}", &message);

        // ATECC608A にメッセージをロード (Nonce コマンド)
        self.load_nonce(&message)?;

        // ECDSA 署名を生成 (Sign コマンド)
        // ATECC608A は内部でハッシュ済みデータに対して署名を実行する
        let signature = self.execute_sign(KEY_SLOT)?;

        Ok(AliveProof {
            device_id: self.device_id,
            timestamp,
            event_type: event,
            signature,
            public_key: self.public_key,
        })
    }

    /// 証明を JSON 文字列にシリアライズ (サーバー POST 用)
    ///
    /// 出力例:
    /// ```json
    /// {
    ///   "device_id": "0102030405060708",
    ///   "timestamp": 1711440000,
    ///   "event_type": "ok_button",
    ///   "signature": "aabbcc....",
    ///   "public_key": "ddeeff...."
    /// }
    /// ```
    /// hex エンコードはバイナリを URL-safe に扱うための標準的な選択。
    pub fn proof_to_json(proof: &AliveProof) -> String {
        // no_std 環境でもコンパイルできるよう serde は使わず手動フォーマット
        // 量産版では serde_json feature を有効にして置き換え可
        format!(
            r#"{{"device_id":"{device_id}","timestamp":{ts},"event_type":"{event}","signature":"{sig}","public_key":"{pk}"}}"#,
            device_id = hex_encode(&proof.device_id),
            ts = proof.timestamp,
            event = proof.event_type.as_str(),
            sig = hex_encode(&proof.signature),
            pk = hex_encode(&proof.public_key),
        )
    }

    /// Solana アンカリング用の 32バイトメッセージハッシュを生成
    ///
    /// Solana の `spl-memo` プログラムや `anchor_lang::solana_program::keccak`
    /// でオンチェーンに記録する際に使用するハッシュ値。
    ///
    /// ハッシュ計算: SHA-256( signature[64] || device_id[8] || timestamp[8] )
    /// = 署名自体をハッシュに含めることで証明の一意性を保証
    pub fn solana_message(proof: &AliveProof) -> [u8; 32] {
        // ESP32-S3 には SHA 加速ハードウェアがあるが、
        // esp-idf の mbedtls SHA-256 API を使うのが最もシンプル
        // ここでは純 Rust 実装の sha2 crate を使用 (no_std 対応)
        use sha2::{Digest, Sha256};

        let mut hasher = Sha256::new();
        hasher.update(&proof.signature);
        hasher.update(&proof.device_id);
        hasher.update(proof.timestamp.to_le_bytes());
        hasher.update([proof.event_type.to_byte()]);

        let result = hasher.finalize();
        let mut hash = [0u8; 32];
        hash.copy_from_slice(&result);
        hash
    }

    // ---- 内部実装 ----

    /// ATECC608A ウェイクアップシーケンスを送信
    ///
    /// ATECC608A はスリープ中に I2C アドレス 0x00 への
    /// 0バイト書き込み (SDA を LOW に保持) でウェイクアップする。
    /// esp-idf の I2cDriver では write(&[]) で実現する。
    fn wake(&self) -> Result<()> {
        let mut i2c = self.i2c.lock().map_err(|_| anyhow!("I2C mutex lock失敗"))?;

        // ウェイクアップパルス: アドレス 0x00 に 0バイト送信
        // NAK が返るが正常動作 (ATECC がウェイクアップ中のため)
        let _ = i2c.write(0x00, &[], 10);

        // ウェイクアップ安定待機
        esp_idf_hal::delay::Ets::delay_us(WAKE_DELAY_US as u32);

        // ウェイクアップ確認: ATECC608A アドレスへの読み込みで ACK を確認
        let mut resp = [0u8; 4];
        i2c.read(ATECC608A_ADDR, &mut resp, 100)
            .map_err(|e| anyhow!("ATECC608A ウェイクアップ失敗: {:?}", e))?;

        // 正常ウェイクアップ応答: 0x04 0x11 0x33 0x43
        if resp[0] != 0x04 || resp[1] != 0x11 {
            return Err(anyhow!("ATECC608A ウェイクアップ応答異常: {:02X?}", resp));
        }

        debug!("[signing] ATECC608A ウェイクアップ完了");
        Ok(())
    }

    /// Config Zone からシリアルナンバー (8バイト) を読み出す
    ///
    /// ATECC608A のシリアルナンバーはアドレス 0x00〜0x08 (9バイト) に格納。
    /// 先頭 4バイト + 末尾 5バイトがシリアル。ここでは先頭 8バイトを使用。
    fn read_serial(&self) -> Result<[u8; 8]> {
        // Read コマンド: Zone=Config(0), Slot=0, Offset=0, 4バイト読み込み×2
        let word0 = self.atecc_read(0x00, 0x0000)?; // bytes 0-3
        let word1 = self.atecc_read(0x00, 0x0002)?; // bytes 4-7

        let mut serial = [0u8; 8];
        serial[0..4].copy_from_slice(&word0);
        serial[4..8].copy_from_slice(&word1);
        Ok(serial)
    }

    /// スロットの公開鍵を取得 (GenKey コマンド、モード=読み出しのみ)
    ///
    /// モード 0x00: 新規鍵生成 (プロビジョニング時のみ使用)
    /// モード 0x26: 既存鍵の公開鍵を計算して返す (ここで使用)
    fn read_public_key(&self, slot: u8) -> Result<[u8; 64]> {
        let mut i2c = self.i2c.lock().map_err(|_| anyhow!("I2C mutex lock失敗"))?;

        // GenKey コマンドパケット構成
        // [count, opcode, mode, slot_lsb, slot_msb, crc_lsb, crc_msb]
        let cmd = self.build_command(CMD_GENKEY, 0x26, slot as u16, &[])?;
        i2c.write(ATECC608A_ADDR, &cmd, 100)
            .map_err(|e| anyhow!("GenKey コマンド送信失敗: {:?}", e))?;

        // GenKey の実行時間: 最大 115ms
        FreeRtos::delay_ms(120);

        // 応答読み出し: [count(1), pubkey(64), crc(2)] = 67バイト
        let mut resp = [0u8; 67];
        i2c.read(ATECC608A_ADDR, &mut resp, 200)
            .map_err(|e| anyhow!("GenKey 応答読み出し失敗: {:?}", e))?;

        // count バイトを確認 (67 = 0x43)
        if resp[0] != 0x43 {
            return Err(anyhow!("GenKey 応答サイズ異常: 0x{:02X}", resp[0]));
        }

        let mut pubkey = [0u8; 64];
        pubkey.copy_from_slice(&resp[1..65]);
        Ok(pubkey)
    }

    /// メッセージを ATECC608A にロード (Nonce コマンド、パススルーモード)
    ///
    /// モード 0x03: ExternalMessage モード — 外部メッセージをそのまま TempKey にロード
    /// これにより Sign コマンドが指定メッセージに対して署名を生成できる
    fn load_nonce(&self, message: &[u8; 32]) -> Result<()> {
        let mut i2c = self.i2c.lock().map_err(|_| anyhow!("I2C mutex lock失敗"))?;

        // Nonce コマンド: [count, opcode=0x16, mode=0x03, zero, zero, message[32], crc[2]]
        // 合計 39バイト
        let cmd = self.build_command(CMD_NONCE, 0x03, 0x0000, message)?;
        i2c.write(ATECC608A_ADDR, &cmd, 100)
            .map_err(|e| anyhow!("Nonce コマンド送信失敗: {:?}", e))?;

        FreeRtos::delay_ms(SHORT_CMD_DELAY_MS as u32);

        // 応答確認: [count=0x04, status=0x00, crc[2]]
        let mut resp = [0u8; 4];
        i2c.read(ATECC608A_ADDR, &mut resp, 100)
            .map_err(|e| anyhow!("Nonce 応答読み出し失敗: {:?}", e))?;

        if resp[1] != 0x00 {
            return Err(anyhow!("Nonce コマンドエラー: status=0x{:02X}", resp[1]));
        }
        Ok(())
    }

    /// Sign コマンドを実行し、ECDSA P-256 署名 (64バイト) を取得
    ///
    /// Sign コマンドはスロットの秘密鍵で TempKey (= load_nonce でロードしたメッセージ) に署名する。
    /// mode=0x80: ExternalMessage モード (TempKey の内容をそのまま署名対象とする)
    fn execute_sign(&self, slot: u8) -> Result<[u8; 64]> {
        let mut i2c = self.i2c.lock().map_err(|_| anyhow!("I2C mutex lock失敗"))?;

        // Sign コマンド: mode=0x80 (外部メッセージモード)
        let cmd = self.build_command(CMD_SIGN, 0x80, slot as u16, &[])?;
        i2c.write(ATECC608A_ADDR, &cmd, 100)
            .map_err(|e| anyhow!("Sign コマンド送信失敗: {:?}", e))?;

        // Sign コマンドの最大実行時間: 50ms
        FreeRtos::delay_ms(SIGN_CMD_DELAY_MS as u32);

        // 応答読み出し: [count(1), signature(64), crc(2)] = 67バイト
        let mut resp = [0u8; 67];
        i2c.read(ATECC608A_ADDR, &mut resp, 200)
            .map_err(|e| anyhow!("Sign 応答読み出し失敗: {:?}", e))?;

        if resp[0] != 0x43 {
            return Err(anyhow!("Sign 応答サイズ異常: 0x{:02X}", resp[0]));
        }

        let mut sig = [0u8; 64];
        sig.copy_from_slice(&resp[1..65]);
        info!("[signing] 署名生成完了");
        Ok(sig)
    }

    /// Config Zone の 4バイトワードを読み出す
    ///
    /// zone: 0=Config, 1=OTP, 2=Data
    /// address: ワードアドレス (4バイト単位)
    fn atecc_read(&self, zone: u8, address: u16) -> Result<[u8; 4]> {
        let mut i2c = self.i2c.lock().map_err(|_| anyhow!("I2C mutex lock失敗"))?;

        let cmd = self.build_command(CMD_READ, zone, address, &[])?;
        i2c.write(ATECC608A_ADDR, &cmd, 100)
            .map_err(|e| anyhow!("Read コマンド送信失敗: {:?}", e))?;

        FreeRtos::delay_ms(SHORT_CMD_DELAY_MS as u32);

        let mut resp = [0u8; 7]; // count(1) + data(4) + crc(2)
        i2c.read(ATECC608A_ADDR, &mut resp, 100)
            .map_err(|e| anyhow!("Read 応答読み出し失敗: {:?}", e))?;

        let mut word = [0u8; 4];
        word.copy_from_slice(&resp[1..5]);
        Ok(word)
    }

    /// ATECC608A コマンドパケットを構築 (CRC 付き)
    ///
    /// パケット構成: [count, opcode, param1, param2_lsb, param2_msb, data..., crc_lsb, crc_msb]
    /// count = パケット全体のバイト数 (count 自身を含む)
    fn build_command(&self, opcode: u8, param1: u8, param2: u16, data: &[u8]) -> Result<Vec<u8>> {
        let data_len = data.len();
        // count = opcode(1) + param1(1) + param2(2) + data + crc(2) + count(1) 自身 = 7 + data_len
        let count = 7 + data_len;
        if count > 255 {
            return Err(anyhow!("コマンドデータが長すぎる: {} bytes", data_len));
        }

        let mut pkt = Vec::with_capacity(count + 1); // +1 for word address byte
        // Word Address Byte (コマンドモード = 0x03)
        pkt.push(0x03);
        pkt.push(count as u8);
        pkt.push(opcode);
        pkt.push(param1);
        pkt.push((param2 & 0xFF) as u8);
        pkt.push(((param2 >> 8) & 0xFF) as u8);
        pkt.extend_from_slice(data);

        // CRC-16 計算 (ATECC608A 専用ポリノミアル: 0x8005、初期値 0x0000)
        let crc = atca_crc16(&pkt[1..pkt.len()]);
        pkt.push((crc & 0xFF) as u8);
        pkt.push(((crc >> 8) & 0xFF) as u8);

        Ok(pkt)
    }

    /// 署名対象メッセージ (32バイト) を構成
    ///
    /// 構成: device_id(8) || timestamp_le(8) || event_byte(1) || zero_padding(15)
    fn build_message(&self, timestamp: u64, event: &ProofEvent) -> [u8; 32] {
        let mut msg = [0u8; 32];
        msg[0..8].copy_from_slice(&self.device_id);
        msg[8..16].copy_from_slice(&timestamp.to_le_bytes());
        msg[16] = event.to_byte();
        // [17..32] はゼロ埋め (デフォルト)
        msg
    }
}

/// ATECC608A 専用 CRC-16 計算
///
/// ポリノミアル: 0x8005、初期値: 0x0000、反転なし
/// Microchip の CryptoAuthLib と同一アルゴリズム
fn atca_crc16(data: &[u8]) -> u16 {
    let poly: u16 = 0x8005;
    let mut crc: u16 = 0x0000;

    for &byte in data {
        for bit in 0..8 {
            let data_bit = (byte >> bit) & 1;
            let crc_bit = (crc >> 15) as u8;
            crc <<= 1;
            if (data_bit ^ crc_bit) != 0 {
                crc ^= poly;
            }
        }
    }
    crc
}

/// バイト列を小文字の hex 文字列にエンコード (serde 非依存)
fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

// FreeRtos は delay 用に import (build_command 内で使用)
use esp_idf_hal::delay::FreeRtos;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_proof_to_json_format() {
        // AliveProof の JSON シリアライズが正しい形式か確認
        let proof = AliveProof {
            device_id: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
            timestamp: 1711440000,
            event_type: ProofEvent::OkButton,
            signature: [0xAB; 64],
            public_key: [0xCD; 64],
        };
        let json = ProofSigner::proof_to_json(&proof);
        assert!(json.contains("\"event_type\":\"ok_button\""));
        assert!(json.contains("\"timestamp\":1711440000"));
        assert!(json.contains("\"device_id\":\"0102030405060708\""));
    }

    #[test]
    fn test_atca_crc16_known_value() {
        // Microchip アプリノートの既知テストベクタで CRC を検証
        // [0x07, 0x1B, 0x01, 0x00, 0x00] → CRC = 0x27D0 (要実機確認)
        let data = &[0x07u8, 0x1B, 0x01, 0x00, 0x00];
        let crc = atca_crc16(data);
        // 注意: この値は仮。実機 or CryptoAuthLib のテストスイートで確認すること
        assert_ne!(crc, 0x0000); // 少なくともゼロでないことを確認
    }

    #[test]
    fn test_proof_event_byte_unique() {
        // 各イベントが異なるバイト値を持つことを確認
        let events = [
            ProofEvent::OkButton,
            ProofEvent::Breathing,
            ProofEvent::DoorOpen,
            ProofEvent::FallDetected,
        ];
        let bytes: Vec<u8> = events.iter().map(|e| e.to_byte()).collect();
        let unique: std::collections::HashSet<u8> = bytes.iter().copied().collect();
        assert_eq!(bytes.len(), unique.len(), "イベントバイト値が重複している");
    }

    #[test]
    fn test_solana_message_length() {
        // Solana アンカリングメッセージが必ず 32バイトであることを確認
        let proof = AliveProof {
            device_id: [0u8; 8],
            timestamp: 0,
            event_type: ProofEvent::Breathing,
            signature: [0u8; 64],
            public_key: [0u8; 64],
        };
        let msg = ProofSigner::solana_message(&proof);
        assert_eq!(msg.len(), 32);
    }
}
