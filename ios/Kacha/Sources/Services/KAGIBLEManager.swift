import Foundation
import CoreBluetooth

// MARK: - KAGIBLEManager
// KAGIデバイスへのBLEローカル接続マネージャー
// プロトコル: kagi://local/ (GATT Service UUID 0x4B4C)
// Wi-Fiオフライン時でもBLE経由でデバイスの状態を読み取れる

@MainActor
final class KAGIBLEManager: NSObject, ObservableObject {

    // MARK: - Published State

    /// BLEスキャンで発見した近くのKAGIデバイス一覧
    @Published var nearbyDevices: [CBPeripheral] = []

    /// 現在接続中のデバイス (nilなら未接続)
    @Published var connectedDevice: CBPeripheral?

    /// 接続中デバイスから読み取ったローカルステータス
    @Published var localStatus: LocalDeviceStatus?

    /// BLEスキャン中フラグ
    @Published var isScanning = false

    /// BLE接続エラーメッセージ
    @Published var bleError: String?

    /// BLE電源状態
    @Published var isBluetoothAvailable = false

    // MARK: - BLE UUIDs
    // KAGI GATTサービス定義
    // Service: 0x4B4C (ASCII "KL" = Kagi Local)
    // Characteristic 0x4C01: デバイス情報 (読み取り専用)
    // Characteristic 0x4C02: StatusSummary 8バイト (読み取り専用)
    // Characteristic 0x4C03: 設定書き込み (書き込み専用)

    private let kagiServiceUUID       = CBUUID(string: "4B4C")
    private let statusCharUUID        = CBUUID(string: "4C02")  // StatusSummary 8バイト
    private let deviceInfoCharUUID    = CBUUID(string: "4C01")  // デバイス情報

    // MARK: - Internal

    private var centralManager: CBCentralManager!
    private var pendingPeripheral: CBPeripheral?  // 接続試行中のデバイス

    // MARK: - LocalDeviceStatus
    // BLEで読み取ったデバイスのローカル状態 (8バイトパース結果)

    struct LocalDeviceStatus {
        var acsPct: Int         // バイト0: Activity Confidence Score (0-100)
        var streakDays: Int     // バイト1: 連続安否確認日数
        var batteryPct: Int     // バイト2: バッテリー残量 (0-100)
        var isCharging: Bool    // バイト3, bit0: 充電中フラグ
        var wifiConnected: Bool // バイト3, bit1: Wi-Fi接続状態
        var alertActive: Bool   // バイト3, bit2: アラート発報中
        var lastActivityHours: Int // バイト4: 最終活動からの経過時間 (時間)
        var spo2: Int           // バイト5: 血中酸素飽和度 (%)
        var heartRate: Int      // バイト6: 心拍数 (bpm)
        // バイト7: 予約済み (将来の拡張用)

        /// バッテリー状態の説明文
        var batteryLabel: String {
            if isCharging { return "充電中 (\(batteryPct)%)" }
            switch batteryPct {
            case 80...100: return "十分 (\(batteryPct)%)"
            case 30...79:  return "正常 (\(batteryPct)%)"
            case 10...29:  return "残量少 (\(batteryPct)%)"
            default:       return "要充電 (\(batteryPct)%)"
            }
        }
    }

    // MARK: - Init

