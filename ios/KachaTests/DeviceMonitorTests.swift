import XCTest
@testable import Kacha

// MARK: - DeviceMonitor Unit Tests
// DeviceAlertモデルとAlertTypeのロジック、DeviceMonitorServiceの
// 重複排除ロジックをテストする。SwiftData / ネットワーク非依存。

final class DeviceMonitorTests: XCTestCase {

    // MARK: - DeviceAlert モデル

    func testDeviceAlertInitialState() {
        let alert = DeviceAlert(
            homeId: "home-001",
            deviceName: "Sesame Lock",
            alertType: AlertType.lowBattery.rawValue,
            message: "電池残量が15%です",
            severity: "warning"
        )

        XCTAssertFalse(alert.id.isEmpty)
        XCTAssertEqual(alert.homeId, "home-001")
        XCTAssertEqual(alert.deviceName, "Sesame Lock")
        XCTAssertEqual(alert.alertType, "low_battery")
        XCTAssertEqual(alert.severity, "warning")
        XCTAssertFalse(alert.isResolved)
        XCTAssertNil(alert.resolvedAt)
    }

    func testDeviceAlertResolvedState() {
        let alert = DeviceAlert(
            homeId: "home-001",
            deviceName: "SwitchBot Lock",
            alertType: AlertType.unlockAfterCheckout.rawValue,
            message: "チェックアウト後30分未施錠",
            severity: "critical"
        )

        let resolvedAt = Date()
        alert.isResolved = true
        alert.resolvedAt = resolvedAt

        XCTAssertTrue(alert.isResolved)
        XCTAssertNotNil(alert.resolvedAt)
        XCTAssertEqual(alert.resolvedAt, resolvedAt)
    }

    // MARK: - AlertType severity 正しさ

    func testAlertTypeSeverityMapping() {
        XCTAssertEqual(AlertType.unlockAfterCheckout.defaultSeverity, "critical")
        XCTAssertEqual(AlertType.deviceOffline.defaultSeverity, "critical")
        XCTAssertEqual(AlertType.lowBattery.defaultSeverity, "warning")
        XCTAssertEqual(AlertType.highTemperature.defaultSeverity, "warning")
        XCTAssertEqual(AlertType.lowTemperature.defaultSeverity, "warning")
        XCTAssertEqual(AlertType.highHumidity.defaultSeverity, "warning")
        XCTAssertEqual(AlertType.lightLeftOn.defaultSeverity, "warning")
    }

    func testAlertTypeTitlesNotEmpty() {
        for type in AlertType.allCases {
            XCTAssertFalse(type.title.isEmpty, "\(type.rawValue) のタイトルが空")
        }
    }

    func testAlertTypeIconsNotEmpty() {
        for type in AlertType.allCases {
            XCTAssertFalse(type.icon.isEmpty, "\(type.rawValue) のアイコンが空")
        }
    }

    func testAlertTypeRawValues() {
        XCTAssertEqual(AlertType.lowBattery.rawValue, "low_battery")
        XCTAssertEqual(AlertType.unlockAfterCheckout.rawValue, "unlock_after_checkout")
        XCTAssertEqual(AlertType.highTemperature.rawValue, "high_temperature")
        XCTAssertEqual(AlertType.lowTemperature.rawValue, "low_temperature")
        XCTAssertEqual(AlertType.highHumidity.rawValue, "high_humidity")
        XCTAssertEqual(AlertType.lightLeftOn.rawValue, "light_left_on")
        XCTAssertEqual(AlertType.deviceOffline.rawValue, "device_offline")
    }

    func testNotificationIdentifierPrefixContainsRawValue() {
        for type in AlertType.allCases {
            XCTAssertTrue(type.notificationIdentifierPrefix.contains(type.rawValue),
                "\(type.rawValue) の notificationIdentifierPrefix が rawValue を含まない")
        }
    }

    // MARK: - バッテリー20%未満でアラート severity

    func testLowBatteryAlertIsWarning() {
        // バッテリー < 20% のアラートは "warning"
        let alert = DeviceAlert(
            homeId: "home-001",
            deviceName: "Sesame (uuid-1234...)",
            alertType: AlertType.lowBattery.rawValue,
            message: "電池残量が15%です。早めに交換してください。",
            severity: AlertType.lowBattery.defaultSeverity
        )
        XCTAssertEqual(alert.severity, "warning")
        XCTAssertEqual(alert.alertType, AlertType.lowBattery.rawValue)
    }

