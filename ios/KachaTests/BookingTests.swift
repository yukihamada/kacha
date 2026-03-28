import XCTest
@testable import Kacha

final class BookingTests: XCTestCase {

    // MARK: - Helpers

    private func date(daysFromNow offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date())!
    }

    // MARK: - mapBeds24Status

    func testMapBeds24Status_Cancelled() {
        let status = Booking.mapBeds24Status("cancelled", checkIn: date(daysFromNow: 1), checkOut: date(daysFromNow: 3))
        XCTAssertEqual(status, "cancelled")
    }

    func testMapBeds24Status_Active() {
        // checkIn = yesterday, checkOut = tomorrow -> currently active
        let status = Booking.mapBeds24Status("confirmed", checkIn: date(daysFromNow: -1), checkOut: date(daysFromNow: 1))
        XCTAssertEqual(status, "active", "Guest currently staying should be 'active'")
    }

    func testMapBeds24Status_Completed() {
        // checkOut = yesterday -> completed
        let status = Booking.mapBeds24Status("confirmed", checkIn: date(daysFromNow: -3), checkOut: date(daysFromNow: -1))
        XCTAssertEqual(status, "completed", "Past checkout should be 'completed'")
    }

    func testMapBeds24Status_Confirmed() {
        // Future dates, status = confirmed
        let status = Booking.mapBeds24Status("confirmed", checkIn: date(daysFromNow: 5), checkOut: date(daysFromNow: 8))
        XCTAssertEqual(status, "confirmed", "Future confirmed booking should be 'confirmed'")
    }

    func testMapBeds24Status_Request() {
        let status = Booking.mapBeds24Status("request", checkIn: date(daysFromNow: 5), checkOut: date(daysFromNow: 8))
        XCTAssertEqual(status, "request")
    }

    // MARK: - Computed Properties

    func testGuestCount() {
        let booking = Booking(
            guestName: "Test Guest",
            checkIn: date(daysFromNow: 1),
            checkOut: date(daysFromNow: 4),
            numAdults: 4,
            numChildren: 2
        )
        XCTAssertEqual(booking.guestCount, 6, "4 adults + 2 children = 6")
    }

    func testNights() {
        let checkIn = date(daysFromNow: 0)
        let checkOut = date(daysFromNow: 3)
        let booking = Booking(
            guestName: "Test Guest",
            checkIn: checkIn,
            checkOut: checkOut
        )
        XCTAssertEqual(booking.nights, 3, "3-day span should be 3 nights")
    }

    func testNights_SingleNight() {
        let booking = Booking(
            guestName: "Test Guest",
            checkIn: date(daysFromNow: 0),
            checkOut: date(daysFromNow: 1)
        )
        XCTAssertEqual(booking.nights, 1)
    }

    func testPlatformLabel() {
        let booking = Booking(guestName: "Test", platform: "airbnb", checkIn: Date(), checkOut: Date())
        XCTAssertEqual(booking.platformLabel, "Airbnb")

        let direct = Booking(guestName: "Test", platform: "direct", checkIn: Date(), checkOut: Date())
        XCTAssertEqual(direct.platformLabel, "直接")
    }
}
