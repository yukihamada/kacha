import SwiftUI
import SwiftData

// MARK: - Property List View (for 4+ properties)
// Scrollable list with search, status filters, and drill-down to HomeView.

struct PropertyListView: View {
    @Query(sort: \Home.sortOrder) private var homes: [Home]
    @Query(sort: \Booking.checkIn) private var bookings: [Booking]
    @AppStorage("activeHomeId") private var activeHomeId = ""
    @AppStorage("minpakuModeEnabled") private var minpakuModeEnabled = false

    @State private var searchText = ""
    @State private var statusFilter: PropertyStatus?

    private var filteredHomes: [Home] {
        var result = homes
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q) || $0.address.lowercased().contains(q)
            }
        }
        if let filter = statusFilter {
            result = result.filter { computeStatus(for: $0) == filter }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Summary bar
                        summaryBar
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        // Filter chips
                        filterChips
                            .padding(.top, 12)

                        // Property list
                        LazyVStack(spacing: 10) {
                            ForEach(filteredHomes) { home in
                                NavigationLink {
                                    HomeView()
                                        .onAppear {
                                            activeHomeId = home.id
                                            home.syncToAppStorage()
                                            minpakuModeEnabled = (home.businessType != "none")
                                        }
                                } label: {
                                    PropertyCardView(
                                        home: home,
                                        status: computeStatus(for: home),
                                        activeBooking: activeBooking(for: home),
                                        nextBooking: nextBooking(for: home)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("物件一覧")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.kachaBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $searchText, prompt: "物件名・住所で検索")
        }
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: 16) {
            summaryPill(count: homes.count, label: "物件", color: .kacha)
            summaryPill(
                count: homes.filter { computeStatus(for: $0) == .occupied }.count,
                label: "滞在中", color: .kachaAccent
            )
            summaryPill(
                count: homes.filter { computeStatus(for: $0) == .vacant }.count,
                label: "空室", color: .kachaSuccess
            )
            summaryPill(
                count: bookings.filter { $0.status == "upcoming" || $0.status == "confirmed" }.count,
                label: "予約", color: .kachaWarn
            )
            Spacer()
        }
    }

    private func summaryPill(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 50)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "すべて", filter: nil)
                filterChip(label: "空室", filter: .vacant)
                filterChip(label: "滞在中", filter: .occupied)
                filterChip(label: "清掃中", filter: .cleaning)
                filterChip(label: "アラート", filter: .alert)
            }
            .padding(.horizontal, 16)
        }
    }

    private func filterChip(label: String, filter: PropertyStatus?) -> some View {
        let isSelected = statusFilter == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { statusFilter = filter }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? (filter?.color ?? Color.kacha).opacity(0.2) : Color.kachaCard)
                .foregroundColor(isSelected ? (filter?.color ?? Color.kacha) : .secondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? (filter?.color ?? Color.kacha).opacity(0.4) : Color.clear, lineWidth: 1))
        }
    }

    // MARK: - Status Computation (shared with PropertyMapView)

    private func computeStatus(for home: Home) -> PropertyStatus {
        let now = Date()
        if bookings.contains(where: { $0.homeId == home.id && $0.status == "active" }) { return .occupied }
        if bookings.contains(where: {
            $0.homeId == home.id && $0.status == "completed" &&
            now.timeIntervalSince($0.checkOut) < 7200 && now >= $0.checkOut
        }) { return .cleaning }
        return .vacant
    }

    private func activeBooking(for home: Home) -> Booking? {
        bookings.first { $0.homeId == home.id && $0.status == "active" }
    }

    private func nextBooking(for home: Home) -> Booking? {
        bookings
            .filter { $0.homeId == home.id && ($0.status == "upcoming" || $0.status == "confirmed") }
            .sorted { $0.checkIn < $1.checkIn }
            .first
    }
}

// MARK: - Property Card

struct PropertyCardView: View {
    let home: Home
    let status: PropertyStatus
    let activeBooking: Booking?
    let nextBooking: Booking?

    private var todayInfo: String {
        if let b = activeBooking {
            return "\(b.guestName) 滞在中（\(b.guestCount)名）"
        }
        if let b = nextBooking {
            let df = DateFormatter()
            df.dateFormat = "M/d"
            return "次: \(b.guestName) \(df.string(from: b.checkIn))〜"
        }
        return "予約なし"
    }

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail
            HomeThumbView(home: home, size: 48)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(home.name)
                        .font(.subheadline).bold()
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if home.isShared {
                        Text(home.roleLabel)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.kachaAccent.opacity(0.2))
                            .foregroundColor(.kachaAccent)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    // Status badge
                    HStack(spacing: 3) {
                        Image(systemName: status.icon)
                            .font(.system(size: 9))
                        Text(status.label)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(status.color)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(status.color.opacity(0.12))
                    .clipShape(Capsule())
                }

                // Today / next booking
                Text(todayInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                // Address (if available)
                if !home.address.isEmpty {
                    Text(home.address)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(Color.kachaCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.kachaCardBorder, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(propertyAccessibilityLabel)
    }

    private var propertyAccessibilityLabel: String {
        var label = "\(home.name)、\(status.label)"
        label += "、\(todayInfo)"
        if !home.address.isEmpty {
            label += "、\(home.address)"
        }
        return label
    }
}
