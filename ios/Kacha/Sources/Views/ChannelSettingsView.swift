import SwiftUI

// MARK: - Channel Settings View
// Manage OTA channels (Airbnb/Booking.com) via Beds24 API.
// Shows connection status, publish toggle, pricing multiplier, cancellation policy.

struct ChannelSettingsView: View {
    let home: Home
    @Environment(\.dismiss) private var dismiss
    @State private var channels: [ChannelInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var airbnbListings: [AirbnbListing] = []

    struct ChannelInfo: Identifiable {
        let id = UUID()
        let channel: String
        var enabled: Bool
        var publish: Bool
        var multiplier: String
        var cancellationPolicy: String
        var instantBook: String
        var roomId: Int
        var listingId: String
        var discount2Day: Int
        var discount7Day: Int
        var discount28Day: Int
    }

    struct AirbnbListing: Identifiable {
        let id: String
        let name: String
        let bedrooms: Int
        let hasAvailability: Bool
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                if isLoading {
                    ProgressView("読み込み中...").foregroundColor(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if let err = errorMessage {
                                Text(err).font(.caption).foregroundColor(.kachaDanger).padding(.horizontal, 16)
                            }

                            ForEach(channels) { ch in
                                channelCard(ch)
                            }

                            if !airbnbListings.isEmpty {
                                KachaCard {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "house.fill").foregroundColor(.kacha)
                                            Text("Airbnbリスティング").font(.subheadline).bold().foregroundColor(.white)
                                        }
                                        ForEach(airbnbListings) { listing in
                                            HStack {
                                                Circle()
                                                    .fill(listing.hasAvailability ? Color.kachaSuccess : Color.kachaDanger)
                                                    .frame(width: 8, height: 8)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(listing.name).font(.caption).foregroundColor(.white).lineLimit(2)
                                                    Text("Bedrooms: \(listing.bedrooms)").font(.caption2).foregroundColor(.secondary)
                                                }
                                                Spacer()
                                            }
                                        }
                                    }
                                    .padding(16)
                                }
                                .padding(.horizontal, 16)
                            }

