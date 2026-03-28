import XCTest
@testable import Kacha

// MARK: - AutomationEngine Unit Tests
// AutomationScene/Trigger/Action の静的データと Codable を検証する。
// 実際のデバイス制御（SwitchBot/Hue/Sesame）には接続しない。

final class AutomationEngineTests: XCTestCase {

    // MARK: - AutomationScene Presets

    func testPresetCount() {
        XCTAssertEqual(AutomationScene.presets.count, 5,
            "There should be exactly 5 preset scenes")
        print("AutomationScene preset count OK: \(AutomationScene.presets.count)")
    }

    func testPresetIDs() {
        let ids = AutomationScene.presets.map(\.id)
        XCTAssertTrue(ids.contains("welcome"), "Missing 'welcome' scene")
        XCTAssertTrue(ids.contains("checkout"), "Missing 'checkout' scene")
        XCTAssertTrue(ids.contains("sleep"), "Missing 'sleep' scene")
        XCTAssertTrue(ids.contains("outing"), "Missing 'outing' scene")
        XCTAssertTrue(ids.contains("party"), "Missing 'party' scene")
        // ID の重複がないこと
        XCTAssertEqual(ids.count, Set(ids).count, "Scene IDs must be unique")
        print("AutomationScene preset IDs OK: \(ids.joined(separator: ", "))")
    }

    func testPresetActionCounts() {
        let presets = AutomationScene.presets
        let welcome  = presets.first { $0.id == "welcome" }
        let checkout = presets.first { $0.id == "checkout" }
        let sleep    = presets.first { $0.id == "sleep" }
        let outing   = presets.first { $0.id == "outing" }
        let party    = presets.first { $0.id == "party" }

        XCTAssertEqual(welcome?.actions.count,  2, "welcome: lightsOn + setAC")
        XCTAssertEqual(checkout?.actions.count, 3, "checkout: lightsOff + lockDoor + setAC")
        XCTAssertEqual(sleep?.actions.count,    2, "sleep: lightsOn(dim) + lockDoor")
        XCTAssertEqual(outing?.actions.count,   2, "outing: allOff + lockDoor")
        XCTAssertEqual(party?.actions.count,    1, "party: lightsOn(bright)")

        print("AutomationScene action counts: welcome=\(welcome?.actions.count ?? -1) checkout=\(checkout?.actions.count ?? -1) sleep=\(sleep?.actions.count ?? -1) outing=\(outing?.actions.count ?? -1) party=\(party?.actions.count ?? -1)")
    }

    func testPresetsHaveNonEmptyDisplayNames() {
        for scene in AutomationScene.presets {
            XCTAssertFalse(scene.name.isEmpty, "Scene '\(scene.id)' has empty name")
            XCTAssertFalse(scene.icon.isEmpty, "Scene '\(scene.id)' has empty icon")
        }
        print("AutomationScene names and icons all non-empty OK")
    }

    func testPresetsAreEnabledByDefault() {
        for scene in AutomationScene.presets {
            XCTAssertTrue(scene.isEnabled, "Preset '\(scene.id)' should be enabled by default")
        }
        print("AutomationScene all presets enabled by default OK")
    }

    // MARK: - AutomationTrigger

    func testTriggerRawValues() {
        XCTAssertEqual(AutomationTrigger.checkIn.rawValue,  "checkIn")
        XCTAssertEqual(AutomationTrigger.checkOut.rawValue, "checkOut")
        XCTAssertEqual(AutomationTrigger.manual.rawValue,   "manual")
        XCTAssertEqual(AutomationTrigger.schedule.rawValue, "schedule")
        print("AutomationTrigger rawValues OK")
    }

    func testTriggerRoundTripFromRawValue() {
        for trigger in AutomationTrigger.allCases {
            let reconstructed = AutomationTrigger(rawValue: trigger.rawValue)
            XCTAssertEqual(reconstructed, trigger,
                "RawValue round-trip failed for \(trigger.rawValue)")
        }
        print("AutomationTrigger rawValue round-trip OK")
    }

    func testTriggerDisplayNames() {
        XCTAssertFalse(AutomationTrigger.checkIn.displayName.isEmpty)
        XCTAssertFalse(AutomationTrigger.checkOut.displayName.isEmpty)
        XCTAssertFalse(AutomationTrigger.manual.displayName.isEmpty)
        XCTAssertFalse(AutomationTrigger.schedule.displayName.isEmpty)
        print("AutomationTrigger displayNames all non-empty OK")
    }

    func testTriggerIcons() {
        for trigger in AutomationTrigger.allCases {
            XCTAssertFalse(trigger.icon.isEmpty, "Icon missing for trigger \(trigger.rawValue)")
        }
        print("AutomationTrigger icons OK")
    }

    func testAllCasesCount() {
        XCTAssertEqual(AutomationTrigger.allCases.count, 4)
        print("AutomationTrigger allCases count = \(AutomationTrigger.allCases.count)")
    }

    // MARK: - AutomationAction Codable Round-Trip

