import SwiftUI

// MARK: - Chat Message Model

private struct ChatMessage: Identifiable {
    let id: String
    let text: String
    let isSent: Bool
    let timestamp: Date
    let subject: String?
}

// MARK: - GuestChatView

struct GuestChatView: View {
    let booking: Booking
    let home: Home

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showTemplates = false
    @Environment(\.dismiss) private var dismiss

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private var bookId: Int {
        let raw = booking.externalId.hasPrefix("beds24-")
            ? String(booking.externalId.dropFirst(7))
            : booking.externalId
        return Int(raw) ?? 0
    }

    private var quickReplies: [(label: String, message: String)] {
        [
            ("チェックイン案内", buildCheckInMessage()),
            ("Wi-Fi情報", buildWiFiMessage()),
            ("チェックアウト案内", buildCheckOutMessage()),
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    if isLoading {
                        Spacer()
                        ProgressView()
                            .tint(.kacha)
                        Spacer()
                    } else if let error = errorMessage {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.kachaWarn)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button("再読み込み") { Task { await loadMessages() } }
                                .font(.subheadline.bold())
                                .foregroundColor(.kacha)
                        }
                        .padding()
                        Spacer()
                    } else {
                        messageListView
                        Divider().background(Color.kachaCardBorder)
                        quickReplyBar
                        inputBar
                    }
                }
            }
            .navigationTitle(booking.guestName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kachaBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(.kacha)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await loadMessages() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.kacha)
                    }
                }
            }
            .task { await loadMessages() }
        }
    }

    // MARK: - Message List

    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if messages.isEmpty {
                        emptyStateView
                            .padding(.top, 60)
                    }

                    ForEach(messages) { msg in
                        messageBubble(msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text("メッセージはまだありません")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("下のテンプレートからメッセージを送信できます")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
    }

    // MARK: - Message Bubble

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.isSent { Spacer(minLength: 60) }

            VStack(alignment: message.isSent ? .trailing : .leading, spacing: 4) {
                if let subject = message.subject, !subject.isEmpty {
                    Text(subject)
                        .font(.caption2.bold())
                        .foregroundColor(message.isSent ? .black.opacity(0.6) : .secondary)
                }

                Text(message.text)
                    .font(.subheadline)
                    .foregroundColor(message.isSent ? .black : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.isSent ? Color.kacha : Color.kachaCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(
                                message.isSent ? Color.clear : Color.kachaCardBorder,
                                lineWidth: 1
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Text(dateFormatter.string(from: message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }

            if !message.isSent { Spacer(minLength: 60) }
        }
    }

    // MARK: - Quick Reply Bar

    private var quickReplyBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickReplies, id: \.label) { reply in
                    Button {
                        inputText = reply.message
                    } label: {
                        Text(reply.label)
                            .font(.caption.bold())
                            .foregroundColor(.kacha)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.kacha.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color.kacha.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.kachaBg)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("メッセージを入力...", text: $inputText, axis: .vertical)
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.kachaCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.kachaCardBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .lineLimit(1...5)

            Button {
                Task { await sendMessage() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(canSend ? .kacha : .secondary.opacity(0.3))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.kachaBg)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    // MARK: - API Actions

    private func loadMessages() async {
        isLoading = true
        errorMessage = nil

        guard bookId > 0 else {
            errorMessage = "予約IDが見つかりません"
            isLoading = false
            return
        }

        guard !home.beds24RefreshToken.isEmpty else {
            errorMessage = "Beds24が接続されていません"
            isLoading = false
            return
        }

        do {
            let token = try await Beds24Client.shared.getToken(refreshToken: home.beds24RefreshToken)
            let raw = try await Beds24Client.shared.getBookingMessages(bookingId: bookId, token: token)
            messages = raw.enumerated().map { index, dict in
                parseMessage(dict, index: index)
            }
            .sorted { $0.timestamp < $1.timestamp }
        } catch {
            errorMessage = "メッセージの読み込みに失敗しました"
            #if DEBUG
            print("[GuestChat] Load error: \(error)")
            #endif
        }

        isLoading = false
    }

    private func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, bookId > 0 else { return }

        isSending = true
        let sentText = text
        inputText = ""

        do {
            let token = try await Beds24Client.shared.getToken(refreshToken: home.beds24RefreshToken)
            try await Beds24Client.shared.sendBookingMessage(
                bookingId: bookId,
                message: sentText,
                token: token
            )

            let newMsg = ChatMessage(
                id: UUID().uuidString,
                text: sentText,
                isSent: true,
                timestamp: Date(),
                subject: nil
            )
            messages.append(newMsg)

            try? await Task.sleep(for: .seconds(1))
            await loadMessages()
        } catch {
            inputText = sentText
            errorMessage = "送信に失敗しました"
            #if DEBUG
            print("[GuestChat] Send error: \(error)")
            #endif
        }

        isSending = false
    }

    // MARK: - Message Parsing

    private func parseMessage(_ dict: [String: Any], index: Int) -> ChatMessage {
        let text = (dict["message"] as? String)
            ?? (dict["body"] as? String)
            ?? (dict["text"] as? String)
            ?? ""
        let subject = dict["subject"] as? String

        let isSent: Bool
        if let from = dict["from"] as? String {
            isSent = from.lowercased() != "guest"
        } else if let direction = dict["direction"] as? String {
            isSent = direction.lowercased() == "out" || direction.lowercased() == "sent"
        } else if let type = dict["type"] as? String {
            isSent = type.lowercased() != "received"
        } else {
            isSent = true
        }

        var timestamp = Date()
        if let dateStr = (dict["date"] as? String) ?? (dict["dateTime"] as? String) ?? (dict["created"] as? String) {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = isoFormatter.date(from: dateStr) {
                timestamp = parsed
            } else {
                isoFormatter.formatOptions = [.withInternetDateTime]
                if let parsed = isoFormatter.date(from: dateStr) {
                    timestamp = parsed
                } else {
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    if let parsed = df.date(from: dateStr) {
                        timestamp = parsed
                    }
                }
            }
        }

        let id = (dict["id"] as? Int).map(String.init)
            ?? (dict["id"] as? String)
            ?? "\(index)-\(text.prefix(20).hashValue)"

        return ChatMessage(id: id, text: text, isSent: isSent, timestamp: timestamp, subject: subject)
    }

    // MARK: - Template Builders

    private func buildCheckInMessage() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ja_JP")
        fmt.dateStyle = .medium

        let address = home.address.isEmpty ? "" : "\n住所: \(home.address)"
        let doorCode = home.doorCode.isEmpty ? "" : "\nドアコード: \(home.doorCode)"

        return """
        \(booking.guestName) 様

        チェックインのご案内です。

        チェックイン: \(fmt.string(from: booking.checkIn))
        チェックアウト: \(fmt.string(from: booking.checkOut))\(address)\(doorCode)

        ご不明な点がございましたらお気軽にご連絡ください。
        """
    }

    private func buildWiFiMessage() -> String {
        let pw = home.wifiPassword.isEmpty ? "(未設定)" : home.wifiPassword
        return """
        \(booking.guestName) 様

        Wi-Fi情報をお知らせします。

        パスワード: \(pw)

        接続にお困りの場合はご連絡ください。
        """
    }

    private func buildCheckOutMessage() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ja_JP")
        fmt.dateStyle = .medium

        return """
        \(booking.guestName) 様

        ご滞在ありがとうございました。
        チェックアウトは \(fmt.string(from: booking.checkOut)) です。

        お帰りの際は以下をお願いします:
        ・ドアの施錠
        ・ゴミは所定の場所へ
        ・忘れ物のご確認

        またのご利用をお待ちしております。
        """
    }
}
