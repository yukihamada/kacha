//! NT3H1101 NFC I2C タグドライバー
//!
//! I2C アドレス: 0x55（デフォルト、A0ピン=GND時）
//!
//! 役割:
//!   - スマートフォンをかざすだけで BLE ペアリング URL を提示
//!   - NDEF URL レコードに https://kagi.home/pair/{device_id} を書き込む
//!   - FD（フィールド検知）ピン変化 → BLE ペアリングモードを自動起動
//!
//! NFC タッチによるペアリングフロー:
//!   スマホをバンドに近づける
//!     → NT3H1101 が NFC フィールドを検知（FD ピン Low → High）
//!     → ESP32-C3 が割り込み受信
//!     → BLE アドバタイズを起動（ペアリングモード）
//!     → スマホ側は NFC から読み取った URL でアプリを開く
//!     → アプリが BLE スキャンして自動接続

use esp_idf_hal::i2c::I2cDriver;

// ==================== アドレス・レジスタ定義 ====================

/// NT3H1101 I2C スレーブアドレス（A0=GND の場合）
pub const NT3H_ADDR: u8 = 0x55;

/// NFC メモリブロック0（NDEF メッセージ開始位置）
/// NT3H1101 のユーザーメモリは Block 1 から始まる（Block 0 はUID/設定）
const NDEF_BLOCK_START: u8 = 0x01;

/// 1ブロックのバイト数（NT3H1101 固定値）
const BLOCK_SIZE: usize = 16;

/// I2C タイムアウト（ms）
const I2C_TIMEOUT_MS: u32 = 100;

// ==================== NDEF エンコーダ ====================

/// NDEF URL レコードの Well-Known Type "U" プレフィックスコード
/// 0x04 = "https://"
const NDEF_URI_PREFIX_HTTPS: u8 = 0x04;

/// NDEF メッセージ最大サイズ（NT3H1101 ユーザーメモリ = 888バイト）
const NDEF_MAX_BYTES: usize = 888;

// ==================== ドライバー実装 ====================

/// NT3H1101 NFC I2C タグドライバー構造体
pub struct Nt3h1101<'d> {
    i2c: I2cDriver<'d>,
    /// このデバイスに割り当てられたデバイスID（BLEアドバタイズ名にも使用）
    device_id: heapless::String<16>,
}

impl<'d> Nt3h1101<'d> {
    /// 新規インスタンス作成
    ///
    /// # 引数
    /// - `i2c`: I2C ドライバー（MAX30102 と共有バスで使用可能）
    /// - `device_id`: デバイス識別子。ペアリングURLに埋め込まれる
    ///   例: "KAGI-001A" → https://kagi.home/pair/KAGI-001A
    pub fn new(i2c: I2cDriver<'d>, device_id: &str) -> Self {
        let mut id_str: heapless::String<16> = heapless::String::new();
        let _ = id_str.push_str(device_id);
        Nt3h1101 { i2c, device_id: id_str }
    }

    // ==================== I2C ブロック読み書き ====================

    /// NT3H1101 の指定ブロックに16バイトを書き込む
    ///
    /// NT3H1101 の I2C 書き込みフォーマット:
    ///   [ADDR(1B)] [BLOCK_NO(1B)] [DATA(16B)] = 計17バイト送信
    fn write_block(&mut self, block: u8, data: &[u8; BLOCK_SIZE]) -> Result<(), esp_idf_hal::sys::EspError> {
        let mut buf = [0u8; BLOCK_SIZE + 1];
        buf[0] = block;
        buf[1..].copy_from_slice(data);
        self.i2c.write(NT3H_ADDR, &buf, I2C_TIMEOUT_MS)
    }

    /// 指定ブロックから16バイトを読み出す
    fn read_block(&mut self, block: u8) -> Result<[u8; BLOCK_SIZE], esp_idf_hal::sys::EspError> {
        let mut buf = [0u8; BLOCK_SIZE];
        self.i2c.write_read(NT3H_ADDR, &[block], &mut buf, I2C_TIMEOUT_MS)?;
        Ok(buf)
    }

    // ==================== NDEF エンコード ====================

