import AppIntents

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
        return .result(dialog: "SwitchBotの設定が必要です。カチャアプリから操作してください。")
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
        return .result(dialog: "SwitchBotの設定が必要です。カチャアプリから操作してください。")
    }
}

// MARK: - App Shortcuts

struct KachaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LockDoorIntent(),
            phrases: [
                "カチャで施錠",
                "ドアを施錠して",
                "Lock the door with \(.applicationName)"
            ],
            shortTitle: "施錠する",
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: UnlockDoorIntent(),
            phrases: [
                "カチャで解錠",
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
