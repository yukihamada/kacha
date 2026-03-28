import SwiftUI
import SwiftData
import Charts

// MARK: - Main View

struct AnalyticsDashboardView: View {
    let homes: [Home]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Booking.checkIn) private var allBookings: [Booking]
    @Query(sort: \UtilityRecord.month) private var allUtilities: [UtilityRecord]
    @Query(sort: \Expense.date) private var allExpenses: [Expense]

    @State private var selectedMonthOffset = 0   // 0 = current month
    @State private var showAddExpense = false
    @State private var selectedHomeId: String?    // nil = all homes
    @State private var exportTrigger = false

    // MARK: - Computed month

    private var cal: Calendar { Calendar.current }

    private var currentMonth: Date {
        cal.date(byAdding: .month, value: selectedMonthOffset, to: Date()) ?? Date()
    }

    private var monthKey: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        return f.string(from: currentMonth)
    }

    private var monthLabel: String {
        let f = DateFormatter(); f.dateFormat = "yyyy年M月"
        f.locale = Locale(identifier: "ja_JP")
        return f.string(from: currentMonth)
    }

    private var totalDaysInMonth: Int {
        let range = cal.range(of: .day, in: .month, for: currentMonth)
        return range?.count ?? 30
    }

    // MARK: - Filtered data helpers

    private func bookings(for home: Home) -> [Booking] {
        allBookings.filter {
            $0.homeId == home.id &&
            $0.status != "cancelled" &&
            monthKey(for: $0.checkIn) == monthKey
        }
    }

    private func expenses(for home: Home) -> [Expense] {
        allExpenses.filter { $0.homeId == home.id && $0.month == monthKey }
    }

    private func utilityExpenses(for home: Home) -> Int {
        allUtilities.filter { $0.homeId == home.id && $0.month == monthKey }
            .reduce(0) { $0 + $1.amount }
    }

    private func monthKey(for date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        return f.string(from: date)
    }

    // MARK: - KPIs per home for current month

    private func occupiedDays(_ home: Home) -> Int {
        let bkgs = bookings(for: home)
        // count unique days across all bookings
        var days = Set<Int>()
        for b in bkgs {
            var d = b.checkIn
            while d < b.checkOut && d < cal.date(byAdding: .month, value: 1, to: cal.startOfMonth(currentMonth))! {
                if monthKey(for: d) == monthKey {
                    days.insert(cal.ordinality(of: .day, in: .year, for: d) ?? 0)
                }
                d = cal.date(byAdding: .day, value: 1, to: d) ?? d
            }
        }
        return days.count
    }

    private func revenue(_ home: Home) -> Int {
        bookings(for: home).reduce(0) { $0 + $1.totalAmount }
    }

    private func totalExpensesAmount(_ home: Home) -> Int {
        expenses(for: home).reduce(0) { $0 + $1.amount } + utilityExpenses(for: home)
    }

    private func occupancyRate(_ home: Home) -> Double {
        guard totalDaysInMonth > 0 else { return 0 }
        return Double(occupiedDays(home)) / Double(totalDaysInMonth)
    }

    private func adr(_ home: Home) -> Double {
        let days = occupiedDays(home)
        guard days > 0 else { return 0 }
        return Double(revenue(home)) / Double(days)
    }

    private func revpar(_ home: Home) -> Double {
        guard totalDaysInMonth > 0 else { return 0 }
        return Double(revenue(home)) / Double(totalDaysInMonth)
    }

    // MARK: - 6-month trend

    private struct MonthPoint: Identifiable {
        let id = UUID()
        let label: String
        let revenue: Int
        let expenses: Int
        let occupancy: Double
    }

    private func trendPoints(for home: Home) -> [MonthPoint] {
        (0..<6).reversed().compactMap { offset -> MonthPoint? in
            guard let date = cal.date(byAdding: .month, value: -offset, to: Date()) else { return nil }
            let f = DateFormatter(); f.dateFormat = "yyyy-MM"
            let key = f.string(from: date)
            let label = String(key.suffix(2)) + "月"

            let rev = allBookings.filter {
                $0.homeId == home.id && $0.status != "cancelled" && f.string(from: $0.checkIn) == key
            }.reduce(0) { $0 + $1.totalAmount }

            let exp = allExpenses.filter { $0.homeId == home.id && $0.month == key }
                .reduce(0) { $0 + $1.amount }
            + allUtilities.filter { $0.homeId == home.id && $0.month == key }
                .reduce(0) { $0 + $1.amount }

            let daysInMonth = cal.range(of: .day, in: .month, for: date)?.count ?? 30
            let occ: Double = daysInMonth > 0 ? min(1.0, Double(rev > 0 ? max(1, rev / max(1, rev / max(1, daysInMonth))) : 0) / Double(daysInMonth)) : 0

            return MonthPoint(label: label, revenue: rev, expenses: exp, occupancy: occ)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                if homes.isEmpty {
                    analyticsEmptyState
                } else {
                ScrollView {
                    VStack(spacing: 20) {

                        // Month navigator
                        monthNavigator

                        // KPI cards grid (all homes or selected)
                        ForEach(homes) { home in
                            homeSection(home)
                        }

                        // Comparison table (only when multiple homes)
                        if homes.count > 1 {
                            comparisonTable
                        }

                        // Export buttons
                        exportSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
                }
            }
            .navigationTitle("詳細分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddExpense = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.kacha)
                    }
                }
            }
            .sheet(isPresented: $showAddExpense) {
                AddExpenseView(homes: homes)
            }
        }
    }

    // MARK: - Month Navigator

    private var monthNavigator: some View {
        HStack {
            Button {
                selectedMonthOffset -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(.kacha)
                    .padding(10)
                    .background(Color.kachaCard)
                    .clipShape(Circle())
            }

            Spacer()

            Text(monthLabel)
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            Button {
                if selectedMonthOffset < 0 { selectedMonthOffset += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(selectedMonthOffset < 0 ? .kacha : .secondary)
                    .padding(10)
                    .background(Color.kachaCard)
                    .clipShape(Circle())
            }
            .disabled(selectedMonthOffset >= 0)
        }
        .padding(.top, 8)
    }

    // MARK: - Per-home section

    @ViewBuilder
    private func homeSection(_ home: Home) -> some View {
        VStack(alignment: .leading, spacing: 12) {

            // Home name header
            HStack {
                Image(systemName: "house.fill")
                    .foregroundColor(.kacha)
                    .font(.caption)
                Text(home.name)
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
            }

            // KPI 3-up
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                kpiBox("稼働率", String(format: "%.0f%%", occupancyRate(home) * 100), .kachaSuccess)
                kpiBox("ADR", "¥\(Int(adr(home)))", .kacha)
                kpiBox("RevPAR", "¥\(Int(revpar(home)))", .kachaAccent)
            }

            // Revenue vs Expense summary
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                kpiBox("売上", "¥\(revenue(home))", .kachaSuccess)
                kpiBox("経費", "¥\(totalExpensesAmount(home))", .kachaDanger)
                let profit = revenue(home) - totalExpensesAmount(home)
                kpiBox("利益", "¥\(profit)", profit >= 0 ? .kacha : .kachaDanger)
            }

            // 6-month bar+line chart
            KachaCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("月次推移").font(.caption).bold().foregroundColor(.white)
                    let points = trendPoints(for: home)
                    Chart {
                        ForEach(points) { pt in
                            BarMark(
                                x: .value("月", pt.label),
                                y: .value("売上", pt.revenue)
                            )
                            .foregroundStyle(Color.kachaSuccess.opacity(0.8))
                            .cornerRadius(4)

                            BarMark(
                                x: .value("月", pt.label),
                                y: .value("経費", -pt.expenses)
                            )
                            .foregroundStyle(Color.kachaDanger.opacity(0.7))
                            .cornerRadius(4)
                        }
                    }
                    .frame(height: 140)

                    HStack(spacing: 16) {
                        legendDot(.kachaSuccess, "売上")
                        legendDot(.kachaDanger, "経費")
                    }
                    .font(.caption2)
                }
                .padding(14)
            }

            // Expense breakdown for this month
            expenseBreakdown(home)
        }
    }

    // MARK: - Expense Breakdown

    @ViewBuilder
    private func expenseBreakdown(_ home: Home) -> some View {
        let exps = expenses(for: home)
        let utilities = allUtilities.filter { $0.homeId == home.id && $0.month == monthKey }

        if !exps.isEmpty || !utilities.isEmpty {
            KachaCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("経費内訳").font(.caption).bold().foregroundColor(.white)

                    // UtilityRecord (光熱費)
                    ForEach(utilities) { u in
                        expenseRow(
                            icon: UtilityRecord.categories.first { $0.key == u.category }?.icon ?? "bolt.fill",
                            color: UtilityRecord.categories.first { $0.key == u.category }?.color ?? "F59E0B",
                            label: (UtilityRecord.categories.first { $0.key == u.category }?.label ?? "光熱費") + "（\(u.month)）",
                            amount: u.amount
                        )
                    }

                    // Expense entries
                    ForEach(exps) { e in
                        expenseRow(
                            icon: e.categoryIcon,
                            color: e.categoryColor,
                            label: e.categoryLabel + (e.notes.isEmpty ? "" : "（\(e.notes)）"),
                            amount: e.amount
                        )
                    }
                }
                .padding(14)
            }
        }
    }

    private func expenseRow(icon: String, color: String, label: String, amount: Int) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(Color(hex: color))
                .frame(width: 20)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("¥\(amount)")
                .font(.caption).bold()
                .foregroundColor(.white)
        }
    }

    // MARK: - Comparison Table

    private var comparisonTable: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("物件比較").font(.subheadline).bold().foregroundColor(.white)

                // Header
                HStack {
                    Text("物件").frame(maxWidth: .infinity, alignment: .leading)
                    Text("稼働率").frame(width: 54, alignment: .trailing)
                    Text("ADR").frame(width: 62, alignment: .trailing)
                    Text("利益").frame(width: 68, alignment: .trailing)
                }
                .font(.caption2)
                .foregroundColor(.secondary)

                Divider().background(Color.kachaCardBorder)

                ForEach(homes) { home in
                    let profit = revenue(home) - totalExpensesAmount(home)
                    HStack {
                        Text(home.name)
                            .font(.caption)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Text(String(format: "%.0f%%", occupancyRate(home) * 100))
                            .font(.caption).bold()
                            .foregroundColor(.kachaSuccess)
                            .frame(width: 54, alignment: .trailing)
                        Text("¥\(Int(adr(home)))")
                            .font(.caption)
                            .foregroundColor(.kacha)
                            .frame(width: 62, alignment: .trailing)
                        Text("¥\(profit)")
                            .font(.caption).bold()
                            .foregroundColor(profit >= 0 ? .kachaSuccess : .kachaDanger)
                            .frame(width: 68, alignment: .trailing)
                    }
                }
            }
            .padding(14)
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        VStack(spacing: 10) {
            exportButton(
                icon: "doc.richtext",
                title: "PDFレポート出力",
                subtitle: "\(monthLabel)のPDFを生成",
                color: .kachaAccent
            ) {
                exportPDF()
            }
            exportButton(
                icon: "tablecells",
                title: "CSV出力（確定申告用）",
                subtitle: "全期間の収支CSVを生成",
                color: .kachaSuccess
            ) {
                exportCSV()
            }
        }
    }

    private func exportButton(icon: String, title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            KachaCard {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(color)
                        .frame(width: 36, height: 36)
                        .background(color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.subheadline).bold().foregroundColor(.white)
                        Text(subtitle).font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(14)
            }
        }
    }

    // MARK: - Export Actions

    private func exportPDF() {
        guard let home = homes.first else { return }
        let report = buildReport(for: home)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let vc = scene.windows.first?.rootViewController else { return }
        ReportExportService.sharePDF(report: report, from: vc)
    }

    private func exportCSV() {
        let reports = homes.map { buildReport(for: $0) }
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let vc = scene.windows.first?.rootViewController else { return }
        let name = homes.count == 1 ? homes[0].name : "全物件"
        ReportExportService.shareCSV(reports: reports, homeName: name, from: vc)
    }

    private func buildReport(for home: Home) -> ReportExportService.MonthlyReport {
        let expBreakdown = Expense.categories.map { cat in
            let total = allExpenses.filter { $0.homeId == home.id && $0.month == monthKey && $0.category == cat.key }
                .reduce(0) { $0 + $1.amount }
            return (category: cat.label, amount: total)
        }.filter { $0.amount > 0 }

        return ReportExportService.MonthlyReport(
            homeName: home.name,
            period: monthLabel,
            revenue: revenue(home),
            bookingCount: bookings(for: home).count,
            occupiedDays: occupiedDays(home),
            totalDays: totalDaysInMonth,
            expenses: expBreakdown
        )
    }

    // MARK: - Empty State (no homes)

    private var analyticsEmptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 56))
                .foregroundColor(.kacha.opacity(0.3))
            Text("物件がありません")
                .font(.title3).bold()
                .foregroundColor(.white)
            Text("設定から物件を追加すると\n収益・稼働率などの分析が表示されます")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("物件がありません。設定から物件を追加してください。")
    }

    // MARK: - Small helpers

    private func kpiBox(_ label: String, _ value: String, _ color: Color) -> some View {
        KachaCard {
            VStack(spacing: 4) {
                Text(value)
                    .font(.subheadline).bold()
                    .foregroundColor(color)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundColor(.secondary)
        }
    }
}

