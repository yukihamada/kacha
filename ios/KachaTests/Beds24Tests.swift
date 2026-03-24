import XCTest
@testable import Kacha

final class Beds24Tests: XCTestCase {

    // MARK: - Authentication Flow

    func testSetupWithInviteCode() async throws {
        // Real invite code test — only run manually
        // To test: paste a fresh invite code from Beds24
        // let code = "YOUR_INVITE_CODE"
        // let refreshToken = try await Beds24Client.shared.setupWithInviteCode(code)
        // XCTAssertFalse(refreshToken.isEmpty)
    }

    func testGetTokenFromRefreshToken() async throws {
        // Use the refreshToken from a previous setup
        let refreshToken = "+kwAGa+2hmGQJjjHSNUlMvuRQmuBOe+LoYES6AsEbZUOKO8vyu39uJ+3g7EU7BNX27juRqj+qXxhK2Z81vN1CiYfl3o4hHLv3Mqj3WCzuPtRI2vDztQOCKIi45OYXTs9p+JEVNSNuYYQebV1aJayI639FZvXSeKHbkS1Kgm8Nsc="
        let token = try await Beds24Client.shared.getToken(refreshToken: refreshToken)
        XCTAssertFalse(token.isEmpty, "Token should not be empty")
        print("✅ Token obtained: \(token.prefix(30))...")
    }

    func testFetchBookings() async throws {
        let refreshToken = "+kwAGa+2hmGQJjjHSNUlMvuRQmuBOe+LoYES6AsEbZUOKO8vyu39uJ+3g7EU7BNX27juRqj+qXxhK2Z81vN1CiYfl3o4hHLv3Mqj3WCzuPtRI2vDztQOCKIi45OYXTs9p+JEVNSNuYYQebV1aJayI639FZvXSeKHbkS1Kgm8Nsc="
        let token = try await Beds24Client.shared.getToken(refreshToken: refreshToken)
        let bookings = try await Beds24Client.shared.fetchBookings(token: token)
        XCTAssertGreaterThan(bookings.count, 0, "Should have at least 1 booking")
        print("✅ Fetched \(bookings.count) bookings")

        // Verify data structure
        if let first = bookings.first {
            XCTAssertGreaterThan(first.effectiveId, 0)
            XCTAssertNotNil(first.arrival)
            XCTAssertNotNil(first.departure)
            print("  First: [\(first.effectiveId)] \(first.guestFullName) | \(first.arrival ?? "") → \(first.departure ?? "") | \(first.platformKey)")
        }
    }

    func testFetchProperties() async throws {
        let refreshToken = "+kwAGa+2hmGQJjjHSNUlMvuRQmuBOe+LoYES6AsEbZUOKO8vyu39uJ+3g7EU7BNX27juRqj+qXxhK2Z81vN1CiYfl3o4hHLv3Mqj3WCzuPtRI2vDztQOCKIi45OYXTs9p+JEVNSNuYYQebV1aJayI639FZvXSeKHbkS1Kgm8Nsc="
        let token = try await Beds24Client.shared.getToken(refreshToken: refreshToken)
        let properties = try await Beds24Client.shared.fetchProperties(token: token)
        XCTAssertGreaterThan(properties.count, 0, "Should have at least 1 property")
        print("✅ Fetched \(properties.count) properties")

        for prop in properties {
            let name = prop["name"] as? String ?? "?"
            let id = prop["id"] as? Int ?? 0
            print("  [\(id)] \(name)")
        }
    }

    func testMultipleTokensFromSameRefreshToken() async throws {
        let refreshToken = "+kwAGa+2hmGQJjjHSNUlMvuRQmuBOe+LoYES6AsEbZUOKO8vyu39uJ+3g7EU7BNX27juRqj+qXxhK2Z81vN1CiYfl3o4hHLv3Mqj3WCzuPtRI2vDztQOCKIi45OYXTs9p+JEVNSNuYYQebV1aJayI639FZvXSeKHbkS1Kgm8Nsc="

        // Get two different tokens
        let token1 = try await Beds24Client.shared.getToken(refreshToken: refreshToken)
        let token2 = try await Beds24Client.shared.getToken(refreshToken: refreshToken)

        XCTAssertNotEqual(token1, token2, "Each call should return a new token")

        // Both should work
        let bookings1 = try await Beds24Client.shared.fetchBookings(token: token1)
        let bookings2 = try await Beds24Client.shared.fetchBookings(token: token2)

        XCTAssertEqual(bookings1.count, bookings2.count, "Both tokens should return same data")
        print("✅ Multiple tokens work concurrently: \(bookings1.count) bookings each")
    }

    // MARK: - Data Parsing

    func testBeds24BookingDecoding() throws {
        let json = """
        {"id":84165159,"propertyId":243406,"status":"new","arrival":"2026-05-05","departure":"2026-05-06","firstName":"康介","lastName":"鈴木","email":"","phone":"818065126396","numAdult":4,"price":76590,"channel":"airbnb","referer":"Airbnb"}
        """.data(using: .utf8)!

        let booking = try JSONDecoder().decode(Beds24Booking.self, from: json)
        XCTAssertEqual(booking.effectiveId, 84165159)
        XCTAssertEqual(booking.guestFullName, "鈴木 康介")
        XCTAssertEqual(booking.arrival, "2026-05-05")
        XCTAssertEqual(booking.departure, "2026-05-06")
        XCTAssertEqual(booking.platformKey, "airbnb")
        XCTAssertEqual(booking.price, 76590)
        print("✅ Booking decoded correctly: \(booking.guestFullName)")
    }
}
