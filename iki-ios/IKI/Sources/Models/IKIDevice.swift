import Foundation
import SwiftData

// MARK: - IKIDevice (SwiftData)
// SwiftData永続化用モデル (ローカルキャッシュ)

@Model
final class IKIDevice {
    var deviceId: String
    var deviceType: String
    var familyToken: String
    var lastSeenMinutesAgo: Int
    var streakDays: Int
    var acsPct: Int
    var statusRaw: String
    var spo2: Int?
    var heartRate: Int?

    init(deviceId: String = "", deviceType: String = "lite", familyToken: String = "",
         lastSeenMinutesAgo: Int = 0, streakDays: Int = 0, acsPct: Int = 0,
         statusRaw: String = "active", spo2: Int? = nil, heartRate: Int? = nil) {
        self.deviceId = deviceId
        self.deviceType = deviceType
        self.familyToken = familyToken
        self.lastSeenMinutesAgo = lastSeenMinutesAgo
        self.streakDays = streakDays
        self.acsPct = acsPct
        self.statusRaw = statusRaw
        self.spo2 = spo2
        self.heartRate = heartRate
    }
}

// MARK: - IKIDeviceData
// APIレスポンス (GET /api/v1/family/{family_token}/status) にマッピングされるCodableモデル

struct IKIDeviceData: Identifiable, Codable {
    let id: String           // device_id (UUIDまたは固有識別子)
    let deviceType: String   // "lite" (小型クリップ型) または "band" (リストバンド型)
    let familyToken: String  // 家族グループトークン
    var lastSeenMinutesAgo: Int   // 最後にオンラインになってから経過した分数
    var streakDays: Int           // 連続安否確認日数
    var acsPct: Int               // Activity Confidence Score: 0-100 (活動信頼度)
    var status: DeviceStatus      // デバイスの現在ステータス
    var lastEvent: SafetyEvent?   // 直近の安否イベント
    var recentEvents: [SafetyEvent] // 過去のイベント一覧
    var spo2: Int?                // 血中酸素飽和度 (%)
    var heartRate: Int?           // 心拍数 (bpm)

    // MARK: - CodingKeys
    enum CodingKeys: String, CodingKey {
        case id
        case deviceType       = "device_type"
        case familyToken      = "family_token"
        case lastSeenMinutesAgo = "last_seen_minutes_ago"
        case streakDays       = "streak_days"
        case acsPct           = "acs_pct"
        case status
        case lastEvent        = "last_event"
        case recentEvents     = "recent_events"
        case spo2
        case heartRate        = "heart_rate"
    }
}

// MARK: - DeviceStatus
// デバイスのステータス区分 (重要度順: active < quiet < check < alert)

enum DeviceStatus: String, Codable {
    case active  // 正常: 最近活動を検知
    case quiet   // 静穏: やや時間が経過
    case check   // 要確認: 長時間活動なし
    case alert   // 警報: 緊急状態または長期未確認

    /// ステータスに対応するカラー名
    var colorName: String {
        switch self {
        case .active: return "ikiSuccess"
        case .quiet:  return "ikiWarn"
        case .check:  return "iki"
        case .alert:  return "ikiDanger"
        }
    }

    /// ステータスの日本語ラベル
    var label: String {
        switch self {
        case .active: return "大丈夫"
        case .quiet:  return "静穏中"
        case .check:  return "確認中..."
        case .alert:  return "警報!"
        }
    }

    /// ステータスの詳細説明
    var description: String {
        switch self {
        case .active: return "最近活動を確認しています"
        case .quiet:  return "しばらく活動がありません"
        case .check:  return "長時間活動が検出されていません"
        case .alert:  return "緊急確認が必要です"
        }
    }

    /// パルスアニメーションを表示するかどうか
    var shouldPulse: Bool {
        switch self {
        case .active: return true
        case .alert:  return true
        default:      return false
        }
    }
}

// MARK: - SafetyEvent
// 安否確認イベント (動き検知、SOS、充電など)

struct SafetyEvent: Identifiable, Codable {
    var id: UUID = UUID()
    let type: String       // イベント種別
    let ts: TimeInterval   // UNIXタイムスタンプ (秒)

    enum CodingKeys: String, CodingKey {
        case type, ts
    }

    /// 「N分前」「N時間前」「N日前」形式の相対時刻ラベル
    var dateLabel: String {
        let elapsed = Date().timeIntervalSince1970 - ts
        switch elapsed {
        case ..<60:
            return "たった今"
        case 60..<3600:
            let minutes = Int(elapsed / 60)
            return "\(minutes)分前"
        case 3600..<86400:
            let hours = Int(elapsed / 3600)
            return "\(hours)時間前"
        default:
            let days = Int(elapsed / 86400)
            return "\(days)日前"
        }
    }

    /// イベント種別に対応するSF Symbolアイコン名
    var icon: String {
        switch type {
        case "motion":            return "figure.walk"
        case "sos":               return "sos.circle.fill"
        case "charge_start":      return "bolt.circle.fill"
        case "charge_end":        return "bolt.slash.circle"
        case "heartbeat":         return "heart.fill"
        case "inactivity_alert":  return "exclamationmark.triangle.fill"
        case "wake":              return "sunrise.fill"
        case "sleep":             return "moon.fill"
        case "fall_detected":     return "figure.fall"
        case "spo2_low":          return "drop.fill"
        case "wifi_connected":    return "wifi"
        case "wifi_disconnected": return "wifi.slash"
        default:                  return "circle.fill"
        }
    }

    /// イベント種別の日本語説明
    var description: String {
        switch type {
        case "motion":            return "動きを検知しました"
        case "sos":               return "SOSが発信されました"
        case "charge_start":      return "充電を開始しました"
        case "charge_end":        return "充電が完了しました"
        case "heartbeat":         return "心拍データを取得しました"
        case "inactivity_alert":  return "長時間の無活動を検出しました"
        case "wake":              return "起床を検知しました"
        case "sleep":             return "就寝を検知しました"
        case "fall_detected":     return "転倒の可能性を検出しました"
        case "spo2_low":          return "血中酸素が低下しています"
        case "wifi_connected":    return "Wi-Fiに接続しました"
        case "wifi_disconnected": return "Wi-Fiから切断しました"
        default:                  return type.replacingOccurrences(of: "_", with: " ")
        }
    }
}
