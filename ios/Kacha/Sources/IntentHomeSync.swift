import Foundation
import SwiftData

// MARK: - IntentHomeSync
// SwiftDataのHome変更をIntentHomeStoreのUserDefaultsキャッシュに同期する。
// アプリ起動時・物件編集後に呼び出すことで、App IntentsからSwiftDataを
// 直接参照しなくても最新の認証情報を利用できる。
//
// 使用例:
//   IntentHomeSync.sync(homes: homes)  // ContentViewのonChangeなどで呼ぶ

enum IntentHomeSync {

    /// SwiftDataから取得したHomeリストをIntentHomeStoreに書き込む
    static func sync(homes: [Home]) {
        let summaries = homes.map { home in
            IntentHomeStore.HomeSummary(
                id: home.id,
                name: home.name,
                switchBotToken: home.switchBotToken,
                switchBotSecret: home.switchBotSecret,
                hueBridgeIP: home.hueBridgeIP,
                hueUsername: home.hueUsername,
                sesameApiKey: home.sesameApiKey,
                sesameDeviceUUIDs: home.sesameDeviceUUIDs,
                doorCode: home.doorCode
            )
        }
        IntentHomeStore.save(summaries)

        // AppShortcutsの物件一覧をSiriに通知（追加・削除時に更新される）
        KachaShortcuts.updateAppShortcutParameters()
    }
}