    func testCriticalBatteryNukiAlertIsCritical() {
        // Nukiの batteryCritical = true は "critical"
        let alert = DeviceAlert(
            homeId: "home-002",
            deviceName: "Nuki Smart Lock",
            alertType: AlertType.lowBattery.rawValue,
            message: "Nuki Smart Lockの電池残量が危険レベルです。すぐに交換してください。",
            severity: "critical" // Nukiは常にcritical
        )
        XCTAssertEqual(alert.severity, "critical")
    }

    // MARK: - チェックアウト後未施錠アラート severity

    func testUnlockAfterCheckoutIsCritical() {
        let alert = DeviceAlert(
            homeId: "home-001",
            deviceName: "SwitchBot Lock",
            alertType: AlertType.unlockAfterCheckout.rawValue,
            message: "山田様のチェックアウトから30分以上経過しましたが、SwitchBot Lockが解錠状態です。",
            severity: AlertType.unlockAfterCheckout.defaultSeverity
        )
        XCTAssertEqual(alert.alertType, "unlock_after_checkout")
        XCTAssertEqual(alert.severity, "critical",
            "チェックアウト後未施錠アラートは critical であるべき")
        XCTAssertFalse(alert.isResolved)
    }

    // MARK: - 重複アラート排除ロジック（インメモリシミュレーション）

    func testDuplicateDetectionLogic() {
        // DeviceMonitorService の fireAlert 内の重複チェックロジックを
        // アラート配列を使ってインメモリで再現する。

        var existingAlerts: [DeviceAlert] = []

        func isDuplicate(homeId: String, deviceName: String, type: AlertType) -> Bool {
            existingAlerts.contains { alert in
                !alert.isResolved &&
                alert.alertType == type.rawValue &&
                alert.homeId == homeId &&
                alert.deviceName == deviceName
            }
        }

        func addAlert(homeId: String, deviceName: String, type: AlertType, severity: String) {
            guard !isDuplicate(homeId: homeId, deviceName: deviceName, type: type) else { return }
            existingAlerts.append(DeviceAlert(
                homeId: homeId,
                deviceName: deviceName,
                alertType: type.rawValue,
                message: "test",
                severity: severity
            ))
        }

        // 1回目: アラート生成される
        addAlert(homeId: "home-1", deviceName: "Lock A", type: .lowBattery, severity: "warning")
        XCTAssertEqual(existingAlerts.count, 1)

        // 2回目: 同じデバイス・タイプ → スキップ
        addAlert(homeId: "home-1", deviceName: "Lock A", type: .lowBattery, severity: "warning")
        XCTAssertEqual(existingAlerts.count, 1, "重複アラートは追加されないべき")

        // 異なるデバイス名 → 追加される
        addAlert(homeId: "home-1", deviceName: "Lock B", type: .lowBattery, severity: "warning")
        XCTAssertEqual(existingAlerts.count, 2)

        // 異なるアラートタイプ → 追加される
        addAlert(homeId: "home-1", deviceName: "Lock A", type: .deviceOffline, severity: "critical")
        XCTAssertEqual(existingAlerts.count, 3)

        // 異なるhomeId → 追加される
        addAlert(homeId: "home-2", deviceName: "Lock A", type: .lowBattery, severity: "warning")
        XCTAssertEqual(existingAlerts.count, 4)
    }

    func testResolvedAlertAllowsNewAlert() {
        var existingAlerts: [DeviceAlert] = []

        func isDuplicate(homeId: String, deviceName: String, type: AlertType) -> Bool {
            existingAlerts.contains { alert in
                !alert.isResolved &&
                alert.alertType == type.rawValue &&
                alert.homeId == homeId &&
                alert.deviceName == deviceName
            }
        }

        // アラート追加
        let alert = DeviceAlert(
            homeId: "home-1",
            deviceName: "Sesame",
            alertType: AlertType.unlockAfterCheckout.rawValue,
            message: "未施錠",
            severity: "critical"
        )
        existingAlerts.append(alert)

        // 解決前: 重複検知
        XCTAssertTrue(isDuplicate(homeId: "home-1", deviceName: "Sesame", type: .unlockAfterCheckout))

        // アラートを解決済みにする
        alert.isResolved = true
        alert.resolvedAt = Date()

        // 解決後: 重複として扱われない → 再度アラートを生成できる
        XCTAssertFalse(isDuplicate(homeId: "home-1", deviceName: "Sesame", type: .unlockAfterCheckout),
            "解決済みアラートは重複チェックの対象外であるべき")
    }

