import SwiftUI
import SwiftData

// MARK: - Pasha Expense Integration View
// Links expense receipts from Pasha app to KAGI properties for property-level P/L tracking.

@Model
final class PropertyExpense {
    var id: String
    var homeId: String
    var amount: Int
    var category: String        // "消耗品費", "修繕費", "通信費", "光熱費", etc.
    var vendor: String
    var date: Date
    var notes: String
    var source: String          // "manual", "pasha"
    var createdAt: Date

    init(
        homeId: String,
        amount: Int,
        category: String,
        vendor: String = "",
        date: Date = Date(),
        notes: String = "",
        source: String = "manual"
    ) {
        self.id = UUID().uuidString
        self.homeId = homeId
        self.amount = amount
        self.category = category
        self.vendor = vendor
        self.date = date
        self.notes = notes
        self.source = source
        self.createdAt = Date()
    }
}

struct ExpenseIntegrationView: View {
    let home: Home
    @Environment(\.modelContext) private var context
    @Query(sort: \PropertyExpense.date, order: .reverse) private var allExpenses: [PropertyExpense]

    @State private var showAddExpense = false
    @State private var showPashaImport = false
    @State private var selectedMonth = Date()

    private var expenses: [PropertyExpense] {
        allExpenses.filter { $0.homeId == home.id }
    }

    private var monthlyExpenses: [PropertyExpense] {
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month], from: selectedMonth)
        return expenses.filter {
            let c = cal.dateComponents([.year, .month], from: $0.date)
            return c.year == components.year && c.month == components.month
        }
    }

    private var monthlyTotal: Int { monthlyExpenses.reduce(0) { $0 + $1.amount } }

    private var byCategory: [(category: String, total: Int)] {
        var dict: [String: Int] = [:]
        for e in monthlyExpenses { dict[e.category, default: 0] += e.amount }
        return dict.sorted { $0.value > $1.value }.map { (category: $0.key, total: $0.value) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        // Month picker
                        HStack {
                            Button {
                                selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                            } label: {
                                Image(systemName: "chevron.left").foregroundColor(.kacha)
                            }
                            Spacer()
                            Text(monthLabel)
                                .font(.headline).foregroundColor(.white)
                            Spacer()
                            Button {
                                selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                            } label: {
                                Image(systemName: "chevron.right").foregroundColor(.kacha)
                            }
                        }
                        .padding(.horizontal, 16)

                        // Total
                        KachaCard {
                            VStack(spacing: 8) {
                                Text("月間経費")
                                    .font(.caption).foregroundColor(.secondary)
                                Text("¥\(monthlyTotal.formatted())")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.kachaDanger)
                                Text("\(monthlyExpenses.count)件")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 16)

                        // Category breakdown
                        if !byCategory.isEmpty {
                            KachaCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "chart.pie.fill").foregroundColor(.kacha)
                                        Text("カテゴリ別").font(.subheadline).bold().foregroundColor(.white)
                                    }
                                    ForEach(byCategory, id: \.category) { item in
                                        HStack {
                                            Text(item.category).font(.caption).foregroundColor(.white)
                                            Spacer()
                                            Text("¥\(item.total.formatted())")
                                                .font(.caption).bold().foregroundColor(.kachaDanger)
                                        }
                                    }
                                }
                                .padding(16)
                            }
                            .padding(.horizontal, 16)
                        }

                        // Actions
                        HStack(spacing: 10) {
                            Button { showAddExpense = true } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("経費を追加").bold()
                                }
                                .font(.subheadline).foregroundColor(.black)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color.kacha)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            Button { importFromPasha() } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "camera.fill")
                                    Text("パシャから取込").bold()
                                }
                                .font(.subheadline).foregroundColor(.kachaAccent)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color.kachaAccent.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.horizontal, 16)

                        // Expense list
                        LazyVStack(spacing: 8) {
                            ForEach(monthlyExpenses) { expense in
                                expenseRow(expense)
                            }
                            .onDelete { offsets in
                                for i in offsets {
                                    context.delete(monthlyExpenses[i])
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("\(home.name) 経費")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAddExpense) {
                PropertyExpenseAddView(homeId: home.id)
            }
        }
    }

    private var monthLabel: String {
        let f = DateFormatter(); f.dateFormat = "yyyy年M月"
        return f.string(from: selectedMonth)
    }

    private func expenseRow(_ expense: PropertyExpense) -> some View {
        KachaCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(expense.category)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.kachaAccent.opacity(0.15))
                            .foregroundColor(.kachaAccent)
                            .clipShape(Capsule())
                        if expense.source == "pasha" {
                            Text("パシャ")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.kacha.opacity(0.15))
                                .foregroundColor(.kacha)
                                .clipShape(Capsule())
                        }
                    }
                    if !expense.vendor.isEmpty {
                        Text(expense.vendor).font(.subheadline).foregroundColor(.white)
                    }
                    Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Text("¥\(expense.amount.formatted())")
                    .font(.subheadline).bold().foregroundColor(.kachaDanger)
            }
            .padding(12)
        }
    }

    // MARK: - Pasha Import

    private func importFromPasha() {
        // Check clipboard for Pasha export data
        if let clip = UIPasteboard.general.string, clip.hasPrefix("SAKUTSU_IMPORT:") || clip.hasPrefix("PASHA_EXPORT:") {
            let jsonStr = clip.replacingOccurrences(of: "SAKUTSU_IMPORT:", with: "")
                .replacingOccurrences(of: "PASHA_EXPORT:", with: "")
            if let data = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let totalExpenses = json["totalExpenses"] as? Int,
               let byCategory = json["byCategory"] as? [String: Int] {
                for (cat, amount) in byCategory {
                    let expense = PropertyExpense(
                        homeId: home.id,
                        amount: amount,
                        category: cat,
                        vendor: "パシャからの取込",
                        source: "pasha"
                    )
                    context.insert(expense)
                }
                try? context.save()
            }
        } else {
            // Open Pasha app
            if let url = URL(string: "pasha://export?destination=kagi&homeId=\(home.id)") {
                UIApplication.shared.open(url)
            }
        }
    }
}

