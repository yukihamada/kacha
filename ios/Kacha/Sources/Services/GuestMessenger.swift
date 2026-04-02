import Foundation
import SwiftData
import UserNotifications

// MARK: - Guest Auto-Messenger
// チェックイン前日にゲストにWiFi/ドアコード等を自動送信
// デフォルトOFF — 設定で有効化

struct GuestMessenger {

    /// チェックイン前日の予約を見つけて通知をスケジュール
    static func scheduleMessages(context: ModelContext, home: Home) {
        guard UserDefaults.standard.bool(forKey: "autoGuestMessage_\(home.id)") else { return }

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let startOfTomorrow = Calendar.current.startOfDay(for: tomorrow)
        let endOfTomorrow = Calendar.current.date(byAdding: .day, value: 1, to: startOfTomorrow) ?? tomorrow
        let homeId = home.id

        var descriptor = FetchDescriptor<Booking>()
        descriptor.predicate = #Predicate<Booking> { booking in
            booking.homeId == homeId &&
            booking.status == "upcoming" &&
            booking.checkIn >= startOfTomorrow &&
            booking.checkIn < endOfTomorrow
        }
        let tomorrowBookings = (try? context.fetch(descriptor)) ?? []

        for booking in tomorrowBookings {
            let message = buildMessage(home: home, booking: booking)

            // Local notification to owner to review/send
            let content = UNMutableNotificationContent()
            content.title = "ゲストメッセージ準備完了"
            content.body = "\(booking.guestName)様へのチェックイン案内を確認してください"
            content.sound = .default
            content.userInfo = [
                "type": "guest_message",
                "bookingId": booking.id,
                "message": message
            ]

            // Schedule for 18:00 today
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = 18
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "guest-msg-\(booking.id)",
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)

