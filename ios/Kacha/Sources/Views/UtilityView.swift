import SwiftUI
import SwiftData
import Charts

struct UtilityView: View {
    let home: Home
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UtilityRecord.month) private var allRecords: [UtilityRecord]
    @State private var showAdd = false
    @State private var addCategory = "electric"
    @State private var addAmount = ""
    @State private var addMonth = ""

    private var records: [UtilityRecord] { allRecords.filter { $0.homeId == home.id } }

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
                        // Chart
                        if !records.isEmpty {
                            KachaCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("月別推移").font(.subheadline).bold().foregroundColor(.white)
                                    Chart {
                                        ForEach(last6Months, id: \.self) { month in
                                            ForEach(UtilityRecord.categories, id: \.key) { cat in
                                                let total = records.filter { $0.month == month && $0.category == cat.key }
                                                    .reduce(0) { $0 + $1.amount }
                                                if total > 0 {
                                                    BarMark(
                                                        x: .value("月", String(month.suffix(2)) + "月"),
                                                        y: .value("金額", total)
                                                    )
                                                    .foregroundStyle(Color(hex: cat.color))
                                                    .annotation(position: .top) {
                                                        if total > 0 {
                                                            Text("¥\(total)").font(.system(size: 8)).foregroundColor(.secondary)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .frame(height: 200)
                                    .chartYAxis { AxisMarks(position: .leading) { _ in AxisValueLabel().foregroundStyle(.secondary) } }
                                }
                                .padding(16)
                            }
                        }

                        // Summary cards
                        HStack(spacing: 10) {
                            ForEach(UtilityRecord.categories, id: \.key) { cat in
                                let thisMonth = currentMonth()
                                let total = records.filter { $0.month == thisMonth && $0.category == cat.key }
                                    .reduce(0) { $0 + $1.amount }
                                KachaCard {
                                    VStack(spacing: 6) {
                                        Image(systemName: cat.icon)
                                            .font(.title3).foregroundColor(Color(hex: cat.color))
                                        Text(cat.label).font(.caption2).foregroundColor(.secondary)
                                        Text("¥\(total)").font(.subheadline).bold().foregroundColor(.white)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                }
                            }
                        }

                        // Recent records
                        KachaCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("記録一覧").font(.subheadline).bold().foregroundColor(.white)
                                    Spacer()
                                    Button { showAdd = true } label: {
                                        Label("追加", systemImage: "plus.circle.fill")
                                            .font(.caption).foregroundColor(.kacha)
                                    }
                                }
                                if records.isEmpty {
                                    Text("まだ記録がありません").font(.caption).foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                                } else {
                                    ForEach(records.suffix(10).reversed()) { record in
                                        let cat = UtilityRecord.categories.first { $0.key == record.category }
                                        HStack(spacing: 10) {
                                            Image(systemName: cat?.icon ?? "questionmark")
                                                .font(.caption).foregroundColor(Color(hex: cat?.color ?? "999"))
                                                .frame(width: 20)
                                            Text(record.month).font(.caption).foregroundColor(.secondary)
                                            Text(cat?.label ?? "").font(.caption).foregroundColor(.secondary)
                                            Spacer()
                                            Text("¥\(record.amount)").font(.subheadline).foregroundColor(.white)
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) { context.delete(record) } label: {
                                                Label("削除", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(16)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("光熱費")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showAdd) { addSheet }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                VStack(spacing: 20) {
                    Picker("カテゴリ", selection: $addCategory) {
                        ForEach(UtilityRecord.categories, id: \.key) { cat in
                            Text(cat.label).tag(cat.key)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    TextField("金額（例: 5000）", text: $addAmount)
                        .keyboardType(.numberPad)
                        .foregroundColor(.white).padding(14)
                        .background(Color.kachaCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kachaCardBorder))
                        .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 20)
            }
            .navigationTitle("光熱費を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { showAdd = false }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveRecord() }.foregroundColor(.kacha)
                        .disabled(addAmount.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { addMonth = currentMonth() }
    }

    private func saveRecord() {
        guard let amount = Int(addAmount), amount > 0 else { return }
        let record = UtilityRecord(homeId: home.id, category: addCategory, amount: amount, month: addMonth)
        context.insert(record)
        showAdd = false
        addAmount = ""
    }

    private func currentMonth() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }
}
