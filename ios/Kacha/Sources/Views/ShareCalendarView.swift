import SwiftUI
import SwiftData

struct ShareCalendarView: View {
    let home: Home
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ShareRecord.validFrom) private var allRecords: [ShareRecord]
    @State private var displayedMonth = Date()
    @State private var selectedRecord: ShareRecord?
    @State private var showRevokeConfirm = false
    @State private var revoking = false
    @State private var showNewShare = false
    @State private var didAutoShow = false

    private var records: [ShareRecord] {
        allRecords.filter { $0.homeId == home.id }
    }

    private var calendar: Calendar { Calendar.current }

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月"
        return f.string(from: displayedMonth)
    }

    private var daysInMonth: [Date] {
        let range = calendar.range(of: .day, in: .month, for: displayedMonth)!
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        return range.compactMap { day in
            calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: day))
        }
    }

    private var firstWeekday: Int {
        guard let first = daysInMonth.first else { return 0 }
        return (calendar.component(.weekday, from: first) + 5) % 7 // Mon=0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Month nav
                        HStack {
                            Button { shiftMonth(-1) } label: {
                                Image(systemName: "chevron.left").foregroundColor(.kacha)
                            }
                            Spacer()
                            Text(monthTitle).font(.headline).foregroundColor(.white)
                            Spacer()
                            Button { shiftMonth(1) } label: {
                                Image(systemName: "chevron.right").foregroundColor(.kacha)
                            }
                        }
                        .padding(.horizontal)

                        // Weekday headers
                        let weekdays = ["月", "火", "水", "木", "金", "土", "日"]
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                            ForEach(weekdays, id: \.self) { day in
                                Text(day).font(.caption2).foregroundColor(.secondary)
                            }

                            // Empty cells
                            ForEach(0..<firstWeekday, id: \.self) { _ in
                                Color.clear.frame(height: 44)
                            }

                            // Days
                            ForEach(daysInMonth, id: \.self) { date in
                                dayCell(date)
                            }
                        }
                        .padding(.horizontal, 8)

                        // Legend
                        HStack(spacing: 16) {
                            legendDot(.kachaSuccess, "有効")
                            legendDot(.kacha.opacity(0.4), "開始前")
                            legendDot(.secondary, "期限切れ")
                            legendDot(.kachaDanger, "取り消し")
                        }
                        .font(.caption2)

                        // Share list
                        if !records.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("シェア履歴").font(.subheadline).bold().foregroundColor(.white)
                                    .padding(.horizontal)
                                ForEach(records) { record in
                                    shareRow(record)
                                }
                            }
                        }

                        // New share button
                        Button { showNewShare = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                Text("新しいシェアを作成").bold()
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.kacha)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("シェア管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showNewShare) {
                HomeShareView(home: home)
            }
            .onAppear {
                // シェア履歴がなければ自動で新規シェア画面を開く
                if records.isEmpty && !didAutoShow {
                    didAutoShow = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showNewShare = true
                    }
                }
            }
            .alert("このシェアを取り消しますか？", isPresented: $showRevokeConfirm) {
                Button("取り消す", role: .destructive) {
                    if let record = selectedRecord {
                        Task { await revokeRecord(record) }
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                if let r = selectedRecord {
                    Text("\(formatted(r.validFrom)) 〜 \(formatted(r.expiresAt))\n取り消すと相手はアクセスできなくなります。")
                }
            }
        }
    }

    // MARK: - Day Cell

    private func dayCell(_ date: Date) -> some View {
        let shares = sharesForDate(date)
        let isToday = calendar.isDateInToday(date)
        return VStack(spacing: 2) {
            Text("\(calendar.component(.day, from: date))")
                .font(.caption)
                .foregroundColor(isToday ? .black : .white)
                .frame(width: 32, height: 32)
                .background(isToday ? Color.kacha : Color.clear)
                .clipShape(Circle())

            if !shares.isEmpty {
                HStack(spacing: 2) {
                    ForEach(shares.prefix(3)) { record in
                        Circle()
                            .fill(dotColor(for: record))
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .frame(height: 44)
    }

    private func sharesForDate(_ date: Date) -> [ShareRecord] {
        records.filter { record in
            let start = calendar.startOfDay(for: record.validFrom)
            let end = calendar.startOfDay(for: record.expiresAt)
            let day = calendar.startOfDay(for: date)
            return day >= start && day <= end
        }
    }

    private func dotColor(for record: ShareRecord) -> Color {
        if record.revoked { return .kachaDanger }
        if record.isActive { return .kachaSuccess }
        if record.isExpired { return .secondary }
        return .kacha.opacity(0.4)
    }

    // MARK: - Share Row

    private func shareRow(_ record: ShareRecord) -> some View {
        KachaCard {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(dotColor(for: record))
                    .frame(width: 4, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(formatted(record.validFrom)) 〜 \(formatted(record.expiresAt))")
                        .font(.caption).foregroundColor(.white)
                    Text(record.statusLabel)
                        .font(.caption2)
                        .foregroundColor(record.isActive ? .kachaSuccess : .secondary)
                }

                Spacer()

                if record.isActive || Date() < record.validFrom {
                    Button {
                        selectedRecord = record
                        showRevokeConfirm = true
                    } label: {
                        Text("取り消す")
                            .font(.caption2).bold()
                            .foregroundColor(.kachaDanger)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.kachaDanger.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(12)
        }
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func shiftMonth(_ delta: Int) {
        withAnimation {
            displayedMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth)!
        }
    }

    private func revokeRecord(_ record: ShareRecord) async {
        revoking = true
        defer { revoking = false }
        do {
            try await ShareClient.revokeShare(token: record.token, ownerToken: record.ownerToken)
            record.revoked = true
            try? context.save()
        } catch {
            // サーバー到達不能でもローカルで取り消しマーク
            record.revoked = true
            try? context.save()
        }
    }

    // MARK: - Helpers

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f.string(from: date)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundColor(.secondary)
        }
    }
}