            // Auto-send guest card link via Beds24 if enabled
            if UserDefaults.standard.bool(forKey: "autoGuestCard_\(home.id)") {
                Task {
                    await sendGuestCardIfNeeded(home: home, booking: booking, context: context)
                }
            }
        }
    }

    // MARK: - Auto-send Guest Card via Beds24

    /// ゲストカードリンクを生成してBeds24メッセージで自動送信
    /// - 既に送信済みの予約はスキップ
    /// - Beds24連携が必要（refreshToken + externalId）
    static func sendGuestCardIfNeeded(home: Home, booking: Booking, context: ModelContext) async {
        let sentKey = "guestCardSent_\(booking.id)"
        guard !UserDefaults.standard.bool(forKey: sentKey) else { return }
        guard !home.beds24RefreshToken.isEmpty else { return }
        guard booking.externalId.hasPrefix("beds24-") else { return }

        // Extract Beds24 booking ID from externalId (format: "beds24-12345")
        let beds24IdStr = String(booking.externalId.dropFirst("beds24-".count))
        guard let beds24BookingId = Int(beds24IdStr) else { return }

        do {
            // 1. Create E2E encrypted guest card share link
            let shareData = HomeShareData(
                name: home.name,
                address: home.address,
                role: "guest",
                switchBotToken: "",
                switchBotSecret: "",
                hueBridgeIP: "",
                hueUsername: "",
                sesameApiKey: "",
                sesameDeviceUUIDs: "",
                qrioApiKey: "",
                qrioDeviceIds: "",
                doorCode: home.doorCode,
                wifiPassword: home.wifiPassword,
                beds24ApiKey: nil,
                beds24RefreshToken: nil
            )

            let ownerToken = UUID().uuidString
            let validFrom = Calendar.current.startOfDay(for: booking.checkIn.addingTimeInterval(-86400)) // 1 day before check-in
            let expiresAt = booking.checkOut.addingTimeInterval(86400) // 1 day after check-out

            let result = try await ShareClient.createShare(
                data: shareData,
                validFrom: validFrom,
                expiresAt: expiresAt,
                ownerToken: ownerToken
            )

            let key = result.encryptionKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? result.encryptionKey
            let shareLink = "https://kagi.pasha.run/join?t=\(result.token)#\(key)"

            // Save share record locally
            let record = ShareRecord(
                homeId: home.id,
                homeName: home.name,
                recipientName: booking.guestName,
                role: "guest",
                token: result.token,
                ownerToken: ownerToken,
                validFrom: validFrom,
                expiresAt: expiresAt
            )
            context.insert(record)
            try? context.save()

            // 2. Build multi-language message
            let message = buildGuestCardMessage(guestName: booking.guestName, shareLink: shareLink)

            // 3. Send via Beds24 messaging API
            let token = try await Beds24Client.shared.getToken(refreshToken: home.beds24RefreshToken)
            try await Beds24Client.shared.sendBookingMessage(
                bookingId: beds24BookingId,
                message: message,
                subject: "Check-in Guide / チェックインのご案内",
                token: token
            )

            // 4. Mark as sent
            UserDefaults.standard.set(true, forKey: sentKey)

            // Log activity
            ActivityLogger.log(
                context: context,
                homeId: home.id,
                action: "guest_card_sent",
                detail: "\(booking.guestName)にゲストカードリンクを自動送信"
            )

            // Notify owner
            let content = UNMutableNotificationContent()
            content.title = "ゲストカード送信完了"
            content.body = "\(booking.guestName)様にチェックイン案内リンクを送信しました"
            content.sound = .default
            content.userInfo = ["type": "guest_card_sent", "bookingId": booking.id]
            let request = UNNotificationRequest(
                identifier: "guest-card-sent-\(booking.id)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)

            #if DEBUG
            print("[GuestMessenger] Sent guest card link to \(booking.guestName) for booking \(booking.externalId)")
            #endif
        } catch {
            #if DEBUG
            print("[GuestMessenger] Failed to send guest card: \(error)")
            #endif
            // Notify owner of failure
            let content = UNMutableNotificationContent()
            content.title = "ゲストカード送信失敗"
            content.body = "\(booking.guestName)様への送信に失敗しました: \(error.localizedDescription)"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "guest-card-fail-\(booking.id)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    /// ゲストの名前/メールパターンから言語を推定し、多言語メッセージを生成
    static func buildGuestCardMessage(guestName: String, shareLink: String) -> String {
        let lang = detectGuestLanguage(guestName: guestName)

        switch lang {
        case "en":
            return """
            Dear \(guestName),

            Here is your check-in guide with WiFi and door code information:
            \(shareLink)

            If you have any questions, please don't hesitate to contact us.
            We look forward to welcoming you!
            """
        case "zh":
            return """
            尊敬的\(guestName)，

            以下是您的入住指南，包含WiFi和门锁密码信息：
            \(shareLink)

            如有任何疑问，请随时联系我们。
            期待您的到来！
            """
        case "ko":
            return """
            안녕하세요, \(guestName)님,

            WiFi 및 도어 코드 정보가 포함된 체크인 가이드입니다:
            \(shareLink)

            궁금하신 사항이 있으시면 언제든지 연락해 주세요.
            기다리겠습니다!
            """
        default: // ja
            return """
            \(guestName)様

            チェックインのご案内です。下記リンクからWi-Fiやドアコードをご確認いただけます。
            \(shareLink)

            何かご不明な点がございましたらお気軽にご連絡ください。
            お待ちしております。
            """
        }
    }

    /// ゲスト名から言語を推定（ヒューリスティック）
    /// - 漢字のみ（CJK Unified）→ zh
    /// - ハングル含む → ko
    /// - 日本語文字（ひらがな・カタカナ・漢字混在）→ ja
    /// - ASCII中心 → en
    private static func detectGuestLanguage(guestName: String) -> String {
        let name = guestName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "ja" }

        var hasHiragana = false
        var hasKatakana = false
        var hasHangul = false
        var hasCJK = false
        var hasLatin = false

        for scalar in name.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x309F: hasHiragana = true
            case 0x30A0...0x30FF: hasKatakana = true
            case 0xAC00...0xD7AF, 0x1100...0x11FF: hasHangul = true
            case 0x4E00...0x9FFF: hasCJK = true
            case 0x0041...0x007A: hasLatin = true
            default: break
            }
        }

        if hasHangul { return "ko" }
        if hasHiragana || hasKatakana { return "ja" }
        if hasCJK && !hasLatin { return "zh" }
        if hasLatin { return "en" }
        return "ja"
    }

    static func buildMessage(home: Home, booking: Booking) -> String {
        var lines: [String] = []
        lines.append("\(booking.guestName)様")
        lines.append("")
        lines.append("明日のチェックインのご案内です。")
        lines.append("")
        lines.append("【\(home.name)】")
        if !home.address.isEmpty {
            lines.append("住所: \(home.address)")
        }
        lines.append("")
        if !home.doorCode.isEmpty {
            lines.append("ドアコード: \(home.doorCode)")
        }
        if !home.wifiPassword.isEmpty {
            lines.append("Wi-Fi: \(home.wifiPassword)")
        }
        if !home.autolockRoomNumber.isEmpty {
            lines.append("部屋番号: \(home.autolockRoomNumber)")
        }
        lines.append("")
        lines.append("チェックイン: \(booking.checkIn.formatted(date: .abbreviated, time: .omitted))")
        lines.append("")
        lines.append("何かご不明な点がございましたらお気軽にご連絡ください。")
        lines.append("お待ちしております。")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Cleaner Notifier
// チェックアウト時に清掃スタッフに通知
// デフォルトOFF

struct CleanerNotifier {

    static func scheduleCleaningNotifications(context: ModelContext, home: Home) {
        guard UserDefaults.standard.bool(forKey: "autoCleanerNotify_\(home.id)") else { return }

        let today = Date()
        let startOfToday = Calendar.current.startOfDay(for: today)
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? today
        let homeId = home.id

        var descriptor = FetchDescriptor<Booking>()
        descriptor.predicate = #Predicate<Booking> { booking in
            booking.homeId == homeId &&
            booking.status == "active" &&
            booking.checkOut >= startOfToday &&
            booking.checkOut < endOfToday
        }
        let todayCheckouts = (try? context.fetch(descriptor)) ?? []

        for booking in todayCheckouts {
            let content = UNMutableNotificationContent()
            content.title = "清掃依頼 — \(home.name)"
            content.body = "\(booking.guestName)様がチェックアウトしました。清掃をお願いします。"
            content.sound = .default
            content.userInfo = ["type": "cleaning_request", "homeId": home.id]

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: booking.checkOut)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "clean-\(booking.id)",
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)

            // LINE Messaging API で清掃スタッフに通知
            if !home.lineChannelToken.isEmpty && !home.lineGroupId.isEmpty {
                Task {
                    try? await LINEMessagingClient.sendCleaningRequest(home: home, booking: booking)
                }
            }
        }
    }
}