// MARK: - Add Expense View

struct PropertyExpenseAddView: View {
    let homeId: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var amount = ""
    @State private var category = "消耗品費"
    @State private var vendor = ""
    @State private var date = Date()
    @State private var notes = ""

    private let categories = ["消耗品費", "修繕費", "通信費", "光熱費", "保険料", "管理費", "清掃費", "広告費", "その他"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        KachaCard {
                            VStack(spacing: 14) {
                                HStack {
                                    Text("金額").font(.subheadline).foregroundColor(.secondary)
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Text("¥").foregroundColor(.kacha)
                                        TextField("0", text: $amount)
                                            .keyboardType(.numberPad)
                                            .multilineTextAlignment(.trailing)
                                            .foregroundColor(.white)
                                            .frame(width: 120)
                                    }
                                }

                                Divider().background(Color.kachaCardBorder)

                                HStack {
                                    Text("カテゴリ").font(.subheadline).foregroundColor(.secondary)
                                    Spacer()
                                    Picker("", selection: $category) {
                                        ForEach(categories, id: \.self) { Text($0) }
                                    }
                                    .tint(.kacha)
                                }

                                Divider().background(Color.kachaCardBorder)

                                HStack {
                                    Text("取引先").font(.subheadline).foregroundColor(.secondary)
                                    Spacer()
                                    TextField("店名など", text: $vendor)
                                        .multilineTextAlignment(.trailing)
                                        .foregroundColor(.white)
                                }

                                Divider().background(Color.kachaCardBorder)

                                DatePicker("日付", selection: $date, displayedComponents: .date)
                                    .foregroundColor(.white)
                                    .tint(.kacha)
                            }
                            .padding(16)
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .navigationTitle("経費を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let expense = PropertyExpense(
                            homeId: homeId,
                            amount: Int(amount) ?? 0,
                            category: category,
                            vendor: vendor,
                            date: date,
                            notes: notes
                        )
                        context.insert(expense)
                        dismiss()
                    }
                    .bold().foregroundColor(.kacha)
                    .disabled(amount.isEmpty)
                }
            }
        }
    }
}
