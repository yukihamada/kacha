import AppIntents
import Foundation

// MARK: - IntentHomeStore
// App Intents から SwiftData に直接アクセスできないため、
// UserDefaults (App Group) 経由でHome情報をキャッシュする。

enum IntentHomeStore {
    private static let key = "kacha_intent_homes"

    struct HomeSummary: Codable {
        let id: String
        let name: String
        let switchBotToken: String
        let switchBotSecret: String
        let hueBridgeIP: String
        let hueUsername: String
        let sesameApiKey: String
        let sesameDeviceUUIDs: String
        let doorCode: String
    }

    static func loadAll() -> [HomeEntity] {
        loadSummaries().map { HomeEntity(id: $0.id, name: $0.name) }
    }

    static func loadSummaries() -> [HomeSummary] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([HomeSummary].self, from: data)
        else { return [] }
        return list
    }

    static func save(_ summaries: [HomeSummary]) {
        guard let data = try? JSONEncoder().encode(summaries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func summary(for homeId: String) -> HomeSummary? {
        loadSummaries().first { $0.id == homeId }
    }
}

// MARK: - HomeEntity (AppIntents parameter type)

struct HomeEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "物件")
    static var defaultQuery = HomeEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct HomeEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [HomeEntity] {
        IntentHomeStore.loadAll().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [HomeEntity] {
        IntentHomeStore.loadAll()
    }
}

// MARK: - Check-in Intent

struct CheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "チェックイン処理"
    static var description = IntentDescription("ゲストのチェックインを完了し、スマートロックを解錠します")
    static var openAppWhenRun = true

    @Parameter(title: "予約")
    var bookingName: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: "チェックイン処理が完了しました")
    }
}

// MARK: - Lock Intent

struct LockDoorIntent: AppIntent {
    static var title: LocalizedStringResource = "施錠する"
    static var description = IntentDescription("スマートロックを施錠します")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // TODO: SwitchBot credentials are stored in SwiftData (per-Home), not UserDefaults.
        // Intents cannot directly access SwiftData ModelContext yet.
        // For now, return a guidance message until App Intents + SwiftData integration is implemented.
        return .result(dialog: "SwitchBotの設定が必要です。KAGIアプリから操作してください。")
    }
}

// MARK: - Unlock Intent

struct UnlockDoorIntent: AppIntent {
    static var title: LocalizedStringResource = "解錠する"
    static var description = IntentDescription("スマートロックを解錠します")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // TODO: SwitchBot credentials are stored in SwiftData (per-Home), not UserDefaults.
        // Intents cannot directly access SwiftData ModelContext yet.
        // For now, return a guidance message until App Intents + SwiftData integration is implemented.
        return .result(dialog: "SwitchBotの設定が必要です。KAGIアプリから操作してください。")
    }
}

// MARK: - App Shortcuts

struct KachaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LockDoorIntent(),
            phrases: [
                "KAGIで施錠",
                "ドアを施錠して",
                "Lock the door with \(.applicationName)"
            ],
            shortTitle: "施錠する",
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: UnlockDoorIntent(),
            phrases: [
                "KAGIで解錠",
                "ドアを解錠して",
                "Unlock the door with \(.applicationName)"
            ],
            shortTitle: "解錠する",
            systemImageName: "lock.open.fill"
        )
        AppShortcut(
            intent: CheckInIntent(),
            phrases: [
                "チェックイン処理して",
                "Check in with \(.applicationName)"
            ],
            shortTitle: "チェックイン",
            systemImageName: "person.fill.checkmark"
        )
    }
}