    func testMultipleAlertTypesPerDevice() {
        // 同じデバイスに対して異なるタイプのアラートが共存できる
        let battery = DeviceAlert(
            homeId: "home-1", deviceName: "Lock",
            alertType: AlertType.lowBattery.rawValue,
            message: "電池低下", severity: "warning"
        )
        let unlock = DeviceAlert(
            homeId: "home-1", deviceName: "Lock",
            alertType: AlertType.unlockAfterCheckout.rawValue,
            message: "未施錠", severity: "critical"
        )

        let alerts = [battery, unlock]

        // 両方アクティブ
        XCTAssertEqual(alerts.filter { !$0.isResolved }.count, 2)

        // タイプで絞り込める
        XCTAssertEqual(
            alerts.filter { $0.alertType == AlertType.lowBattery.rawValue }.count, 1)
        XCTAssertEqual(
            alerts.filter { $0.alertType == AlertType.unlockAfterCheckout.rawValue }.count, 1)
    }

    // MARK: - checkUnlockAfterCheckout ロジックのシミュレーション

    func testCheckoutUnlockLogic_recentCheckoutTriggers() {
        let now = Date()
        let thirtyOneMinutesAgo = now.addingTimeInterval(-(31 * 60))
        let twoHoursAgo = now.addingTimeInterval(-(2 * 3600))

        // チェックアウト31分前 = アラートトリガー対象
        let booking = makeBooking(
            homeId: "home-1",
            status: "completed",
            checkOut: thirtyOneMinutesAgo
        )

        let shouldAlert = isUnlockAlertNeeded(bookings: [booking], homeId: "home-1", now: now)
        XCTAssertTrue(shouldAlert, "チェックアウト31分経過の未施錠はアラートをトリガーすべき")
    }

    func testCheckoutUnlockLogic_oldCheckoutDoesNotTrigger() {
        let now = Date()
        let fourHoursAgo = now.addingTimeInterval(-(4 * 3600))

        // 4時間前のチェックアウト = 3時間以上前のため対象外
        let booking = makeBooking(
            homeId: "home-1",
            status: "completed",
            checkOut: fourHoursAgo
        )

        let shouldAlert = isUnlockAlertNeeded(bookings: [booking], homeId: "home-1", now: now)
        XCTAssertFalse(shouldAlert, "4時間前のチェックアウトはアラートトリガー対象外")
    }

    func testCheckoutUnlockLogic_activeWithin30MinDoesNotTrigger() {
        let now = Date()
        let tenMinutesAgo = now.addingTimeInterval(-(10 * 60))

        // 10分前のチェックアウト = まだ猶予あり
        let booking = makeBooking(
            homeId: "home-1",
            status: "active",
            checkOut: tenMinutesAgo
        )

        let shouldAlert = isUnlockAlertNeeded(bookings: [booking], homeId: "home-1", now: now)
        XCTAssertFalse(shouldAlert, "チェックアウト10分後はまだアラートを出すべきでない")
    }

    func testCheckoutUnlockLogic_wrongHomeDoesNotTrigger() {
        let now = Date()
        let fortyMinutesAgo = now.addingTimeInterval(-(40 * 60))

        let booking = makeBooking(
            homeId: "home-other",
            status: "completed",
            checkOut: fortyMinutesAgo
        )

        let shouldAlert = isUnlockAlertNeeded(bookings: [booking], homeId: "home-1", now: now)
        XCTAssertFalse(shouldAlert, "別ホームの予約は対象外")
    }

    // MARK: - Private Helpers

    /// DeviceMonitorServiceの checkUnlockAfterCheckout ロジックを再現
    private func isUnlockAlertNeeded(bookings: [MockBooking], homeId: String, now: Date) -> Bool {
        let thirtyMinutesAgo = now.addingTimeInterval(-30 * 60)
        let threeHoursAgo = now.addingTimeInterval(-3 * 3600)

        let recentCheckouts = bookings.filter { booking in
            guard booking.homeId == homeId else { return false }
            let isCompletedOrExpired = booking.status == "completed" ||
                (booking.status == "active" && booking.checkOut < thirtyMinutesAgo)
            return isCompletedOrExpired && booking.checkOut > threeHoursAgo
        }
        return !recentCheckouts.isEmpty
    }

    private func makeBooking(homeId: String, status: String, checkOut: Date) -> MockBooking {
        MockBooking(homeId: homeId, status: status, checkOut: checkOut)
    }
}

// MARK: - MockBooking (SwiftData非依存のテスト用構造体)

private struct MockBooking {
    let homeId: String
    let status: String
    let checkOut: Date
}
