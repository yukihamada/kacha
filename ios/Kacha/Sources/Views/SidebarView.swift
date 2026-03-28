import SwiftUI
import SwiftData

// MARK: - iPad Sidebar Navigation Destination

enum SidebarDestination: Hashable, Identifiable {
    case dashboard
    case home(String)   // home.id
    case calendar
    case bookings
    case settings

    var id: String {
        switch self {
        case .dashboard:        return "dashboard"
        case .home(let id):     return "home-\(id)"
        case .calendar:         return "calendar"
        case .bookings:         return "bookings"
        case .settings:         return "settings"
        }
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    @Binding var selection: SidebarDestination?

    @Query(sort: \Home.sortOrder) private var homes: [Home]
    @Query(sort: \Booking.checkIn) private var bookings: [Booking]
    @Query(sort: \ShareRecord.validFrom) private var shares: [ShareRecord]
    @AppStorage("activeHomeId") private var activeHomeId = ""
    @AppStorage("minpakuModeEnabled") private var minpakuModeEnabled = false

    private var upcomingCount: Int {
        bookings.filter { $0.status == "upcoming" || $0.status == "active" }.count
    }

    private var activeShareCount: Int {
        shares.filter(\.isActive).count
    }

    var body: some View {
        List(selection: $selection) {

            // MARK: Overview section
            Section("概要") {
                NavigationLink(value: SidebarDestination.dashboard) {
                    Label {
                        Text("ダッシュボード")
                    } icon: {
                        Image(systemName: "square.grid.2x2.fill")
                            .foregroundColor(.kacha)
                    }
                }
                .badge(activeShareCount > 0 ? activeShareCount : 0)

                NavigationLink(value: SidebarDestination.calendar) {
                    Label {
                        Text("カレンダー")
                    } icon: {
                        Image(systemName: "calendar")
                            .foregroundColor(.kachaAccent)
                    }
                }

                if minpakuModeEnabled {
                    NavigationLink(value: SidebarDestination.bookings) {
                        Label {
                            Text("予約")
                        } icon: {
                            Image(systemName: "list.clipboard")
                                .foregroundColor(.kachaSuccess)
                        }
                    }
                    .badge(upcomingCount > 0 ? upcomingCount : 0)
                }
            }

            // MARK: Properties section
            Section("物件") {
                ForEach(homes) { home in
                    NavigationLink(value: SidebarDestination.home(home.id)) {
                        HomeRowView(home: home, bookings: bookings)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            activeHomeId = home.id
                            home.syncToAppStorage()
                            minpakuModeEnabled = (home.businessType != "none")
                        } label: {
                            Label("選択", systemImage: "checkmark.circle")
                        }
                        .tint(.kacha)
                    }
                }
            }

            // MARK: Settings section
            Section {
                NavigationLink(value: SidebarDestination.settings) {
                    Label {
                        Text("設定")
                    } icon: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("IKI")
        .navigationBarTitleDisplayMode(.large)
        .background(Color.kachaBg)
        .scrollContentBackground(.hidden)
        .tint(.kacha)
        .onAppear {
            // Default selection: first home or dashboard
            if selection == nil {
                if let first = homes.first {
                    selection = .home(first.id)
                } else {
                    selection = .dashboard
                }
            }
        }
    }
}

// MARK: - Home Row (thumbnail + badge)

private struct HomeRowView: View {
    let home: Home
    let bookings: [Booking]

    private var upcomingCount: Int {
        bookings.filter {
            $0.homeId == home.id && ($0.status == "upcoming" || $0.status == "active")
        }.count
    }

    var body: some View {
        HStack(spacing: 10) {
            // Thumbnail
            Group {
                if let data = home.backgroundImageData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color.kacha.opacity(0.15)
                        Image(systemName: "house.fill")
                            .font(.caption)
                            .foregroundColor(.kacha)
                    }
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(home.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if !home.address.isEmpty {
                    Text(home.address)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if upcomingCount > 0 {
                Text("\(upcomingCount)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.kachaAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.kachaAccent.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}
