import WidgetKit
import Foundation

// MARK: - Shared Data Model

struct BookingItem: Codable {
    let guestName: String
    let timeLabel: String
    let platform: String
    let checkInDate: TimeInterval   // Date().timeIntervalSince1970
}

struct TodayEvent: Codable {
    let guestName: String
    let propertyName: String
    let time: String
    let eventType: String  // "checkin" or "checkout"
    let platform: String
}

struct KachaWidgetEntry: TimelineEntry {
    let date: Date
    let homeName: String
    let isLocked: Bool
    let todayCheckIns: Int
    let todayCheckOuts: Int
    let monthNights: Int
    let propertyCount: Int
    let vacantCount: Int
    let todayEvents: [TodayEvent]
    let nextGuestName: String
    let nextCheckInLabel: String
    let nextPlatform: String
    let nextCheckInDate: Date?
    let upcomingBookings: [BookingItem]
    /// true when deviceId/token are not configured (show hint)
    let isUnconfigured: Bool
}

// MARK: - Provider

struct KachaWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> KachaWidgetEntry {
        KachaWidgetEntry(
            date: Date(),
            homeName: "私の家",
            isLocked: true,
            todayCheckIns: 2,
            todayCheckOuts: 1,
            monthNights: 18,
            propertyCount: 3,
            vacantCount: 1,
            todayEvents: [
                TodayEvent(guestName: "山田 太郎 様", propertyName: "IKI", time: "16:00", eventType: "checkin", platform: "Airbnb"),
                TodayEvent(guestName: "田中 花子 様", propertyName: "NAMI", time: "10:00", eventType: "checkout", platform: "じゃらん")
            ],
            nextGuestName: "山田 太郎 様",
            nextCheckInLabel: "16:00 チェックイン",
            nextPlatform: "Airbnb",
            nextCheckInDate: Calendar.current.date(byAdding: .hour, value: 3, to: Date()),
            upcomingBookings: [
                BookingItem(guestName: "山田 太郎 様", timeLabel: "16:00 チェックイン", platform: "Airbnb", checkInDate: Date().timeIntervalSince1970 + 3600 * 3),
                BookingItem(guestName: "田中 花子 様", timeLabel: "10:00 チェックアウト", platform: "じゃらん", checkInDate: Date().timeIntervalSince1970 + 3600 * 18),
                BookingItem(guestName: "鈴木 一郎 様", timeLabel: "明日 15:00 チェックイン", platform: "Booking.com", checkInDate: Date().timeIntervalSince1970 + 3600 * 23)
            ],
            isUnconfigured: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (KachaWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KachaWidgetEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh every 15 minutes; if a check-in is imminent, refresh sooner
        var nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        if let checkIn = entry.nextCheckInDate, checkIn > Date() {
            let minutesToCheckIn = checkIn.timeIntervalSinceNow / 60
            if minutesToCheckIn < 60 {
                // Refresh every 5 minutes when check-in is within the hour
                nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
            }
        }
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    // MARK: - Private

    private func loadEntry() -> KachaWidgetEntry {
        let d = UserDefaults(suiteName: WidgetSharedDefaults.suiteName)

        let homeName = d?.string(forKey: WidgetSharedDefaults.homeNameKey) ?? "KAGI"
        let isLocked = d?.bool(forKey: WidgetSharedDefaults.isLockedKey) ?? true
        let checkIns = d?.integer(forKey: WidgetSharedDefaults.todayCheckInsKey) ?? 0
        let checkOuts = d?.integer(forKey: WidgetSharedDefaults.todayCheckOutsKey) ?? 0
        let monthNights = d?.integer(forKey: WidgetSharedDefaults.monthNightsKey) ?? 0
        let propertyCount = d?.integer(forKey: WidgetSharedDefaults.propertyCountKey) ?? 0
        let vacantCount = d?.integer(forKey: WidgetSharedDefaults.vacantCountKey) ?? 0
        let nextGuestName = d?.string(forKey: WidgetSharedDefaults.nextGuestNameKey) ?? ""
        let nextCheckInLabel = d?.string(forKey: WidgetSharedDefaults.nextCheckInLabelKey) ?? ""
        let nextPlatform = d?.string(forKey: WidgetSharedDefaults.nextPlatformKey) ?? ""
        let nextCheckInTs = d?.double(forKey: WidgetSharedDefaults.nextCheckInKey) ?? 0
        let nextCheckInDate = nextCheckInTs > 0 ? Date(timeIntervalSince1970: nextCheckInTs) : nil

        var upcomingBookings: [BookingItem] = []
        if let data = d?.data(forKey: WidgetSharedDefaults.upcomingBookingsKey),
           let decoded = try? JSONDecoder().decode([BookingItem].self, from: data) {
            upcomingBookings = decoded
        }

        var todayEvents: [TodayEvent] = []
        if let data = d?.data(forKey: WidgetSharedDefaults.todayEventsKey),
           let decoded = try? JSONDecoder().decode([TodayEvent].self, from: data) {
            todayEvents = decoded
        }

        let token = d?.string(forKey: WidgetSharedDefaults.switchBotTokenKey) ?? ""
        let deviceId = d?.string(forKey: WidgetSharedDefaults.lockDeviceIdKey) ?? ""
        let isUnconfigured = token.isEmpty || deviceId.isEmpty

        return KachaWidgetEntry(
            date: Date(),
            homeName: homeName,
            isLocked: isLocked,
            todayCheckIns: checkIns,
            todayCheckOuts: checkOuts,
            monthNights: monthNights,
            propertyCount: propertyCount,
            vacantCount: vacantCount,
            todayEvents: todayEvents,
            nextGuestName: nextGuestName,
            nextCheckInLabel: nextCheckInLabel,
            nextPlatform: nextPlatform,
            nextCheckInDate: nextCheckInDate,
            upcomingBookings: upcomingBookings,
            isUnconfigured: isUnconfigured
        )
    }
}