    func testLightsOnCodable() throws {
        let action = AutomationAction.lightsOn(brightness: 75, colorTemp: 3000)
        let encoded = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(AutomationAction.self, from: encoded)
        XCTAssertEqual(decoded, action)
        print("AutomationAction.lightsOn Codable OK")
    }

    func testLightsOffCodable() throws {
        let action = AutomationAction.lightsOff
        let encoded = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(AutomationAction.self, from: encoded)
        XCTAssertEqual(decoded, action)
        print("AutomationAction.lightsOff Codable OK")
    }

    func testLockDoorCodable() throws {
        let action = AutomationAction.lockDoor
        let encoded = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(AutomationAction.self, from: encoded)
        XCTAssertEqual(decoded, action)
        print("AutomationAction.lockDoor Codable OK")
    }

    func testUnlockDoorCodable() throws {
        let action = AutomationAction.unlockDoor
        let encoded = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(AutomationAction.self, from: encoded)
        XCTAssertEqual(decoded, action)
        print("AutomationAction.unlockDoor Codable OK")
    }

    func testSetACCodable() throws {
        let action = AutomationAction.setAC(temp: 24, mode: "cool")
        let encoded = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(AutomationAction.self, from: encoded)
        XCTAssertEqual(decoded, action)
        print("AutomationAction.setAC Codable OK")
    }

    func testAllOffCodable() throws {
        let action = AutomationAction.allOff
        let encoded = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(AutomationAction.self, from: encoded)
        XCTAssertEqual(decoded, action)
        print("AutomationAction.allOff Codable OK")
    }

    func testAllActionsCodable() throws {
        let actions: [AutomationAction] = [
            .lightsOn(brightness: 100, colorTemp: 4000),
            .lightsOff,
            .lockDoor,
            .unlockDoor,
            .setAC(temp: 22, mode: "heat"),
            .allOff
        ]
        let encoded = try JSONEncoder().encode(actions)
        let decoded = try JSONDecoder().decode([AutomationAction].self, from: encoded)
        XCTAssertEqual(decoded, actions)
        print("AutomationAction all-actions array Codable OK (\(actions.count) actions)")
    }

    // MARK: - AutomationAction Display

    func testActionDisplayNames() {
        let cases: [AutomationAction] = [
            .lightsOn(brightness: 50, colorTemp: 2700),
            .lightsOff,
            .lockDoor,
            .unlockDoor,
            .setAC(temp: 26, mode: "off"),
            .allOff
        ]
        for action in cases {
            XCTAssertFalse(action.displayName.isEmpty,
                "displayName should not be empty for \(action)")
            XCTAssertFalse(action.icon.isEmpty,
                "icon should not be empty for \(action)")
        }
        print("AutomationAction displayNames and icons all non-empty OK")
    }

    func testLightsOnDisplayNameContainsValues() {
        let action = AutomationAction.lightsOn(brightness: 80, colorTemp: 3500)
        XCTAssertTrue(action.displayName.contains("80"),
            "lightsOn displayName should include brightness")
        XCTAssertTrue(action.displayName.contains("3500"),
            "lightsOn displayName should include colorTemp")
    }

    func testSetACDisplayNameContainsValues() {
        let action = AutomationAction.setAC(temp: 23, mode: "cool")
        XCTAssertTrue(action.displayName.contains("23"),
            "setAC displayName should include temperature")
        XCTAssertTrue(action.displayName.contains("cool"),
            "setAC displayName should include mode")
    }

    // MARK: - SceneColor Gradient

    func testSceneColorGradients() {
        let colors: [AutomationScene.SceneColor] = [.amber, .teal, .indigo, .rose, .purple]
        for color in colors {
            XCTAssertEqual(color.gradient.count, 2,
                "\(color.rawValue) should have exactly 2 gradient colors")
            for hex in color.gradient {
                XCTAssertTrue(hex.hasPrefix("#"),
                    "\(color.rawValue) gradient color '\(hex)' should be a hex string")
            }
        }
        print("SceneColor gradients OK for \(colors.count) colors")
    }

    // MARK: - Preset Trigger Assignments

    func testWelcomeSceneTriggerIsCheckIn() {
        let welcome = AutomationScene.presets.first { $0.id == "welcome" }
        XCTAssertEqual(welcome?.trigger, .checkIn)
        print("welcome scene trigger = checkIn OK")
    }

    func testCheckoutSceneTriggerIsCheckOut() {
        let checkout = AutomationScene.presets.first { $0.id == "checkout" }
        XCTAssertEqual(checkout?.trigger, .checkOut)
        print("checkout scene trigger = checkOut OK")
    }

    func testManualScenes() {
        let manualIds = ["sleep", "outing", "party"]
        for id in manualIds {
            let scene = AutomationScene.presets.first { $0.id == id }
            XCTAssertEqual(scene?.trigger, .manual,
                "Scene '\(id)' should have manual trigger")
        }
        print("Manual trigger scenes OK: \(manualIds.joined(separator: ", "))")
    }
}
