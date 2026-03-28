import ActivityKit
import Foundation

// MARK: - LiveActivityManager

/// KAGIスマートロックのLive Activity（Dynamic Island / Lock Screen）を管理するサービス。
/// ActivityContentのAPIはiOS 16.2+。プロジェクトのdeploymentTarget(iOS 17)なので
/// @available(iOS 16.2, *)でラップし、実行時チェックはareActivitiesEnabledのみ行う。
@available(iOS 16.2, *)
@MainActor
final class LiveActivityManager: ObservableObject {

    static let shared = LiveActivityManager()

    // MARK: State

    @Published private(set) var isActivityRunning = false

    private var currentActivity: Activity<KachaLockAttributes>? {
        Activity<KachaLockAttributes>.activities.first
    }

    // MARK: - Public API

    /// Live Activityを開始する。既存のActivityがあれば状態を更新して再利用する。
    /// - Parameters:
    ///   - homeName: 物件名（表示用）
    ///   - homeId: 物件ID（DeepLink用）
    ///   - isLocked: 現在の施錠状態
    ///   - battery: バッテリー残量 (0–100)。不明の場合は -1
    ///   - nextGuest: 次ゲスト情報 (guestName, checkInDate)
    func startLockActivity(
        homeName: String,
        homeId: String,
        isLocked: Bool,
        battery: Int = -1,
        nextGuest: (name: String, checkIn: Date)? = nil
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivity] Activities are not enabled on this device.")
            return
        }

        // 既に動いているActivityがあれば状態更新のみ
        if currentActivity != nil {
            updateLockState(isLocked: isLocked, battery: battery, nextGuest: nextGuest)
            return
        }

        let attributes = KachaLockAttributes(homeName: homeName, homeId: homeId)
        let state = KachaLockAttributes.ContentState(
            isLocked: isLocked,
            batteryLevel: battery,
            nextGuestName: nextGuest?.name,
            nextCheckIn: nextGuest?.checkIn,
            lastUpdated: Date()
        )

        do {
            let content = ActivityContent(
                state: state,
                staleDate: Calendar.current.date(byAdding: .minute, value: 30, to: Date())
            )
            let activity = try Activity<KachaLockAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            isActivityRunning = true
            print("[LiveActivity] Started: id=\(activity.id)")
        } catch {
            print("[LiveActivity] Failed to start: \(error.localizedDescription)")
        }
    }

    /// 施錠状態とバッテリーを更新する。SwitchBot操作後に呼ぶ。
    func updateLockState(
        isLocked: Bool,
        battery: Int = -1,
        nextGuest: (name: String, checkIn: Date)? = nil
    ) {
        guard let activity = currentActivity else { return }

        let newState = KachaLockAttributes.ContentState(
            isLocked: isLocked,
            batteryLevel: battery,
            nextGuestName: nextGuest?.name,
            nextCheckIn: nextGuest?.checkIn,
            lastUpdated: Date()
        )
        let content = ActivityContent(
            state: newState,
            staleDate: Calendar.current.date(byAdding: .minute, value: 30, to: Date())
        )

        Task {
            await activity.update(content)
            print("[LiveActivity] Updated: isLocked=\(isLocked), battery=\(battery)")
        }
    }

    /// Live Activityを終了する。アプリがフォアグラウンドに戻った時などに呼ぶ。
    func endActivity() {
        guard let activity = currentActivity else { return }

        Task {
            // 終了後5秒間はLock Screenに残す
            let finalState = activity.content.state
            let dismissDate = Calendar.current.date(byAdding: .second, value: 5, to: Date()) ?? Date()
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .after(dismissDate)
            )
            await MainActor.run {
                isActivityRunning = false
            }
            print("[LiveActivity] Ended.")
        }
    }

    /// アプリがバックグラウンドに入った時に呼ぶ。
    /// KachaAppの `.onChange(of: scenePhase)` でscenePhase == .backgroundの時に呼び出す。
    func handleScenePhaseBackground(
        homeName: String,
        homeId: String,
        isLocked: Bool,
        battery: Int = -1,
        nextGuest: (name: String, checkIn: Date)? = nil
    ) {
        startLockActivity(
            homeName: homeName,
            homeId: homeId,
            isLocked: isLocked,
            battery: battery,
            nextGuest: nextGuest
        )
    }

    /// アプリがフォアグラウンドに戻った時に呼ぶ。
    func handleScenePhaseActive() {
        endActivity()
    }
}
