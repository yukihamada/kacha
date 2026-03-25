import SwiftUI
import SwiftData
import MapKit

// MARK: - Property Status

enum PropertyStatus {
    case vacant       // 空室
    case occupied     // 滞在中
    case cleaning     // 清掃中（チェックアウト後2時間以内）
    case alert        // アラートあり

    var color: Color {
        switch self {
        case .vacant:   return .kachaSuccess
        case .occupied: return .kachaAccent
        case .cleaning: return .kachaWarn
        case .alert:    return .kachaDanger
        }
    }

    var label: String {
        switch self {
        case .vacant:   return "空室"
        case .occupied: return "滞在中"
        case .cleaning: return "清掃中"
        case .alert:    return "アラートあり"
        }
    }

    var icon: String {
        switch self {
        case .vacant:   return "checkmark.circle.fill"
        case .occupied: return "person.fill"
        case .cleaning: return "sparkles"
        case .alert:    return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Home Map Item (Identifiable for Map annotations)

struct HomeMapItem: Identifiable {
    let id: String
    let home: Home
    let status: PropertyStatus
    let activeBooking: Booking?
    let nextBooking: Booking?
    let coordinate: CLLocationCoordinate2D
}

// MARK: - PropertyMapView

struct PropertyMapView: View {
    @Query(sort: \Home.sortOrder) private var homes: [Home]
    @Query(sort: \Booking.checkIn) private var allBookings: [Booking]
    @Query private var allAlerts: [DeviceAlert]

    private var bookings: [Booking] {
        allBookings.filter { $0.status == "active" || $0.status == "upcoming" || $0.status == "completed" }
    }
    private var alerts: [DeviceAlert] {
        allAlerts.filter { !$0.isResolved }
    }

    @State private var selectedItem: HomeMapItem? = nil
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showingPopup = false

    // Binding to navigate to a specific page in HomePagerView
    var onSelectHome: ((Home) -> Void)?

    private var mapItems: [HomeMapItem] {
        homes.compactMap { home in
            guard home.latitude != 0 || home.longitude != 0 else { return nil }
            let coordinate = CLLocationCoordinate2D(latitude: home.latitude, longitude: home.longitude)
            let status = computeStatus(for: home)
            let active = bookings.first { $0.homeId == home.id && $0.status == "active" }
            let next = bookings
                .filter { $0.homeId == home.id && $0.status == "upcoming" }
                .sorted { $0.checkIn < $1.checkIn }
                .first
            return HomeMapItem(
                id: home.id,
                home: home,
                status: status,
                activeBooking: active,
                nextBooking: next,
                coordinate: coordinate
            )
        }
    }

    private func computeStatus(for home: Home) -> PropertyStatus {
        let now = Date()

        // アラートあり（未解決）
        let hasAlert = alerts.contains { $0.homeId == home.id && !$0.isResolved }
        if hasAlert { return .alert }

        // 滞在中
        let isOccupied = bookings.contains { $0.homeId == home.id && $0.status == "active" }
        if isOccupied { return .occupied }

        // 清掃中（直近チェックアウトから2時間以内）
        let recentCheckout = bookings.first {
            $0.homeId == home.id &&
            $0.status == "completed" &&
            now.timeIntervalSince($0.checkOut) < 7200 &&
            now >= $0.checkOut
        }
        if recentCheckout != nil { return .cleaning }

        return .vacant
    }

    var body: some View {
        ZStack {
            if #available(iOS 17, *) {
                modernMap
            } else {
                legacyMap
            }

            // Popup overlay
            if showingPopup, let item = selectedItem {
                VStack {
                    Spacer()
                    PropertyPopupView(
                        item: item,
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showingPopup = false
                                selectedItem = nil
                            }
                        },
                        onNavigate: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showingPopup = false
                            }
                            onSelectHome?(item.home)
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .onTapGesture {
            if showingPopup {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingPopup = false
                    selectedItem = nil
                }
            }
        }
    }

    // MARK: - iOS 17+ Map

    @available(iOS 17, *)
    private var modernMap: some View {
        Map(position: $cameraPosition) {
            ForEach(mapItems) { item in
                Annotation(item.home.name, coordinate: item.coordinate) {
                    PropertyPinView(item: item)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedItem = item
                                showingPopup = true
                                cameraPosition = .region(
                                    MKCoordinateRegion(
                                        center: item.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                    )
                                )
                            }
                        }
                        .accessibilityLabel("\(item.home.name)、\(item.status.label)")
                        .accessibilityHint("ダブルタップで詳細を表示")
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .ignoresSafeArea(edges: .bottom)
        .onAppear { fitAllItems() }
        .onChange(of: mapItems.count) { _, _ in fitAllItems() }
    }

    // MARK: - iOS 16 Fallback

    private var legacyMap: some View {
        Map(
            coordinateRegion: .constant(regionForAll()),
            annotationItems: mapItems
        ) { item in
            MapAnnotation(coordinate: item.coordinate) {
                PropertyPinView(item: item)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedItem = item
                            showingPopup = true
                        }
                    }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func regionForAll() -> MKCoordinateRegion {
        guard !mapItems.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }
        let lats = mapItems.map { $0.coordinate.latitude }
        let lons = mapItems.map { $0.coordinate.longitude }
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.01)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    @available(iOS 17, *)
    private func fitAllItems() {
        guard !mapItems.isEmpty else { return }
        if mapItems.count == 1 {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: mapItems[0].coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            )
        } else {
            let region = regionForAll()
            cameraPosition = .region(region)
        }
    }
}

// MARK: - Property Pin View

struct PropertyPinView: View {
    let item: HomeMapItem
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6

    private var isAlert: Bool { item.status == .alert }

    var body: some View {
        ZStack {
            // Pulse ring (alert only)
            if isAlert {
                Circle()
                    .stroke(item.status.color, lineWidth: 2)
                    .frame(width: 52, height: 52)
                    .scaleEffect(pulseScale)
                    .opacity(pulseOpacity)
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: false)
                        ) {
                            pulseScale = 1.6
                            pulseOpacity = 0
                        }
                    }
            }

            // Thumbnail or icon circle (ThumbnailCache経由でデコードをキャッシュ)
            ZStack {
                if let data = item.home.backgroundImageData,
                   let uiImage = ThumbnailCache.shared.thumbnail(for: data, id: item.home.id, size: 36) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.kachaBg)
                        .frame(width: 36, height: 36)
                    Image(systemName: "house.fill")
                        .font(.system(size: 14))
                        .foregroundColor(item.status.color)
                }
            }
            .overlay(
                Circle()
                    .stroke(item.status.color, lineWidth: 3)
            )

            // Status badge
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(item.status.color)
                            .frame(width: 14, height: 14)
                        Image(systemName: item.status.icon)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .frame(width: 36, height: 36)
        }
        .frame(width: 52, height: 52)
    }
}

