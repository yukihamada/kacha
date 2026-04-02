import SwiftUI
import SwiftData

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

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var sentMessages: [SentMessage]

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var suggestions: [ReplySuggestion] = []
    @State private var showSuggestions = false
    @State private var isGeneratingSuggestions = false
    @State private var showSubscriptionPrompt = false
    @ObservedObject private var subscription = SubscriptionManager.shared
    @AppStorage("geminiApiKey") private var geminiApiKey = ""

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

    /// Past sent messages for this home (used for suggestion generation)
    private var homeSentMessages: [SentMessage] {
        sentMessages.filter { $0.homeId == home.id }
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

                        if showSuggestions && (isGeneratingSuggestions || !suggestions.isEmpty) {
                            suggestionBar
                        }

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
            .sheet(isPresented: $showSubscriptionPrompt) {
                SubscriptionView()
            }
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
            Text("下の入力欄からメッセージを送信できます")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
    }

    // MARK: - Message Bubble

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isSent {
                Spacer(minLength: 60)
            } else {
                // Guest avatar
                Text(String(booking.guestName.prefix(1)))
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.kachaAccent.opacity(0.7))
                    .clipShape(Circle())
            }

            VStack(alignment: message.isSent ? .trailing : .leading, spacing: 3) {
                // Sender label
                Text(message.isSent ? "あなた" : booking.guestName)
                    .font(.caption2.bold())
                    .foregroundColor(message.isSent ? .kacha.opacity(0.7) : .kachaAccent.opacity(0.7))

                if let subject = message.subject, !subject.isEmpty {
                    Text(subject)
                        .font(.caption2)
                        .foregroundColor(message.isSent ? .kacha.opacity(0.5) : .secondary)
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

                // Timestamp + sent indicator
                HStack(spacing: 4) {
                    Text(dateFormatter.string(from: message.timestamp))
                    if message.isSent {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
            }

            if !message.isSent {
                Spacer(minLength: 60)
            } else {
                // Host avatar
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.kacha.opacity(0.6))
            }
        }
    }

    // MARK: - Smart Reply Suggestions

    private var suggestionBar: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundColor(.kacha)
                Text("返信候補")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showSuggestions = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if isGeneratingSuggestions {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.kacha)
                        .scaleEffect(0.8)
                    Text("AI生成中...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions) { suggestion in
                            suggestionCard(suggestion)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(Color.kachaBg)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func suggestionCard(_ suggestion: ReplySuggestion) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                inputText = suggestion.text
                showSuggestions = false
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if suggestion.source == .history {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 8))
                            .foregroundColor(.kacha.opacity(0.8))
                    } else if suggestion.source == .ai {
                        Image(systemName: "sparkle")
                            .font(.system(size: 8))
                            .foregroundColor(.kacha.opacity(0.8))
                    }
                    Text(suggestion.label)
                        .font(.caption2.bold())
                        .foregroundColor(.kacha)
                }

                Text(suggestion.text)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(width: 180, alignment: .leading)
            .background(Color.kacha.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.kacha.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            // Suggestion toggle button
            Button {
                if showSuggestions {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showSuggestions = false
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showSuggestions = true
                    }
                    Task { await generateSuggestions() }
                }
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .foregroundColor(showSuggestions ? .kacha : .secondary)
                    .frame(width: 32, height: 32)
            }

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

    // MARK: - Suggestion Generation

    private func generateSuggestions() async {
        // Find the last guest (non-sent) message to base suggestions on
        let lastGuestMessage = messages.last(where: { !$0.isSent })?.text ?? ""

        // AI返信はProプラン以上で利用可能（Freeプランではキーワード候補のみ）
        if !geminiApiKey.isEmpty && !subscription.isPro {
            await MainActor.run { showSubscriptionPrompt = true }
            // Fall back to keyword-based suggestions
            suggestions = ReplySuggestionService.suggest(
                incomingMessage: lastGuestMessage,
                guestName: booking.guestName,
                booking: (checkIn: booking.checkIn, checkOut: booking.checkOut, nights: booking.nights),
                pastMessages: homeSentMessages
            )
            return
        }

        // Try Gemini AI first if API key is configured
        if !geminiApiKey.isEmpty {
            isGeneratingSuggestions = true
            let aiSuggestions = await GeminiReplyService.generateReplies(
                guestMessage: lastGuestMessage,
                guestName: booking.guestName,
                home: home,
                booking: booking,
                pastMessages: homeSentMessages,
                apiKey: geminiApiKey
            )
            isGeneratingSuggestions = false
            suggestions = aiSuggestions
        } else {
            // Fall back to keyword-based suggestions
            suggestions = ReplySuggestionService.suggest(
                incomingMessage: lastGuestMessage,
                guestName: booking.guestName,
                booking: (checkIn: booking.checkIn, checkOut: booking.checkOut, nights: booking.nights),
                pastMessages: homeSentMessages
            )
        }
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

            // Auto-show suggestions if the last message is from guest
            if let last = messages.last, !last.isSent {
                withAnimation(.easeOut(duration: 0.3)) {
                    showSuggestions = true
                }
                await generateSuggestions()
            }
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

        // Hide suggestions after sending
        withAnimation(.easeOut(duration: 0.2)) {
            showSuggestions = false
        }

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

            // Save to SentMessage history for future suggestions
            let lastGuestMessage = messages.last(where: { !$0.isSent })?.text ?? ""
            let category = ReplySuggestionService.categorize(lastGuestMessage)
            let record = SentMessage(
                homeId: home.id,
                bookingId: booking.id,
                guestName: booking.guestName,
                text: sentText,
                inReplyTo: lastGuestMessage,
                category: category
            )
            modelContext.insert(record)
            try? modelContext.save()

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
}
