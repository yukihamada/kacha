import XCTest
@testable import Kacha

final class ModelTests: XCTestCase {

    // MARK: - ManualSection Templates

    func testManualSectionTemplates() {
        XCTAssertGreaterThanOrEqual(ManualSection.templates.count, 14)
        let keys = ManualSection.templates.map(\.key)
        XCTAssertTrue(keys.contains("welcome"))
        XCTAssertTrue(keys.contains("wifi"))
        XCTAssertTrue(keys.contains("checkin"))
        XCTAssertTrue(keys.contains("checkout"))
        XCTAssertTrue(keys.contains("rules"))
        print("✅ \(ManualSection.templates.count) manual templates available")
    }

    // MARK: - ChecklistItem Defaults

    func testDefaultChecklists() {
        XCTAssertGreaterThan(ChecklistItem.defaultCheckIn.count, 0)
        XCTAssertGreaterThan(ChecklistItem.defaultCheckOut.count, 0)
        print("✅ Checklist defaults: \(ChecklistItem.defaultCheckIn.count) check-in, \(ChecklistItem.defaultCheckOut.count) check-out")
    }

    // MARK: - MaintenanceTask

    func testMaintenanceDefaults() {
        XCTAssertGreaterThan(MaintenanceTask.defaults.count, 0)
        for (name, days) in MaintenanceTask.defaults {
            XCTAssertGreaterThan(days, 0)
            XCTAssertFalse(name.isEmpty)
        }
        print("✅ \(MaintenanceTask.defaults.count) maintenance task defaults")
    }

    // MARK: - UtilityRecord Categories

    func testUtilityCategories() {
        XCTAssertEqual(UtilityRecord.categories.count, 3)
        let keys = UtilityRecord.categories.map(\.key)
        XCTAssertTrue(keys.contains("electric"))
        XCTAssertTrue(keys.contains("gas"))
        XCTAssertTrue(keys.contains("water"))
        print("✅ Utility categories: \(keys.joined(separator: ", "))")
    }

    // MARK: - NearbyPlace Categories

    func testNearbyPlaceCategories() {
        XCTAssertGreaterThanOrEqual(NearbyPlace.categoryInfo.count, 6)
        print("✅ \(NearbyPlace.categoryInfo.count) place categories")
    }

    // MARK: - ActivityLog Icons

    func testActivityLogIcons() {
        let actions = ["lock", "unlock", "light_on", "light_off", "scene", "share_create", "share_revoke"]
        for action in actions {
            let log = ActivityLog(homeId: "test", action: action, detail: "test")
            XCTAssertFalse(log.icon.isEmpty, "Icon for \(action) should not be empty")
            XCTAssertFalse(log.iconColor.isEmpty)
        }
        print("✅ All activity log action icons defined")
    }

    // MARK: - Beds24 Booking Parsing

    func testBeds24BookingPlatformKey() {
        let airbnb = Beds24Booking(id: 1, propertyId: nil, roomId: nil, status: nil, arrival: nil, departure: nil, firstName: nil, lastName: nil, email: nil, phone: nil, numAdult: nil, numChild: nil, price: nil, commission: nil, referer: nil, channel: "airbnb", apiReference: nil, comments: nil, notes: nil)
        XCTAssertEqual(airbnb.platformKey, "airbnb")

        let booking = Beds24Booking(id: 2, propertyId: nil, roomId: nil, status: nil, arrival: nil, departure: nil, firstName: nil, lastName: nil, email: nil, phone: nil, numAdult: nil, numChild: nil, price: nil, commission: nil, referer: nil, channel: "booking", apiReference: nil, comments: nil, notes: nil)
        XCTAssertEqual(booking.platformKey, "booking")

        let jalan = Beds24Booking(id: 3, propertyId: nil, roomId: nil, status: nil, arrival: nil, departure: nil, firstName: nil, lastName: nil, email: nil, phone: nil, numAdult: nil, numChild: nil, price: nil, commission: nil, referer: nil, channel: "jalan", apiReference: nil, comments: nil, notes: nil)
        XCTAssertEqual(jalan.platformKey, "jalan")
        print("✅ Platform key detection works")
    }
}