                            // Help
                            KachaCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "info.circle.fill").foregroundColor(.kachaAccent)
                                        Text("チャネル追加").font(.subheadline).bold().foregroundColor(.white)
                                    }
                                    Text("じゃらん・楽天トラベル・Expedia等の新規チャネル接続はBeds24管理画面から行ってください。")
                                        .font(.caption).foregroundColor(.secondary)
                                    Link(destination: URL(string: "https://beds24.com")!) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.up.right.square").font(.caption)
                                            Text("Beds24管理画面を開く").font(.caption).bold()
                                        }
                                        .foregroundColor(.kachaAccent)
                                    }
                                }
                                .padding(16)
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("チャネル管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
            .task { await loadChannels() }
        }
    }

    // MARK: - Channel Card

    private func channelCard(_ ch: ChannelInfo) -> some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: ch.channel == "airbnb" ? "house.fill" : "building.2.fill")
                        .foregroundColor(ch.channel == "airbnb" ? Color(hex: "FF5A5F") : Color(hex: "003580"))
                    Text(ch.channel == "airbnb" ? "Airbnb" : ch.channel.capitalized)
                        .font(.subheadline).bold().foregroundColor(.white)
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(ch.enabled ? Color.kachaSuccess : Color.kachaDanger).frame(width: 8, height: 8)
                        Text(ch.enabled ? "接続中" : "無効").font(.caption2).foregroundColor(ch.enabled ? .kachaSuccess : .kachaDanger)
                    }
                }

                HStack(spacing: 16) {
                    statPill("公開", ch.publish ? "ON" : "OFF", ch.publish ? .kachaSuccess : .secondary)
                    statPill("倍率", ch.multiplier, .kacha)
                    statPill("キャンセル", ch.cancellationPolicy, .kachaAccent)
                }

                if ch.discount2Day > 0 || ch.discount7Day > 0 || ch.discount28Day > 0 {
                    HStack(spacing: 12) {
                        if ch.discount2Day > 0 { Text("2泊割: \(ch.discount2Day)%").font(.caption2).foregroundColor(.kachaWarn) }
                        if ch.discount7Day > 0 { Text("7泊割: \(ch.discount7Day)%").font(.caption2).foregroundColor(.kachaWarn) }
                        if ch.discount28Day > 0 { Text("28泊割: \(ch.discount28Day)%").font(.caption2).foregroundColor(.kachaWarn) }
                    }
                }

                // Publish toggle
                HStack {
                    Text("Beds24から公開").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button {
                        Task { await togglePublish(ch) }
                    } label: {
                        Text(ch.publish ? "公開中" : "公開する")
                            .font(.caption).bold()
                            .foregroundColor(ch.publish ? .kachaSuccess : .kacha)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background((ch.publish ? Color.kachaSuccess : Color.kacha).opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(16)
        }
        .padding(.horizontal, 16)
    }

    private func statPill(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 12, weight: .bold)).foregroundColor(color)
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
        }
    }

    // MARK: - API

    private func loadChannels() async {
        guard !home.beds24RefreshToken.isEmpty else {
            errorMessage = "Beds24未接続"
            isLoading = false
            return
        }
        do {
            let token = try await Beds24Client.shared.getToken(refreshToken: home.beds24RefreshToken)
            let propId = Int(home.beds24ApiKey) ?? 0

            // Channel settings
            let url = URL(string: "https://beds24.com/api/v2/channels/settings?propertyId=\(propId)")!
            var req = URLRequest(url: url)
            req.addValue(token, forHTTPHeaderField: "token")
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["data"] as? [[String: Any]] {
                var result: [ChannelInfo] = []
                for item in items {
                    guard let channel = item["channel"] as? String else { continue }
                    if channel == "iCalExport" || channel == "iCalImport" { continue }
                    for prop in (item["properties"] as? [[String: Any]]) ?? [] {
                        let mult = prop["multiplier"] as? String ?? "1.0"
                        for room in (prop["roomTypes"] as? [[String: Any]]) ?? [] {
                            result.append(ChannelInfo(
                                channel: channel,
                                enabled: room["enabled"] as? Bool ?? false,
                                publish: room["publish"] as? Bool ?? false,
                                multiplier: mult,
                                cancellationPolicy: room["cancellationPolicy"] as? String ?? "?",
                                instantBook: room["instantBook"] as? String ?? "?",
                                roomId: room["id"] as? Int ?? 0,
                                listingId: (room["airbnbListingId"] ?? room["bookingRoomId"] ?? "") as? String ?? "",
                                discount2Day: room["2DayDiscountPercent"] as? Int ?? 0,
                                discount7Day: room["7DayDiscountPercent"] as? Int ?? 0,
                                discount28Day: room["28DayDiscountPercent"] as? Int ?? 0
                            ))
                        }
                    }
                }
                channels = result
            }

            // Airbnb listings - get userId dynamically from channel settings
            let airbnbUserId = channels.first { $0.channel == "airbnb" }?.listingId.components(separatedBy: "/").first ?? ""
            // Fetch users first to get the correct userId
            var usersUrl = URL(string: "https://beds24.com/api/v2/channels/airbnb/users")!
            var usersReq = URLRequest(url: usersUrl)
            usersReq.addValue(token, forHTTPHeaderField: "token")
            var dynamicUserId = ""
            if let (usersData, _) = try? await URLSession.shared.data(for: usersReq),
               let usersJson = try? JSONSerialization.jsonObject(with: usersData) as? [String: Any],
               let usersItems = usersJson["data"] as? [[String: Any]],
               let firstUser = usersItems.first?["airbnbUser"] as? [String: Any],
               let uid = firstUser["airbnbUserId"] as? String {
                dynamicUserId = uid
            }
            guard !dynamicUserId.isEmpty, let listUrl = URL(string: "https://beds24.com/api/v2/channels/airbnb/listings?airbnbUserId=\(dynamicUserId)") else { isLoading = false; return }
            var listReq = URLRequest(url: listUrl)
            listReq.addValue(token, forHTTPHeaderField: "token")
            let (listData, _) = try await URLSession.shared.data(for: listReq)
            if let json = try? JSONSerialization.jsonObject(with: listData) as? [String: Any],
               let items = json["data"] as? [[String: Any]] {
                airbnbListings = items.compactMap { item in
                    guard let listing = item["airbnbListing"] as? [String: Any],
                          let id = listing["id"] as? String else { return nil }
                    return AirbnbListing(
                        id: id,
                        name: listing["name"] as? String ?? "?",
                        bedrooms: listing["bedrooms"] as? Int ?? 0,
                        hasAvailability: listing["has_availability"] as? Bool ?? false
                    )
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func togglePublish(_ ch: ChannelInfo) async {
        guard !home.beds24RefreshToken.isEmpty else { return }
        do {
            let token = try await Beds24Client.shared.getToken(refreshToken: home.beds24RefreshToken)
            let newPublish = !ch.publish
            let payload: [[String: Any]] = [[
                "channel": ch.channel,
                "properties": [[
                    "id": Int(home.beds24ApiKey) ?? 0,
                    "roomTypes": [["id": ch.roomId, "publish": newPublish]]
                ]]
            ]]
            let url = URL(string: "https://beds24.com/api/v2/channels/settings")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue(token, forHTTPHeaderField: "token")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let _ = try await URLSession.shared.data(for: req)

            // Refresh
            await loadChannels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
