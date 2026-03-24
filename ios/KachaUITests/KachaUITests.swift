import XCTest

final class KachaUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    // MARK: - Onboarding

    func testOnboardingFlow() {
        // First page should show "カチャ"
        XCTAssertTrue(app.staticTexts["カチャ"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["開いた、ウェルカム。"].exists)

        // Check Amazon links exist
        XCTAssertTrue(app.staticTexts["対応デバイスを揃える"].exists)

        // Tap next
        app.buttons["次へ"].tap()
        sleep(1)

        // Second page - share
        XCTAssertTrue(app.staticTexts["安全にシェア"].waitForExistence(timeout: 3))

        // Tap next
        app.buttons["次へ"].tap()
        sleep(1)

        // Third page - name input
        XCTAssertTrue(app.staticTexts["はじめましょう"].waitForExistence(timeout: 3))

        // Enter name and complete
        let textField = app.textFields.firstMatch
        textField.tap()
        textField.typeText("テストハウス")

        app.buttons["はじめる"].tap()
        sleep(2)

        // Should see home screen
        XCTAssertTrue(app.staticTexts["テストハウス"].waitForExistence(timeout: 5))
        print("✅ Onboarding flow completed")
    }

    // MARK: - Tab Navigation

    func testTabNavigation() {
        // Complete onboarding first if needed
        if app.staticTexts["カチャ"].exists && app.buttons["次へ"].exists {
            // Skip onboarding
            app.buttons["次へ"].tap()
            sleep(1)
            app.buttons["次へ"].tap()
            sleep(1)
            let textField = app.textFields.firstMatch
            textField.tap()
            textField.typeText("Test")
            app.buttons["はじめる"].tap()
            sleep(2)
        }

        // Test tab bar
        XCTAssertTrue(app.tabBars.buttons["ホーム"].exists)
        XCTAssertTrue(app.tabBars.buttons["カレンダー"].exists)
        XCTAssertTrue(app.tabBars.buttons["設定"].exists)

        // Switch to calendar
        app.tabBars.buttons["カレンダー"].tap()
        sleep(1)
        XCTAssertTrue(app.navigationBars["カレンダー"].exists)

        // Switch to settings
        app.tabBars.buttons["設定"].tap()
        sleep(1)
        XCTAssertTrue(app.navigationBars["設定"].exists)

        print("✅ Tab navigation works")
    }

    // MARK: - Settings

    func testSettingsPage() {
        skipOnboarding()
        app.tabBars.buttons["設定"].tap()
        sleep(1)

        // Check sections exist
        XCTAssertTrue(app.staticTexts["ホーム"].exists)
        XCTAssertTrue(app.staticTexts["営業モード"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["ヘルプ"].exists)
        XCTAssertTrue(app.staticTexts["対応デバイスを購入"].exists)
        print("✅ Settings sections visible")
    }

    // MARK: - Quick Actions

    func testQuickActionsGrid() {
        skipOnboarding()

        // Default mode: 光熱費 and 家の管理
        XCTAssertTrue(app.staticTexts["光熱費"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["家の管理"].exists)

        // Guest card should NOT be visible in normal mode
        XCTAssertFalse(app.staticTexts["ゲストカード"].exists)
        print("✅ Quick actions grid shows correct items for normal mode")
    }

    // MARK: - Helpers

    private func skipOnboarding() {
        if app.staticTexts["カチャ"].exists && app.buttons["次へ"].exists {
            app.buttons["次へ"].tap()
            sleep(1)
            app.buttons["次へ"].tap()
            sleep(1)
            let textField = app.textFields.firstMatch
            textField.tap()
            textField.typeText("Test")
            app.buttons["はじめる"].tap()
            sleep(2)
        }
    }
}
