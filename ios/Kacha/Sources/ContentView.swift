import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("minpakuModeEnabled") private var minpakuModeEnabled = false
    @AppStorage("vaultEnabled") private var vaultEnabled = false
    @AppStorage("activeHomeId") private var activeHomeId = ""
    @Query private var homes: [Home]

    private var activeHome: Home? {
        homes.first { $0.id == activeHomeId } ?? homes.first
    }

    var body: some View {
        let home = activeHome
        let hasHomes = !homes.isEmpty
        let canViewBookings = hasHomes && (home?.canViewBookings ?? true)
        let isAdmin = hasHomes && (home?.isAdmin ?? true)

        TabView {
            HomePagerView()
                .tabItem {
                    Label("ホーム", systemImage: "house.fill")
                }

            if canViewBookings {
                CalendarView()
                    .tabItem {
                        Label("カレンダー", systemImage: "calendar")
                    }
            }

            if minpakuModeEnabled && canViewBookings {
                BookingView()
                    .tabItem {
                        Label("予約", systemImage: "list.clipboard")
                    }
            }

            if vaultEnabled {
                VaultTabWrapper()
                    .tabItem {
                        Label("鍵管理", systemImage: "key.fill")
                    }
            }

            if isAdmin {
                SettingsView()
                    .tabItem {
                        Label("設定", systemImage: "gearshape.fill")
                    }
            }
        }
        .accentColor(.kacha)
        .background(Color.kachaBg)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

// MARK: - Color Extension

extension Color {
    static let kachaBg       = Color(hex: "0A0A12")
    static let kacha         = Color(hex: "E8A838")
    static let kachaAccent   = Color(hex: "3B9FE8")
    static let kachaSuccess  = Color(hex: "10B981")
    static let kachaWarn     = Color(hex: "F59E0B")
    static let kachaDanger   = Color(hex: "EF4444")
    static let kachaLocked   = Color(hex: "EF4444")
    static let kachaUnlocked = Color(hex: "10B981")
    static let kachaCard     = Color(white: 1, opacity: 0.06)
    static let kachaCardBorder = Color(white: 1, opacity: 0.10)

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Shared Card Style

struct KachaCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(Color.kachaCard)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.kachaCardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