    /// NDEF URL レコードをエンコードし、NFC メモリに書き込む
    ///
    /// # NDEF フォーマット（RFC 5234 / NFC Forum Type 2 Tag）
    /// ```text
    /// TLV ラッパー:
    ///   0x03 [Length] [NDEF Message] 0xFE (Terminator)
    ///
    /// NDEF Message:
    ///   Header(1B) | Type_Len(1B) | Payload_Len(1B) | Type(1B) | Payload
    ///   Header = 0xD1 (MB=1, ME=1, SR=1, TNF=0x01 Well-Known)
    ///   Type   = 0x55 ('U' = URI record)
    ///   Payload= [URI_PREFIX(1B)] [URI文字列]
    /// ```
    ///
    /// # 引数
    /// - `url`: 書き込む URL 文字列（"https://" プレフィックスは自動付与）
    ///   例: "kagi.home/pair/KAGI-001A"
    pub fn write_ndef_url(&mut self, url: &str) -> Result<(), esp_idf_hal::sys::EspError> {
        // Payload = [プレフィックスコード(1B)] + URL バイト列
        // "https://" は NDEF_URI_PREFIX_HTTPS(0x04) で省略表現
        let url_bytes = url.as_bytes();
        let payload_len = 1 + url_bytes.len(); // プレフィックス1B + URL

        // NDEF レコード構築
        // Header: MB=1, ME=1, SR=1(Short Record), TNF=001(Well-Known)
        // → 0b1101_0001 = 0xD1
        let mut ndef_msg: heapless::Vec<u8, NDEF_MAX_BYTES> = heapless::Vec::new();

        // NDEF TLV Type-Len-Value ラッパー
        let ndef_record_len = 3 + payload_len as u8; // Header+TypeLen+PayloadLen + payload
        let _ = ndef_msg.push(0x03);              // NDEF TLV Tag
        let _ = ndef_msg.push(ndef_record_len + 1); // TLV Length (Type byte も含む)

        // NDEF Record ヘッダ
        let _ = ndef_msg.push(0xD1); // MB=1, ME=1, SR=1, TNF=0x01
        let _ = ndef_msg.push(0x01); // Type Length = 1 ('U')
        let _ = ndef_msg.push(payload_len as u8); // Payload Length
        let _ = ndef_msg.push(b'U'); // Record Type = 'U' (URI)

        // Payload: URI プレフィックス + URL
        let _ = ndef_msg.push(NDEF_URI_PREFIX_HTTPS);
        for &b in url_bytes {
            let _ = ndef_msg.push(b);
        }

        // TLV Terminator
        let _ = ndef_msg.push(0xFE);

        // 16バイト単位でブロック書き込み
        self.write_ndef_blocks(&ndef_msg)
    }

    /// NDEF テキストレコードを書き込む
    ///
    /// ステータス表示用途（「心拍: 72bpm, SpO2: 98%」など）に使用。
    /// NFC タッチ時にスマホのステータスバーにテキストをポップアップ表示できる。
    ///
    /// # 引数
    /// - `text`: 表示するテキスト（UTF-8）
    pub fn write_ndef_text(&mut self, text: &str) -> Result<(), esp_idf_hal::sys::EspError> {
        let text_bytes = text.as_bytes();
        // NDEF Text Record
        // Type = 'T', Payload = [Status(1B)] + [Lang(2B "ja")] + [Text]
        // Status byte: 0x02 = UTF-8, Lang Code Length = 2
        let lang = b"ja";
        let payload_len = 1 + lang.len() + text_bytes.len();

        let mut ndef_msg: heapless::Vec<u8, NDEF_MAX_BYTES> = heapless::Vec::new();
        let ndef_record_len = 3 + payload_len as u8;

        let _ = ndef_msg.push(0x03);              // NDEF TLV Tag
        let _ = ndef_msg.push(ndef_record_len + 1);

        let _ = ndef_msg.push(0xD1); // MB=1, ME=1, SR=1, TNF=0x01
        let _ = ndef_msg.push(0x01); // Type Length = 1 ('T')
        let _ = ndef_msg.push(payload_len as u8);
        let _ = ndef_msg.push(b'T'); // Record Type = 'T' (Text)

        // Payload
        let _ = ndef_msg.push(0x02); // Status: UTF-8, lang len=2
        for &b in lang    { let _ = ndef_msg.push(b); }
        for &b in text_bytes { let _ = ndef_msg.push(b); }

        let _ = ndef_msg.push(0xFE); // Terminator

        self.write_ndef_blocks(&ndef_msg)
    }