    override init() {
        super.init()
        // BLE初期化はメインスレッドで実行
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public Methods

    /// BLEスキャンを開始
    /// KAGIサービスUUID (0x4B4C) を持つデバイスのみを対象とする
    func startScan() {
        guard centralManager.state == .poweredOn else {
            bleError = "Bluetoothが無効です。設定から有効にしてください。"
            return
        }

        isScanning = true
        nearbyDevices = []
        bleError = nil

        // KAGIサービスUUIDでフィルタリングしてスキャン
        centralManager.scanForPeripherals(
            withServices: [kagiServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        #if DEBUG
        print("[KAGIBLEManager] BLEスキャン開始 (サービス: \(kagiServiceUUID))")
        #endif

        // 10秒後に自動停止
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if isScanning { stopScan() }
        }
    }

    /// BLEスキャンを停止
    func stopScan() {
        centralManager.stopScan()
        isScanning = false
        #if DEBUG
        print("[KAGIBLEManager] BLEスキャン停止 (発見: \(nearbyDevices.count)台)")
        #endif
    }

    /// 指定したKAGIデバイスに接続してStatusSummaryを読み取る
    func connect(to peripheral: CBPeripheral) {
        stopScan()
        pendingPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        #if DEBUG
        print("[KAGIBLEManager] 接続試行: \(peripheral.name ?? peripheral.identifier.uuidString)")
        #endif
    }

    /// 現在の接続を切断
    func disconnect() {
        guard let device = connectedDevice else { return }
        centralManager.cancelPeripheralConnection(device)
    }

    // MARK: - Private: StatusSummary パース

    /// 8バイトのStatusSummaryデータをLocalDeviceStatusに変換
    /// バイト定義:
    /// [0] ACS (0-100)
    /// [1] streakDays
    /// [2] batteryPct (0-100)
    /// [3] flagsByte: bit0=isCharging, bit1=wifiConnected, bit2=alertActive
    /// [4] lastActivityHours
    /// [5] spo2 (%)
    /// [6] heartRate (bpm)
    /// [7] 予約済み
    private func parseStatusSummary(_ data: Data) -> LocalDeviceStatus? {
        guard data.count >= 8 else {
            #if DEBUG
            print("[KAGIBLEManager] StatusSummaryが短すぎます: \(data.count)バイト (要8バイト)")
            #endif
            return nil
        }

        let bytes = [UInt8](data)
        let flagsByte = bytes[3]

        return LocalDeviceStatus(
            acsPct:            Int(bytes[0]),
            streakDays:        Int(bytes[1]),
            batteryPct:        Int(bytes[2]),
            isCharging:        (flagsByte & 0x01) != 0,   // bit0
            wifiConnected:     (flagsByte & 0x02) != 0,   // bit1
            alertActive:       (flagsByte & 0x04) != 0,   // bit2
            lastActivityHours: Int(bytes[4]),
            spo2:              Int(bytes[5]),
            heartRate:         Int(bytes[6])
        )
    }
}

// MARK: - CBCentralManagerDelegate
extension KAGIBLEManager: CBCentralManagerDelegate {

    /// BLEの電源状態が変化した時のコールバック
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            isBluetoothAvailable = central.state == .poweredOn
            switch central.state {
            case .poweredOn:
                bleError = nil
            case .poweredOff:
                bleError = "Bluetoothがオフになっています"
                isScanning = false
            case .unauthorized:
                bleError = "Bluetooth使用が許可されていません"
            case .unsupported:
                bleError = "このデバイスはBLEをサポートしていません"
            default:
                break
            }
        }
    }

    /// BLEデバイスを発見した時のコールバック
    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            // 重複を除いて追加
            guard !nearbyDevices.contains(where: { $0.identifier == peripheral.identifier }) else { return }
            nearbyDevices.append(peripheral)
            #if DEBUG
            print("[KAGIBLEManager] 発見: \(peripheral.name ?? "不明") RSSI=\(RSSI)dBm")
            #endif
        }
    }

    /// デバイス接続成功コールバック
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectedDevice = peripheral
            bleError = nil
            // サービス探索を開始
            peripheral.discoverServices([kagiServiceUUID])
            #if DEBUG
            print("[KAGIBLEManager] 接続成功: \(peripheral.name ?? peripheral.identifier.uuidString)")
            #endif
        }
    }

    /// デバイス接続失敗コールバック
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            pendingPeripheral = nil
            bleError = "接続に失敗しました: \(error?.localizedDescription ?? "不明なエラー")"
            #if DEBUG
            print("[KAGIBLEManager] 接続失敗: \(error?.localizedDescription ?? "不明")")
            #endif
        }
    }

    /// デバイス切断コールバック
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            if connectedDevice?.identifier == peripheral.identifier {
                connectedDevice = nil
                localStatus = nil
            }
            #if DEBUG
            print("[KAGIBLEManager] 切断: \(peripheral.name ?? "不明")")
            #endif
        }
    }
}

// MARK: - CBPeripheralDelegate
extension KAGIBLEManager: CBPeripheralDelegate {

    /// GATTサービス探索完了コールバック
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                bleError = "サービス探索エラー: \(error.localizedDescription)"
                return
            }

            guard let services = peripheral.services else { return }
            for service in services where service.uuid == kagiServiceUUID {
                // StatusSummaryキャラクタリスティックを探索
                peripheral.discoverCharacteristics([statusCharUUID, deviceInfoCharUUID], for: service)
            }
        }
    }

    /// キャラクタリスティック探索完了コールバック
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error {
                bleError = "キャラクタリスティック探索エラー: \(error.localizedDescription)"
                return
            }

            guard let characteristics = service.characteristics else { return }
            for char in characteristics {
                if char.uuid == statusCharUUID {
                    // StatusSummary (8バイト) を読み取り
                    peripheral.readValue(for: char)
                    #if DEBUG
                    print("[KAGIBLEManager] StatusSummary読み取り開始")
                    #endif
                }
            }
        }
    }

    /// キャラクタリスティック値読み取り完了コールバック
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error {
                bleError = "データ読み取りエラー: \(error.localizedDescription)"
                return
            }

            guard let data = characteristic.value else { return }

            if characteristic.uuid == statusCharUUID {
                // StatusSummary 8バイトをパースして状態を更新
                if let status = parseStatusSummary(data) {
                    localStatus = status
                    #if DEBUG
                    print("[KAGIBLEManager] ローカルステータス取得: ACS=\(status.acsPct)%, streak=\(status.streakDays)日")
                    #endif
                }
            }
        }
    }
}