// MARK: - Calendar helper

private extension Calendar {
    func startOfMonth(_ date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}

// MARK: - Add Expense Sheet

struct AddExpenseView: View {
    let homes: [Home]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedHomeId: String
    @State private var category = "cleaning"
    @State private var amountText = ""
    @State private var notes = ""
    @State private var date = Date()
    @State private var showImagePicker = false
    @State private var receiptImage: UIImage?

    init(homes: [Home]) {
        self.homes = homes
        _selectedHomeId = State(initialValue: homes.first?.id ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                Form {
                    Section {
                        Picker("物件", selection: $selectedHomeId) {
                            ForEach(homes, id: \.id) { h in
                                Text(h.name).tag(h.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .foregroundColor(.white)
                    } header: {
                        Text("対象物件").foregroundColor(.secondary)
                    }
                    .listRowBackground(Color.kachaCard)

                    Section {
                        Picker("カテゴリ", selection: $category) {
                            ForEach(Expense.categories, id: \.key) { cat in
                                Label(cat.label, systemImage: cat.icon).tag(cat.key)
                            }
                        }
                        .pickerStyle(.menu)

                        HStack {
                            Text("¥")
                                .foregroundColor(.secondary)
                            TextField("金額", text: $amountText)
                                .keyboardType(.numberPad)
                                .foregroundColor(.white)
                        }

                        DatePicker("日付", selection: $date, displayedComponents: .date)
                            .foregroundColor(.white)
                            .environment(\.locale, Locale(identifier: "ja_JP"))

                        TextField("メモ（任意）", text: $notes)
                            .foregroundColor(.white)
                    } header: {
                        Text("経費情報").foregroundColor(.secondary)
                    }
                    .listRowBackground(Color.kachaCard)

                    Section {
                        Button {
                            showImagePicker = true
                        } label: {
                            HStack {
                                Image(systemName: receiptImage == nil ? "camera.fill" : "checkmark.circle.fill")
                                    .foregroundColor(receiptImage == nil ? .kacha : .kachaSuccess)
                                Text(receiptImage == nil ? "レシートを撮影" : "レシート登録済み")
                                    .foregroundColor(.white)
                            }
                        }

                        if let img = receiptImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    } header: {
                        Text("レシート（任意）").foregroundColor(.secondary)
                    }
                    .listRowBackground(Color.kachaCard)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("経費を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .bold()
                        .foregroundColor(canSave ? .kacha : .secondary)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePickerView(image: $receiptImage)
            }
        }
    }

    private var canSave: Bool {
        !selectedHomeId.isEmpty && Int(amountText) != nil && !(amountText.isEmpty)
    }

    private func save() {
        guard let amount = Int(amountText) else { return }
        let imageData = receiptImage?.jpegData(compressionQuality: 0.7)
        let expense = Expense(
            homeId: selectedHomeId,
            category: category,
            amount: amount,
            date: date,
            notes: notes,
            receiptImageData: imageData
        )
        modelContext.insert(expense)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Image Picker wrapper

struct ImagePickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView
        init(_ parent: ImagePickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