// MARK: - Property Popup View

struct PropertyPopupView: View {
    let item: HomeMapItem
    let onDismiss: () -> Void
    let onNavigate: () -> Void

    private var nextGuest: Booking? {
        item.nextBooking ?? item.activeBooking
    }

    var body: some View {
        ZStack {
            // Glassmorphism background
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.kachaCardBorder, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 0) {
                // Hero image header
                heroHeader

                // Content
                VStack(alignment: .leading, spacing: 12) {
                    // Name & status
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.home.name)
                                .font(.headline)
                                .bold()
                                .foregroundColor(.white)
                                .lineLimit(2)
                            if !item.home.address.isEmpty {
                                Text(item.home.address)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        // Lock icon placeholder
                        Image(systemName: "lock.fill")
                            .font(.title3)
                            .foregroundColor(.kachaWarn)
                    }

                    // Status badge
                    HStack(spacing: 6) {
                        Image(systemName: item.status.icon)
                            .font(.caption2)
                        Text(item.status.label)
                            .font(.caption)
                            .bold()
                    }
                    .foregroundColor(item.status.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(item.status.color.opacity(0.15))
                    .clipShape(Capsule())

                    // Guest info
                    if let booking = item.activeBooking ?? item.nextBooking {
                        Divider().background(Color.kachaCardBorder)
                        guestRow(booking: booking)
                    }

                    // Action buttons
                    HStack(spacing: 10) {
                        Button(action: onDismiss) {
                            Text("閉じる")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.08))
                                .foregroundColor(.secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        Button(action: onNavigate) {
                            Text("この物件を表示")
                                .font(.subheadline)
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.kacha)
                                .foregroundColor(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity)
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 8)
    }

    // MARK: Hero Header

    private var heroHeader: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let data = item.home.backgroundImageData,
                   let uiImage = ThumbnailCache.shared.thumbnail(for: data, id: "\(item.home.id)-popup", size: 240) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [item.status.color.opacity(0.3), Color.kachaBg],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: "house.fill")
                            .font(.system(size: 36))
                            .foregroundColor(item.status.color.opacity(0.5))
                    }
                }
            }
            .frame(height: 120)
            .clipped()
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.kachaBg.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Close button
            Button(action: onDismiss) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 28, height: 28)
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(10)
        }
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 20,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 20
        ))
    }

    // MARK: Guest Row

    private func guestRow(booking: Booking) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hex: booking.platformColor).opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundColor(Color(hex: booking.platformColor))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(booking.guestName)
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.white)
                    Text(booking.platformLabel)
                        .font(.system(size: 9))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color(hex: booking.platformColor).opacity(0.2))
                        .foregroundColor(Color(hex: booking.platformColor))
                        .clipShape(Capsule())
                }
                Text("チェックイン: \(booking.checkIn.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(booking.statusLabel)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Map Tab Wrapper (for NavigationStack title)

struct PropertyMapTabView: View {
    @Query(sort: \Home.sortOrder) private var homes: [Home]
    @AppStorage("activeHomeId") private var activeHomeId = ""
    @AppStorage("minpakuModeEnabled") private var minpakuModeEnabled = false

    // Callback to switch HomePager page
    var currentPage: Binding<Int>

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                if homes.filter({ $0.latitude != 0 || $0.longitude != 0 }).isEmpty {
                    emptyState
                } else {
                    PropertyMapView { home in
                        if let idx = homes.firstIndex(where: { $0.id == home.id }) {
                            activeHomeId = home.id
                            home.syncToAppStorage()
                            minpakuModeEnabled = (home.businessType != "none")
                            withAnimation { currentPage.wrappedValue = idx + 1 }
                        }
                    }
                }
            }
            .navigationTitle("マップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    statusLegend
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundColor(.kacha.opacity(0.4))
            Text("物件の位置情報がありません")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("各物件の設定で緯度・経度を登録してください")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var statusLegend: some View {
        Menu {
            Label("空室", systemImage: "checkmark.circle.fill")
            Label("滞在中", systemImage: "person.fill")
            Label("清掃中", systemImage: "sparkles")
            Label("アラート", systemImage: "exclamationmark.triangle.fill")
        } label: {
            Image(systemName: "info.circle")
                .foregroundColor(.kacha)
        }
    }
}
