import SwiftUI
import SwiftData

extension Notification.Name {
    static let switchToDashboard = Notification.Name("switchToDashboard")
}

// MARK: - Swipeable Home Pager
// [Dashboard] [Home 1] [Home 2] [Home 3] ...
// Default: Home 1 (index 1). Swipe left → Dashboard. Swipe right → next home.

struct HomePagerView: View {
    @Query(sort: \Home.sortOrder) private var homes: [Home]
    @AppStorage("activeHomeId") private var activeHomeId = ""
    @State private var currentPage = 1  // 0=Dashboard, 1+=Homes

    private var pageCount: Int { homes.count + 1 } // +1 for dashboard

    var body: some View {
        ZStack(alignment: .top) {
            Color.kachaBg.ignoresSafeArea()

            if homes.isEmpty {
                HomeView()
            } else {
                TabView(selection: $currentPage) {
                    // Page 0: Dashboard
                    DashboardView()
                        .tag(0)

                    // Page 1+: Individual homes
                    ForEach(Array(homes.enumerated()), id: \.element.id) { index, home in
                        HomeView()
                            .tag(index + 1)
                            .onAppear {
                                if activeHomeId != home.id {
                                    activeHomeId = home.id
                                    home.syncToAppStorage()
                                }
                            }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Page indicator
                VStack {
                    Spacer()
                    pageIndicator
                        .padding(.bottom, 4)
                }
            }
        }
        .onAppear {
            if let idx = homes.firstIndex(where: { $0.id == activeHomeId }) {
                currentPage = idx + 1
            } else if !homes.isEmpty {
                currentPage = 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToDashboard)) { _ in
            withAnimation { currentPage = 0 }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            // Dashboard dot
            Circle()
                .fill(currentPage == 0 ? Color.kacha : Color.white.opacity(0.3))
                .frame(width: currentPage == 0 ? 8 : 6, height: currentPage == 0 ? 8 : 6)

            // Separator
            if homes.count > 0 {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 8)
            }

            // Home dots
            ForEach(Array(homes.enumerated()), id: \.element.id) { index, _ in
                Circle()
                    .fill(currentPage == index + 1 ? Color.kacha : Color.white.opacity(0.3))
                    .frame(width: currentPage == index + 1 ? 8 : 6, height: currentPage == index + 1 ? 8 : 6)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(Color.black.opacity(0.3))
        .clipShape(Capsule())
    }
}

// MARK: - Dashboard (aggregate view of all homes)

struct DashboardView: View {
    @Query(sort: \Home.sortOrder) private var homes: [Home]
    @Query(sort: \Booking.checkIn) private var bookings: [Booking]
    @Query(sort: \ShareRecord.validFrom) private var shares: [ShareRecord]
    @Query(sort: \ActivityLog.timestamp, order: .reverse) private var logs: [ActivityLog]
    @AppStorage("minpakuModeEnabled") private var minpakuModeEnabled = false

    private var upcomingBookings: [Booking] {
        bookings.filter { $0.status == "upcoming" || $0.status == "active" }
            .sorted { $0.checkIn < $1.checkIn }
    }

    private var activeShares: [ShareRecord] {
        shares.filter(\.isActive)
    }

    private var recentLogs: [ActivityLog] {
        Array(logs.prefix(10))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 4) {
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.system(size: 28)).foregroundColor(.kacha)
                            Text("ダッシュボード").font(.title2).bold().foregroundColor(.white)
                            Text("\(homes.count)件の物件を管理中")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.top, 16)

                        // Summary cards
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            summaryCard("house.fill", "\(homes.count)", "物件", .kacha)
                            if minpakuModeEnabled {
                                summaryCard("calendar", "\(upcomingBookings.count)", "予約", .kachaAccent)
                            }
                            summaryCard("person.badge.plus", "\(activeShares.count)", "シェア中", .kachaSuccess)
                            summaryCard("list.bullet.rectangle", "\(recentLogs.count)", "最近のログ", .kachaWarn)
                        }

                        // Homes list
                        KachaCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 6) {
                                    Image(systemName: "house.fill").foregroundColor(.kacha)
                                    Text("物件一覧").font(.subheadline).bold().foregroundColor(.white)
                                }
                                ForEach(homes) { home in
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle().fill(Color.kacha.opacity(0.15)).frame(width: 36, height: 36)
                                            Image(systemName: "house.fill").font(.caption).foregroundColor(.kacha)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(home.name).font(.subheadline).bold().foregroundColor(.white)
                                            if !home.address.isEmpty {
                                                Text(home.address).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        let homeBookings = upcomingBookings.filter { $0.homeId == home.id }
                                        if !homeBookings.isEmpty {
                                            Text("\(homeBookings.count)件")
                                                .font(.caption2).foregroundColor(.kachaAccent)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Color.kachaAccent.opacity(0.15))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    if home.id != homes.last?.id {
                                        Divider().background(Color.kachaCardBorder)
                                    }
                                }
                            }
                            .padding(16)
                        }

                        // Upcoming bookings (if business mode)
                        if minpakuModeEnabled && !upcomingBookings.isEmpty {
                            KachaCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "calendar").foregroundColor(.kachaAccent)
                                        Text("直近の予約").font(.subheadline).bold().foregroundColor(.white)
                                    }
                                    ForEach(upcomingBookings.prefix(5)) { booking in
                                        let homeName = homes.first { $0.id == booking.homeId }?.name ?? ""
                                        HStack(spacing: 10) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(booking.guestName).font(.subheadline).foregroundColor(.white)
                                                Text("\(booking.checkIn.formatted(date: .abbreviated, time: .omitted)) · \(homeName)")
                                                    .font(.caption2).foregroundColor(.secondary)
                                            }
                                            Spacer()
                                            Text(booking.statusLabel).font(.caption2).foregroundColor(.secondary)
                                        }
                                        if booking.id != upcomingBookings.prefix(5).last?.id {
                                            Divider().background(Color.kachaCardBorder)
                                        }
                                    }
                                }
                                .padding(16)
                            }
                        }

                        // Active shares
                        if !activeShares.isEmpty {
                            KachaCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "person.badge.plus").foregroundColor(.kachaSuccess)
                                        Text("アクティブなシェア").font(.subheadline).bold().foregroundColor(.white)
                                    }
                                    ForEach(activeShares.prefix(5)) { share in
                                        HStack(spacing: 10) {
                                            Text(share.recipientName.isEmpty ? "ゲスト" : share.recipientName)
                                                .font(.subheadline).foregroundColor(.white)
                                            Text(share.roleLabel).font(.caption2)
                                                .padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(Color.kacha.opacity(0.15))
                                                .foregroundColor(.kacha)
                                                .clipShape(Capsule())
                                            Spacer()
                                            Text(share.homeName).font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(16)
                            }
                        }

                        // Recent activity
                        if !recentLogs.isEmpty {
                            KachaCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "list.bullet.rectangle").foregroundColor(.kachaWarn)
                                        Text("最近のアクティビティ").font(.subheadline).bold().foregroundColor(.white)
                                    }
                                    ForEach(recentLogs.prefix(5)) { log in
                                        HStack(spacing: 10) {
                                            Image(systemName: log.icon)
                                                .font(.caption).foregroundColor(Color(hex: log.iconColor))
                                                .frame(width: 16)
                                            Text(log.detail).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                            Spacer()
                                            Text(timeAgo(log.timestamp)).font(.caption2).foregroundColor(.secondary.opacity(0.6))
                                        }
                                    }
                                }
                                .padding(16)
                            }
                        }

                        Text("← スワイプで物件へ").font(.caption2).foregroundColor(.secondary.opacity(0.4))

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func summaryCard(_ icon: String, _ value: String, _ label: String, _ color: Color) -> some View {
        KachaCard {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3).foregroundColor(color)
                Text(value).font(.title2).bold().foregroundColor(.white)
                Text(label).font(.caption2).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "今" }
        if minutes < 60 { return "\(minutes)分前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)時間前" }
        return "\(hours / 24)日前"
    }
}
