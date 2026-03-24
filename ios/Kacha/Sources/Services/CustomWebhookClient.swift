import Foundation

// MARK: - CustomWebhookClient
// カスタムWebhook / IFTTT / Tuya / Home Assistant など汎用HTTP実行

struct CustomWebhookClient {
    static func execute(integration: DeviceIntegration) async throws {
        let platform = integration.platform

        if platform == "ifttt" {
            try await triggerIFTTT(integration: integration)
        } else if platform == "homeassistant" {
            try await callHomeAssistant(integration: integration)
        } else {
            try await callCustomURL(integration: integration)
        }
    }

    // MARK: - IFTTT Maker Webhook
    static func triggerIFTTT(integration: DeviceIntegration) async throws {
        let key = integration["webhookKey"]
        let event = integration["eventName"]
        guard !key.isEmpty, !event.isEmpty,
              let url = URL(string: "https://maker.ifttt.com/trigger/\(event)/with/key/\(key)")
        else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    }

    // MARK: - Home Assistant REST
    static func callHomeAssistant(integration: DeviceIntegration, entityId: String = "", service: String = "toggle") async throws {
        let base = integration["url"].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let token = integration["token"]
        guard !base.isEmpty, !token.isEmpty else { throw URLError(.badURL) }
        let path = entityId.isEmpty
            ? "\(base)/api/"
            : "\(base)/api/services/\(String(entityId.split(separator: ".").first ?? "homeassistant"))/\(service)"
        guard let url = URL(string: path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = entityId.isEmpty ? "GET" : "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !entityId.isEmpty {
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["entity_id": entityId])
        }
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse).map({ $0.statusCode < 300 }) ?? false else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Generic URL
    static func callCustomURL(integration: DeviceIntegration) async throws {
        let urlStr = integration["actionURL"]
        let method = integration["method"].uppercased().isEmpty ? "POST" : integration["method"].uppercased()
        let bodyStr = integration["body"]
        let token = integration["token"]
        guard !urlStr.isEmpty, let url = URL(string: urlStr) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if !bodyStr.isEmpty { req.httpBody = bodyStr.data(using: .utf8) }
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse).map({ $0.statusCode < 300 }) ?? false else {
            throw URLError(.badServerResponse)
        }
    }
}