    /// NDEF バイト列を 16バイト単位でメモリブロックに分割書き込み
    fn write_ndef_blocks(&mut self, data: &[u8]) -> Result<(), esp_idf_hal::sys::EspError> {
        let mut block_no = NDEF_BLOCK_START;
        let mut offset = 0;

        while offset < data.len() {
            let mut block = [0u8; BLOCK_SIZE];
            let end = (offset + BLOCK_SIZE).min(data.len());
            block[..end - offset].copy_from_slice(&data[offset..end]);

            self.write_block(block_no, &block)?;

            offset += BLOCK_SIZE;
            block_no += 1;

            // NT3H1101 は連続書き込み時に 10ms インターバルが必要
            // esp_idf_hal::delay::FreeRtos::delay_ms(10);
        }

        Ok(())
    }

    // ==================== ペアリング URL 設定 ====================

    /// デバイスID を埋め込んだペアリング URL を NFC に書き込む
    ///
    /// 書き込まれる URL: https://kagi.home/pair/{device_id}
    ///
    /// # 使い方（起動時に一度だけ呼び出す）
    /// ```ignore
    /// nfc.write_pairing_url()?;
    /// // → スマホをかざすだけでペアリング画面が開く
    /// ```
    pub fn write_pairing_url(&mut self) -> Result<(), esp_idf_hal::sys::EspError> {
        // URL を組み立て: "kagi.home/pair/{device_id}"
        // write_ndef_url が "https://" プレフィックスを自動付与するため省略
        let mut url: heapless::String<64> = heapless::String::new();
        let _ = url.push_str("kagi.home/pair/");
        let _ = url.push_str(&self.device_id);

        self.write_ndef_url(&url)
    }

    // ==================== NFC フィールド検知コールバック ====================

    /// NFC フィールド検知時の処理
    ///
    /// # 呼び出しタイミング
    /// ESP32-C3 の GPIO に接続した NT3H1101 の FD（Field Detect）ピンが
    /// High になった際の割り込みハンドラから呼び出すこと。
    ///
    /// # 処理内容
    /// 1. BLE アドバタイズを起動（ペアリングモード）
    /// 2. ステータス LED を点滅（NFC タッチを視覚でフィードバック）
    ///
    /// # BLE 連携
    /// この関数は BLE モジュール（ble.rs）の `start_advertising()` を
    /// 呼び出すことでペアリングモードを有効化する。
    /// タイムアウト（デフォルト30秒）後は自動でアドバタイズを停止する。
    ///
    /// ```ignore
    /// // GPIO 割り込みハンドラ例（main.rs より）
    /// let mut nfc_fd_pin = gpio::PinDriver::input(peripherals.pins.gpio10)?;
    /// nfc_fd_pin.set_interrupt_type(InterruptType::PosEdge)?;
    /// nfc_fd_pin.enable_interrupt()?;
    ///
    /// loop {
    ///     if nfc_field_detected.load(Ordering::SeqCst) {
    ///         nfc.on_field_detect(&mut ble, &mut led)?;
    ///         nfc_field_detected.store(false, Ordering::SeqCst);
    ///     }
    ///     FreeRtos::delay_ms(10);
    /// }
    /// ```
    pub fn on_field_detect(
        &mut self,
        // BLE モジュールへの参照（ble.rs の BleDriver）
        // ble: &mut BleDriver,
        // LED GPIO ピン（ステータス点滅用）
        // led: &mut PinDriver<'_, gpio::Gpio2, gpio::Output>,
    ) -> Result<(), esp_idf_hal::sys::EspError> {
        // ---- Step 1: BLE ペアリングモード起動 ----
        // ble.start_advertising(30_000)?; // 30秒間アドバタイズ
        // BLE アドバタイズの実装は ble.rs の start_pairing_mode() を参照

        // ---- Step 2: ステータス LED 点滅（NFC タッチ確認）----
        // NFC を検知したことをユーザーに視覚フィードバック
        // 3回点滅: NFC 検知成功 + BLE ペアリングモード開始を示す
        // for _ in 0..3 {
        //     led.set_high()?;
        //     FreeRtos::delay_ms(150);
        //     led.set_low()?;
        //     FreeRtos::delay_ms(150);
        // }

        // ---- Step 3: NDEF を最新状態に更新（オプション）----
        // 心拍・SpO2 の最新値をテキストレコードとして書き込んでおくと
        // NFC タッチ時にスマホへリアルタイムデータを渡せる
        // let status = format_status(spo2, hr);
        // self.write_ndef_text(&status)?;

        Ok(())
    }
}
