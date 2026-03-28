import SwiftUI
import SwiftData
import Charts

struct RevenueReportView: View {
    let home: Home
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Booking.checkIn) private var allBookings: [Booking]
    @Query(sort: \UtilityRecord.month) private var allUtilities: [UtilityRecord]

    private var bookings: [Booking] { allBookings.filter { $0.homeId == home.id } }
    private var utilities: [UtilityRecord] { allUtilities.filter { $0.homeId == home.id } }

    private var last6Months: [String] {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        return (0..<6).reversed().compactMap {
            cal.date(byAdding: .month, value: -$0, to: Date())
        }.map { f.string(from: $0) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 4) {
                            Text(home.name).font(.title2).bold().foregroundColor(.white)
                            Text("収支レポート").font(.caption).foregroundColor(.kacha)
                        }
                        .padding(.top, 8)

                        // Monthly revenue chart
                        KachaCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("月別売上").font(.subheadline).bold().foregroundColor(.white)
                                Chart {
                                    ForEach(last6Months, id: \.self) { month in
                                        let revenue = revenueForMonth(month)
                                        let expenses = expensesForMonth(month)
                                        BarMark(x: .value("月", String(month.suffix(2)) + "月"), y: .value("金額", revenue))
                                            .foregroundStyle(Color.kachaSuccess)
                                        BarMark(x: .value("月", String(month.suffix(2)) + "月"), y: .value("金額", -expenses))
                                            .foregroundStyle(Color.kachaDanger)
                                    }
                                }
                                .frame(height: 200)
                                HStack(spacing: 16) {
                                    legendDot(.kachaSuccess, "売上")
                                    legendDot(.kachaDanger, "経費")
                                }
                                .font(.caption2)
                            }
                            .padding(16)
                        }

                        // Summary
                        let totalRevenue = bookings.filter { $0.status != "cancelled" }.reduce(0) { $0 + $1.totalAmount }
                        let totalExpenses = utilities.reduce(0) { $0 + $1.amount }
                        let totalCommission = 0 // TODO: calculate from Beds24 commission

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            summaryBox("売上", "¥\(totalRevenue)", .kachaSuccess)
                            summaryBox("経費", "¥\(totalExpenses)", .kachaDanger)
                            summaryBox("利益", "¥\(totalRevenue - totalExpenses)", totalRevenue > totalExpenses ? .kacha : .kachaDanger)
                        }

                        // Platform breakdown
                        KachaCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("プラットフォーム別").font(.subheadline).bold().foregroundColor(.white)
                                let platforms = Dictionary(grouping: bookings.filter { $0.status != "cancelled" }) { $0.platform }
                                ForEach(platforms.sorted(by: { $0.value.count > $1.value.count }), id: \.key) { platform, pBookings in
                                    let total = pBookings.reduce(0) { $0 + $1.totalAmount }
                                    HStack {
                                        Text(pBookings.first?.platformLabel ?? platform)
                                            .font(.subheadline).foregroundColor(.white)
                                        Spacer()
                                        Text("\(pBookings.count)件").font(.caption).foregroundColor(.secondary)
                                        Text("¥\(total)").font(.subheadline).bold().foregroundColor(.kacha)
                                    }
                                }
                            }
                            .padding(16)
                        }

                        // Share button
                        ShareLink(item: generateReportText()) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                Text("レポートを共有").bold()
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.kacha)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("収支レポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func revenueForMonth(_ month: String) -> Int {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        return bookings.filter {
            $0.status != "cancelled" && f.string(from: $0.checkIn) == month
        }.reduce(0) { $0 + $1.totalAmount }
    }

    private func expensesForMonth(_ month: String) -> Int {
        utilities.filter { $0.month == month }.reduce(0) { $0 + $1.amount }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundColor(.secondary)
        }
    }

    private func summaryBox(_ label: String, _ value: String, _ color: Color) -> some View {
        KachaCard {
            VStack(spacing: 4) {
                Text(value).font(.subheadline).bold().foregroundColor(color)
                Text(label).font(.caption2).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
        }
    }

    private func generateReportText() -> String {
        let totalRevenue = bookings.filter { $0.status != "cancelled" }.reduce(0) { $0 + $1.totalAmount }
        let totalExpenses = utilities.reduce(0) { $0 + $1.amount }
        return """
        【\(home.name) 収支レポート】
        期間: 全期間
        売上: ¥\(totalRevenue)
        経費: ¥\(totalExpenses)
        利益: ¥\(totalRevenue - totalExpenses)
        予約数: \(bookings.filter { $0.status != "cancelled" }.count)件
        """
    }
}
