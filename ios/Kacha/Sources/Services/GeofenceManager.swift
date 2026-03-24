import CoreLocation
import UserNotifications

// MARK: - Geofence Manager
// 自宅に近づいたらオートロック解除通知を表示

class GeofenceManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = GeofenceManager()

    private let locationManager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isMonitoring = false
    @Published var lastGeocodeResult: String?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Permission

    func requestPermission() {
        locationManager.requestAlwaysAuthorization()
    }

    // MARK: - Geocode address → coordinates

    func geocodeAddress(_ address: String) async -> CLLocationCoordinate2D? {
        guard !address.isEmpty else { return nil }
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(address)
            if let location = placemarks.first?.location {
                await MainActor.run {
                    lastGeocodeResult = "座標取得成功: \(String(format: "%.4f", location.coordinate.latitude)), \(String(format: "%.4f", location.coordinate.longitude))"
                }
                return location.coordinate
            }
        } catch {
            await MainActor.run {
                lastGeocodeResult = "住所から座標を取得できませんでした"
            }
        }
        return nil
    }

    // MARK: - Register geofence

    func registerGeofence(homeId: String, latitude: Double, longitude: Double, radius: Double) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        guard latitude != 0 && longitude != 0 else { return }

        // Remove existing
        removeGeofence(homeId: homeId)

        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = CLCircularRegion(center: center, radius: min(radius, locationManager.maximumRegionMonitoringDistance), identifier: "kacha-home-\(homeId)")
        region.notifyOnEntry = true
        region.notifyOnExit = false

        locationManager.startMonitoring(for: region)
        isMonitoring = true
    }

    func removeGeofence(homeId: String) {
        let id = "kacha-home-\(homeId)"
        for region in locationManager.monitoredRegions where region.identifier == id {
            locationManager.stopMonitoring(for: region)
        }
        if locationManager.monitoredRegions.isEmpty {
            isMonitoring = false
        }
    }

    func removeAllGeofences() {
        for region in locationManager.monitoredRegions where region.identifier.hasPrefix("kacha-home-") {
            locationManager.stopMonitoring(for: region)
        }
        isMonitoring = false
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix("kacha-home-") else { return }
        sendArrivalNotification()
    }

    // MARK: - Notification

    private func sendArrivalNotification() {
        let content = UNMutableNotificationContent()
        content.title = "おかえりなさい"
        content.body = "オートロックを解除しますか？"
        content.sound = .default
        content.categoryIdentifier = "AUTOLOCK_ARRIVAL"
        content.userInfo = ["type": "autolock_arrival"]

        let request = UNNotificationRequest(
            identifier: "autolock-arrival-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // immediate
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Setup notification actions

    static func registerNotificationCategory() {
        let unlockAction = UNNotificationAction(
            identifier: "UNLOCK_AUTOLOCK",
            title: "オートロック解除",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "AUTOLOCK_ARRIVAL",
            actions: [unlockAction],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
