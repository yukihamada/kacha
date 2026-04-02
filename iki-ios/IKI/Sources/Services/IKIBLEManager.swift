import Foundation
import CoreBluetooth

// MARK: - IKIBLEManager
// IKIデバイスへのBLEローカル接続マネージャー
// プロトコル: iki://local/ (GATT Service UUID 0x4B4C)
// Wi-Fiオフライン時でもBLE経由でデバイスの状態を読み取れる

@MainActor
final class IKIBLEManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var nearbyDevices: [CBPeripheral] = []
    @Published var connectedDevice: CBPeripheral?
    @Published var localStatus: LocalDeviceStatus?
    @Published var isScanning = false
    @Published var bleError: String?
    @Published var isBluetoothAvailable = false

    // MARK: - BLE UUIDs
    // GATT Service: 0x4B4C (ASCII "KL")
    // Characteristic 0x4C01: デバイス情報 (読み取り専用)
    // Characteristic 0x4C02: StatusSummary 8バイト (読み取り専用)
    // Characteristic 0x4C03: 設定書き込み (書き込み専用)

    private let ikiServiceUUID       = CBUUID(string: "4B4C")
    private let statusCharUUID       = CBUUID(string: "4C02")
    private let deviceInfoCharUUID   = CBUUID(string: "4C01")

    // MARK: - Internal

    private var centralManager: CBCentralManager!
    private var pendingPeripheral: CBPeripheral?

    // MARK: - LocalDeviceStatus

    struct LocalDeviceStatus {
        var acsPct: Int
        var streakDays: Int
        var batteryPct: Int
        var isCharging: Bool
        var wifiConnected: Bool
        var alertActive: Bool
        var lastActivityHours: Int
        var spo2: Int
        var heartRate: Int

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
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public Methods

    func startScan() {
        guard centralManager.state == .poweredOn else {
            bleError = "Bluetoothが無効です。設定から有効にしてください。"
            return
        }

        isScanning = true
        nearbyDevices = []
        bleError = nil

        centralManager.scanForPeripherals(
            withServices: [ikiServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        #if DEBUG
        print("[IKIBLEManager] BLEスキャン開始 (サービス: \(ikiServiceUUID))")
        #endif

        // 10秒後に自動停止
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if isScanning { stopScan() }
        }
    }

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
        #if DEBUG
        print("[IKIBLEManager] BLEスキャン停止 (発見: \(nearbyDevices.count)台)")
        #endif
    }

    func connect(to peripheral: CBPeripheral) {
        stopScan()
        pendingPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        #if DEBUG
        print("[IKIBLEManager] 接続試行: \(peripheral.name ?? peripheral.identifier.uuidString)")
        #endif
    }

    func disconnect() {
        guard let device = connectedDevice else { return }
        centralManager.cancelPeripheralConnection(device)
    }

    // MARK: - Private: StatusSummary パース

    private func parseStatusSummary(_ data: Data) -> LocalDeviceStatus? {
        guard data.count >= 8 else {
            #if DEBUG
            print("[IKIBLEManager] StatusSummaryが短すぎます: \(data.count)バイト (要8バイト)")
            #endif
            return nil
        }

        let bytes = [UInt8](data)
        let flagsByte = bytes[3]

        return LocalDeviceStatus(
            acsPct:            Int(bytes[0]),
            streakDays:        Int(bytes[1]),
            batteryPct:        Int(bytes[2]),
            isCharging:        (flagsByte & 0x01) != 0,
            wifiConnected:     (flagsByte & 0x02) != 0,
            alertActive:       (flagsByte & 0x04) != 0,
            lastActivityHours: Int(bytes[4]),
            spo2:              Int(bytes[5]),
            heartRate:         Int(bytes[6])
        )
    }
}

// MARK: - CBCentralManagerDelegate
extension IKIBLEManager: CBCentralManagerDelegate {

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

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            guard !nearbyDevices.contains(where: { $0.identifier == peripheral.identifier }) else { return }
            nearbyDevices.append(peripheral)
            #if DEBUG
            print("[IKIBLEManager] 発見: \(peripheral.name ?? "不明") RSSI=\(RSSI)dBm")
            #endif
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectedDevice = peripheral
            bleError = nil
            peripheral.discoverServices([ikiServiceUUID])
            #if DEBUG
            print("[IKIBLEManager] 接続成功: \(peripheral.name ?? peripheral.identifier.uuidString)")
            #endif
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            pendingPeripheral = nil
            bleError = "接続に失敗しました: \(error?.localizedDescription ?? "不明なエラー")"
            #if DEBUG
            print("[IKIBLEManager] 接続失敗: \(error?.localizedDescription ?? "不明")")
            #endif
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            if connectedDevice?.identifier == peripheral.identifier {
                connectedDevice = nil
                localStatus = nil
            }
            #if DEBUG
            print("[IKIBLEManager] 切断: \(peripheral.name ?? "不明")")
            #endif
        }
    }
}

// MARK: - CBPeripheralDelegate
extension IKIBLEManager: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                bleError = "サービス探索エラー: \(error.localizedDescription)"
                return
            }

            guard let services = peripheral.services else { return }
            for service in services where service.uuid == ikiServiceUUID {
                peripheral.discoverCharacteristics([statusCharUUID, deviceInfoCharUUID], for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error {
                bleError = "キャラクタリスティック探索エラー: \(error.localizedDescription)"
                return
            }

            guard let characteristics = service.characteristics else { return }
            for char in characteristics {
                if char.uuid == statusCharUUID {
                    peripheral.readValue(for: char)
                    #if DEBUG
                    print("[IKIBLEManager] StatusSummary読み取り開始")
                    #endif
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error {
                bleError = "データ読み取りエラー: \(error.localizedDescription)"
                return
            }

            guard let data = characteristic.value else { return }

            if characteristic.uuid == statusCharUUID {
                if let status = parseStatusSummary(data) {
                    localStatus = status
                    #if DEBUG
                    print("[IKIBLEManager] ローカルステータス取得: ACS=\(status.acsPct)%, streak=\(status.streakDays)日")
                    #endif
                }
            }
        }
    }
}
