import Foundation

/// Calls Gemini 2.5 Flash API to generate AI-powered reply suggestions
/// for guest messages in vacation rental context.
struct GeminiReplyService {

    private static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

    /// Generate 3 AI reply suggestions using Gemini API.
    /// Falls back to keyword-based suggestions on any error.
    static func generateReplies(
        guestMessage: String,
        guestName: String,
        home: Home,
        booking: Booking,
        pastMessages: [SentMessage],
        apiKey: String
    ) async -> [ReplySuggestion] {
        guard !apiKey.isEmpty, !guestMessage.isEmpty else {
            return fallback(guestMessage: guestMessage, guestName: guestName, booking: booking, pastMessages: pastMessages)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"

        let checkInStr = dateFormatter.string(from: booking.checkIn)
        let checkOutStr = dateFormatter.string(from: booking.checkOut)

        // Build recent message history (last 5)
        let recentHistory = pastMessages
            .sorted { $0.sentAt > $1.sentAt }
            .prefix(5)
            .map { "Host: \($0.text)" }
            .joined(separator: "\n")

        let systemPrompt = """
        You are a vacation rental host assistant. Generate exactly 3 reply options in the same language as the guest message.

        Property info:
        - Name: \(home.name)
        - Address: \(home.address)
        - Door code: \(home.doorCode)
        - WiFi password: \(home.wifiPassword)
        - Check-in: \(checkInStr)
        - Check-out: \(checkOutStr)
        - Guest name: \(guestName)
        - Nights: \(booking.nights)
        - Platform: \(booking.platformLabel)

        \(recentHistory.isEmpty ? "" : "Recent host replies for tone reference:\n\(recentHistory)")

        Rules:
        - Be polite, helpful, and concise
        - Include relevant property details (door code, wifi, etc.) when the guest asks about them
        - Each reply should have a different tone/length
        - Respond in JSON array format only, no markdown

        Output format (strict JSON array):
        [{"label":"丁寧","text":"..."},{"label":"簡潔","text":"..."},{"label":"詳しく","text":"..."}]
        """

        let userPrompt = "Guest message from \(guestName): \(guestMessage)"

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": "\(systemPrompt)\n\n\(userPrompt)"]
                    ]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.7
            ]
        ]

        guard let url = URL(string: "\(endpoint)?key=\(apiKey)") else {
            return fallback(guestMessage: guestMessage, guestName: guestName, booking: booking, pastMessages: pastMessages)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                #if DEBUG
                print("[GeminiReply] HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                if let body = String(data: data, encoding: .utf8) {
                    print("[GeminiReply] Response: \(body.prefix(500))")
                }
                #endif
                return fallback(guestMessage: guestMessage, guestName: guestName, booking: booking, pastMessages: pastMessages)
            }

            return try parseResponse(data, guestMessage: guestMessage, guestName: guestName, booking: booking, pastMessages: pastMessages)
        } catch {
            #if DEBUG
            print("[GeminiReply] Error: \(error)")
            #endif
            return fallback(guestMessage: guestMessage, guestName: guestName, booking: booking, pastMessages: pastMessages)
        }
    }

    // MARK: - Response Parsing

    private static func parseResponse(
        _ data: Data,
        guestMessage: String,
        guestName: String,
        booking: Booking,
        pastMessages: [SentMessage]
    ) throws -> [ReplySuggestion] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String
        else {
            return fallback(guestMessage: guestMessage, guestName: guestName, booking: booking, pastMessages: pastMessages)
        }

        // Parse the JSON array from Gemini's response
        guard let jsonData = text.data(using: .utf8),
              let suggestions = try JSONSerialization.jsonObject(with: jsonData) as? [[String: String]]
        else {
            return fallback(guestMessage: guestMessage, guestName: guestName, booking: booking, pastMessages: pastMessages)
        }

        let category = ReplySuggestionService.categorize(guestMessage)
        let result = suggestions.compactMap { item -> ReplySuggestion? in
            guard let label = item["label"], let replyText = item["text"] else { return nil }
            return ReplySuggestion(label: label, text: replyText, category: category, source: .ai)
        }

        guard !result.isEmpty else {
            return fallback(guestMessage: guestMessage, guestName: guestName, booking: booking, pastMessages: pastMessages)
        }

        return Array(result.prefix(3))
    }

    // MARK: - Fallback

    private static func fallback(
        guestMessage: String,
        guestName: String,
        booking: Booking,
        pastMessages: [SentMessage]
    ) -> [ReplySuggestion] {
        ReplySuggestionService.suggest(
            incomingMessage: guestMessage,
            guestName: guestName,
            booking: (checkIn: booking.checkIn, checkOut: booking.checkOut, nights: booking.nights),
            pastMessages: pastMessages
        )
    }
}
