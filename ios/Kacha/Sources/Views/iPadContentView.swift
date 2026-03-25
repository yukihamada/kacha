import SwiftUI
import SwiftData

// MARK: - iPad 3-Column Layout

struct iPadContentView: View {
    @Query(sort: \Home.sortOrder) private var homes: [Home]
    @AppStorage("activeHomeId") private var activeHomeId = ""
    @AppStorage("minpakuModeEnabled") private var minpakuModeEnabled = false

    @State private var sidebarSelection: SidebarDestination? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {

            // MARK: Sidebar (column 1)
            SidebarView(selection: $sidebarSelection)

        } content: {

            // MARK: Content / Main (column 2)
            contentColumn

        } detail: {

            // MARK: Detail (column 3)
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.kacha)
        // Keep activeHomeId in sync when sidebar selection changes
        .onChange(of: sidebarSelection) { _, newValue in
            if case .home(let id) = newValue {
                if let home = homes.first(where: { $0.id == id }) {
                    activeHomeId = id
                    home.syncToAppStorage()
                    minpakuModeEnabled = (home.businessType != "none")
                }
            }
        }
    }

    // MARK: - Content Column

    @ViewBuilder
    private var contentColumn: some View {
        switch sidebarSelection {
        case .dashboard, .none:
            iPadDashboardView(sidebarSelection: $sidebarSelection)

        case .home(let id):
            if let home = homes.first(where: { $0.id == id }) {
                iPadHomeMainView(home: home)
            } else {
                emptyState("物件が見つかりません", "house.trianglebadge.exclamationmark")
            }

        case .calendar:
            CalendarView()
                .navigationTitle("カレンダー")

        case .bookings:
            BookingView()
                .navigationTitle("予約")

        case .settings:
            SettingsView()
                .navigationTitle("設定")
        }
    }

    // MARK: - Detail Column

    @ViewBuilder
    private var detailColumn: some View {
        switch sidebarSelection {
        case .home(let id):
            if let home = homes.first(where: { $0.id == id }) {
                iPadHomeDetailView(home: home)
            } else {
                emptyState("物件を選択してください", "hand.point.left")
            }

        case .dashboard:
            iPadDashboardDetailView()

        default:
            emptyState("左のメニューから項目を選んでください", "sidebar.left")
        }
    }

    private func emptyState(_ message: String, _ icon: String) -> some View {
        ZStack {
            Color.kachaBg.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(.kacha.opacity(0.4))
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - iPad Dashboard View (content column)

private struct iPadDashboardView: View {
    @Binding var sidebarSelection: SidebarDestination?

    @Query(sort: \Home.sortOrder) private var homes: [Home]
    @Query(sort: \Booking.checkIn) private var bookings: [Booking]
    @Query(sort: \ShareRecord.validFrom) private var shares: [ShareRecord]
    @Query(sort: \ActivityLog.timestamp, order: .reverse) private var logs: [ActivityLog]
    @AppStorage("minpakuModeEnabled") private var minpakuModeEnabled = false

    private var upcoming: [Booking] {
        bookings.filter { $0.status == "upcoming" || $0.status == "active" }
            .sorted { $0.checkIn < $1.checkIn }
    }

    private var activeShares: [ShareRecord] { shares.filter(\.isActive) }

    var body: some View {
        ZStack {
            Color.kachaBg.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 20, pinnedViews: []) {

                    // Summary grid
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible()), GridItem(.flexible()),
                            GridItem(.flexible()), GridItem(.flexible())
                        ],
                        spacing: 12
                    ) {
                        summaryCard("house.fill",        "\(homes.count)",         "物件",       .kacha)
                        if minpakuModeEnabled {
                            summaryCard("calendar",      "\(upcoming.count)",      "予約",       .kachaAccent)
                        }
                        summaryCard("person.badge.plus", "\(activeShares.count)",  "シェア中",   .kachaSuccess)
                        summaryCard("clock.arrow.2.circlepath", "\(logs.count)",   "ログ",       .kachaWarn)
                    }
                    .padding(.top, 8)

                    // Homes list
                    KachaCard {
                        VStack(alignment: .leading, spacing: 0) {
                            sectionHeader("house.fill", "物件一覧", .kacha)
                            if homes.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "house.badge.plus")
                                        .font(.system(size: 36))
                                        .foregroundColor(.kacha.opacity(0.35))
                                    Text("物件がありません")
                                        .font(.subheadline).foregroundColor(.secondary)
                                    Text("設定から物件を追加してください")
                                        .font(.caption).foregroundColor(.secondary.opacity(0.7))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("物件がありません。設定から追加してください。")
                            } else {
                                ForEach(Array(homes.enumerated()), id: \.element.id) { idx, home in
                                    Button {
                                        sidebarSelection = .home(home.id)
                                    } label: {
                                        dashboardHomeRow(home, upcoming: upcoming)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(home.name)、\(upcoming.filter { $0.homeId == home.id }.count)件の予約")

                                    if idx < homes.count - 1 {
                                        Divider().background(Color.kachaCardBorder).padding(.leading, 60)
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }

                    // Upcoming bookings
                    if minpakuModeEnabled && !upcoming.isEmpty {
                        KachaCard {
                            VStack(alignment: .leading, spacing: 0) {
                                sectionHeader("calendar", "直近の予約", .kachaAccent)
                                ForEach(upcoming.prefix(8)) { booking in
                                    let homeName = homes.first { $0.id == booking.homeId }?.name ?? ""
                                    upcomingRow(booking, homeName: homeName)
                                    if booking.id != upcoming.prefix(8).last?.id {
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
                            VStack(alignment: .leading, spacing: 0) {
                                sectionHeader("person.badge.plus", "アクティブなシェア", .kachaSuccess)
                                ForEach(activeShares.prefix(6)) { share in
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
                                    .padding(.vertical, 6)
                                }
                            }
                            .padding(16)
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationTitle("ダッシュボード")
    }

    private func sectionHeader(_ icon: String, _ title: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(color)
            Text(title).font(.subheadline).bold().foregroundColor(.white)
        }
        .padding(.bottom, 12)
    }

    private func summaryCard(_ icon: String, _ value: String, _ label: String, _ color: Color) -> some View {
        KachaCard {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3).foregroundColor(color)
                Text(value).font(.title2).bold().foregroundColor(.white)
                Text(label).font(.caption2).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    private func dashboardHomeRow(_ home: Home, upcoming: [Booking]) -> some View {
        HStack(spacing: 12) {
            Group {
                if let data = home.backgroundImageData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.kacha.opacity(0.15)
                        Image(systemName: "house.fill").font(.caption).foregroundColor(.kacha)
                    }
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(home.name).font(.subheadline).bold().foregroundColor(.white).lineLimit(1)
                if !home.address.isEmpty {
                    Text(home.address).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
            }

            Spacer()

            let count = upcoming.filter { $0.homeId == home.id }.count
            if count > 0 {
                Text("\(count)件").font(.caption2).foregroundColor(.kachaAccent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.kachaAccent.opacity(0.15))
                    .clipShape(Capsule())
            }

            Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func upcomingRow(_ booking: Booking, homeName: String) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(booking.guestName).font(.subheadline).foregroundColor(.white)
                Text("\(booking.checkIn.formatted(date: .abbreviated, time: .omitted)) · \(homeName)")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Text(booking.statusLabel).font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - iPad Dashboard Detail (column 3)

private struct iPadDashboardDetailView: View {
    @Query(sort: \ActivityLog.timestamp, order: .reverse) private var logs: [ActivityLog]

    var body: some View {
        ZStack {
            Color.kachaBg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .font(.system(size: 28)).foregroundColor(.kachaWarn)
                        Text("最近のアクティビティ").font(.title3).bold().foregroundColor(.white)
                    }
                    .padding(.top, 20)

                    KachaCard {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(logs.prefix(20)) { log in
                                HStack(spacing: 10) {
                                    Image(systemName: log.icon)
                                        .font(.caption)
                                        .foregroundColor(Color(hex: log.iconColor))
                                        .frame(width: 20)
                                    Text(log.detail).font(.caption).foregroundColor(.secondary).lineLimit(2)
                                    Spacer()
                                    Text(timeAgo(log.timestamp))
                                        .font(.caption2).foregroundColor(.secondary.opacity(0.6))
                                }
                                .padding(.vertical, 8)

                                if log.id != logs.prefix(20).last?.id {
                                    Divider().background(Color.kachaCardBorder)
                                }
                            }

                            if logs.isEmpty {
                                Text("アクティビティはまだありません")
                                    .font(.caption).foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                            }
                        }
                        .padding(16)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
            }
        }
        .navigationTitle("アクティビティ")
    }

    private func timeAgo(_ date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1  { return "今" }
        if minutes < 60 { return "\(minutes)分前" }
        let hours = minutes / 60
        if hours < 24   { return "\(hours)時間前" }
        return "\(hours / 24)日前"
    }
}

// MARK: - iPad Home Main View (column 2: device controls)

private struct iPadHomeMainView: View {
    let home: Home

    var body: some View {
        ZStack {
            Color.kachaBg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    // Home header
                    homeHeader

                    // Full HomeView embedded (scroll disabled)
                    HomeView()
                }
            }
        }
        .navigationTitle(home.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var homeHeader: some View {
        HStack(spacing: 14) {
            Group {
                if let data = home.backgroundImageData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.kacha.opacity(0.15)
                        Image(systemName: "house.fill").foregroundColor(.kacha)
                    }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(home.name).font(.title3).bold().foregroundColor(.white)
                if !home.address.isEmpty {
                    Text(home.address).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}

// MARK: - iPad Home Detail View (column 3: bookings / shares for this home)

private struct iPadHomeDetailView: View {
    let home: Home

    @Query private var allBookings: [Booking]
    @Query private var allShares: [ShareRecord]

    private var homeBookings: [Booking] {
        allBookings
            .filter { $0.homeId == home.id && ($0.status == "upcoming" || $0.status == "active") }
            .sorted { $0.checkIn < $1.checkIn }
    }

    private var homeShares: [ShareRecord] {
        allShares.filter { $0.homeId == home.id && $0.isActive }
    }

    var body: some View {
        ZStack {
            Color.kachaBg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    // Upcoming bookings for this home
                    if !homeBookings.isEmpty {
                        KachaCard {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 6) {
                                    Image(systemName: "calendar").foregroundColor(.kachaAccent)
                                    Text("予約").font(.subheadline).bold().foregroundColor(.white)
                                    Spacer()
                                    Text("\(homeBookings.count)件")
                                        .font(.caption2).foregroundColor(.kachaAccent)
                                }
                                .padding(.bottom, 12)

                                ForEach(homeBookings.prefix(10)) { booking in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(booking.guestName).font(.subheadline).bold().foregroundColor(.white)
                                            Spacer()
                                            Text(booking.platformLabel)
                                                .font(.system(size: 10))
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Color(hex: booking.platformColor).opacity(0.2))
                                                .foregroundColor(Color(hex: booking.platformColor))
                                                .clipShape(Capsule())
                                        }
                                        HStack {
                                            Text("\(booking.checkIn.formatted(date: .abbreviated, time: .omitted)) - \(booking.checkOut.formatted(date: .abbreviated, time: .omitted))")
                                                .font(.caption2).foregroundColor(.secondary)
                                            Spacer()
                                            if booking.totalAmount > 0 {
                                                Text("¥\(booking.totalAmount / 100)")
                                                    .font(.caption).bold().foregroundColor(.kacha)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 8)

                                    if booking.id != homeBookings.prefix(10).last?.id {
                                        Divider().background(Color.kachaCardBorder)
                                    }
                                }
                            }
                            .padding(16)
                        }
                    }

                    // Active shares for this home
                    if !homeShares.isEmpty {
                        KachaCard {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.badge.plus").foregroundColor(.kachaSuccess)
                                    Text("シェア中").font(.subheadline).bold().foregroundColor(.white)
                                }
                                .padding(.bottom, 12)

                                ForEach(homeShares) { share in
                                    HStack(spacing: 10) {
                                        Image(systemName: "person.circle.fill")
                                            .font(.title3).foregroundColor(.kachaSuccess.opacity(0.7))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(share.recipientName.isEmpty ? "ゲスト" : share.recipientName)
                                                .font(.subheadline).foregroundColor(.white)
                                            Text(share.roleLabel).font(.caption2).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text(share.expiresAt.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                            .padding(16)
                        }
                    }

                    if homeBookings.isEmpty && homeShares.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 36))
                                .foregroundColor(.kacha.opacity(0.3))
                            Text("予約やシェアはありません")
                                .font(.subheadline).foregroundColor(.secondary)
                            Text("予約タブから予約を追加できます")
                                .font(.caption).foregroundColor(.secondary.opacity(0.7))
                        }
                        .padding(.top, 60)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("予約やシェアはありません")
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
            }
        }
        .navigationTitle("詳細")
    }
}
