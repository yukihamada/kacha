import SwiftUI
import SwiftData

struct BookingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Booking.checkIn) private var bookings: [Booking]
    @Query private var homes: [Home]
    @AppStorage("activeHomeId") private var activeHomeId = ""

    @State private var showAddBooking = false
    @State private var filterStatus: String = "all"

    private var activeHome: Home? { homes.first { $0.id == activeHomeId } ?? homes.first }

    private let statusFilters = [
        ("all", "すべて"),
        ("inquiry", "問い合わせ"),
        ("request", "リクエスト"),
        ("upcoming", "予定"),
        ("confirmed", "確定"),
        ("active", "滞在中"),
        ("completed", "完了")
    ]

    private var filtered: [Booking] {
        if filterStatus == "all" { return bookings }
        return bookings.filter { $0.status == filterStatus }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    filterBar
                    if filtered.isEmpty {
                        emptyState
                    } else {
                        bookingList
                    }
                }
            }
            .navigationTitle("予約管理")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.kachaBg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddBooking = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.kacha)
                            .font(.title3)
                    }
                    .accessibilityLabel("予約を追加")
                }
            }
            .sheet(isPresented: $showAddBooking) {
                AddBookingView(home: activeHome)
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statusFilters, id: \.0) { (key, label) in
                    Button {
                        filterStatus = key
                    } label: {
                        Text(label)
                            .font(.subheadline)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(filterStatus == key ? Color.kacha : Color.kachaCard)
                            .foregroundColor(filterStatus == key ? .black : .white)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var bookingList: some View {
        List {
            ForEach(filtered) { booking in
                NavigationLink {
                    BookingDetailView(booking: booking)
                } label: {
                    BookingRow(booking: booking)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            .onDelete(perform: deleteBookings)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.kacha.opacity(0.4))
            Text("予約がありません")
                .font(.title3).bold()
                .foregroundColor(.white)
            Text("右上の + から新しい予約を追加できます")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private func deleteBookings(at offsets: IndexSet) {
        for index in offsets where index < filtered.count {
            context.delete(filtered[index])
        }
    }
}

struct BookingRow: View {
    let booking: Booking

    var body: some View {
        KachaCard {
            HStack(spacing: 12) {
                // Date badge
                VStack(spacing: 2) {
                    Text(booking.checkIn.formatted(.dateTime.month(.abbreviated)))
                        .font(.system(size: 10))
                        .foregroundColor(.kacha)
                    Text(booking.checkIn.formatted(.dateTime.day()))
                        .font(.title2).bold()
                        .foregroundColor(.white)
                }
                .frame(width: 44)

                Divider()
                    .background(Color.kachaCardBorder)
                    .frame(height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(booking.guestName)
                        .font(.subheadline).bold()
                        .foregroundColor(.white)
                    HStack(spacing: 6) {
                        Text(booking.platformLabel)
                            .font(.system(size: 11))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(hex: booking.platformColor).opacity(0.2))
                            .foregroundColor(Color(hex: booking.platformColor))
                            .clipShape(Capsule())
                        Text("\(booking.nights)泊")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if booking.guestCount > 0 {
                            Text("\(booking.guestCount)名")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    StatusBadge(status: booking.status, label: booking.statusLabel)
                    if booking.totalAmount > 0 {
                        Text("¥\(booking.totalAmount.formatted())")
                            .font(.caption).bold()
                            .foregroundColor(.kacha)
                    }
                }
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(bookingAccessibilityLabel)
    }

    private var bookingAccessibilityLabel: String {
        let dateStr = booking.checkIn.formatted(.dateTime.month(.abbreviated).day())
        var label = "\(booking.guestName)、\(dateStr)、\(booking.nights)泊"
        if booking.guestCount > 0 {
            label += "、\(booking.guestCount)名"
        }
        label += "、\(booking.statusLabel)"
        if booking.totalAmount > 0 {
            label += "、\(booking.totalAmount.formatted())円"
        }
        return label
    }
}

struct StatusBadge: View {
    let status: String
    let label: String

    var color: Color {
        switch status {
        case "active": return .kachaSuccess
        case "upcoming": return .kachaAccent
        case "confirmed": return .kacha
        case "inquiry": return .kachaAccent
        case "request": return .kachaWarn
        case "completed": return .secondary
        case "cancelled": return .kachaDanger
        default: return .secondary
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11)).bold()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}
