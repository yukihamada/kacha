import SwiftUI
import SwiftData

struct ActivityLogView: View {
    let home: Home
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ActivityLog.timestamp, order: .reverse) private var allLogs: [ActivityLog]
    @State private var filterAction = "all"

    private var logs: [ActivityLog] {
        let homeLogs = allLogs.filter { $0.homeId == home.id }
        if filterAction == "all" { return homeLogs }
        return homeLogs.filter { $0.action == filterAction }
    }

    private var groupedByDate: [(String, [ActivityLog])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        let dict = Dictionary(grouping: logs) { formatter.string(from: $0.timestamp) }
        return dict.sorted { $0.key > $1.key }
    }

    private let filters: [(String, String)] = [
        ("all", "すべて"),
        ("lock", "施錠"),
        ("unlock", "解錠"),
        ("light_on", "照明ON"),
        ("light_off", "照明OFF"),
        ("scene", "シーン"),
        ("share_create", "シェア"),
        ("share_revoke", "取り消し"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filters, id: \.0) { key, label in
                                Button {
                                    withAnimation { filterAction = key }
                                } label: {
                                    Text(label)
                                        .font(.caption2).bold()
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(filterAction == key ? Color.kacha : Color.kacha.opacity(0.1))
                                        .foregroundColor(filterAction == key ? .black : .kacha)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 8)

                    if logs.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 40)).foregroundColor(.secondary)
                            Text("ログがありません").font(.subheadline).foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                                ForEach(groupedByDate, id: \.0) { date, entries in
                                    Section {
                                        ForEach(entries) { log in
                                            logRow(log)
                                        }
                                    } header: {
                                        HStack {
                                            Text(date).font(.caption).bold().foregroundColor(.secondary)
                                            Spacer()
                                            Text("\(entries.count)件").font(.caption2).foregroundColor(.secondary.opacity(0.6))
                                        }
                                        .padding(.horizontal, 16).padding(.vertical, 6)
                                        .background(Color.kachaBg)
                                    }
                                }
                            }
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationTitle("アクティビティログ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
        }
    }

    private func logRow(_ log: ActivityLog) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(hex: log.iconColor).opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: log.icon).font(.system(size: 14)).foregroundColor(Color(hex: log.iconColor))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(log.detail).font(.subheadline).foregroundColor(.white)
                HStack(spacing: 8) {
                    if !log.actor.isEmpty {
                        Text(log.actor).font(.caption2).foregroundColor(.kacha)
                    }
                    if !log.deviceName.isEmpty {
                        Text(log.deviceName).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Text(timeString(log.timestamp))
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
