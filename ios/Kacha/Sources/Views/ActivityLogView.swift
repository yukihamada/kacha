import SwiftUI
import SwiftData

struct ActivityLogView: View {
    let home: Home
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ActivityLog.timestamp, order: .reverse) private var allLogs: [ActivityLog]
    @State private var filterAction = "all"
    @State private var isSyncing = false
    @State private var syncResult: String?

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
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await syncDeviceLogs() } } label: {
                        if isSyncing {
                            ProgressView().tint(.kacha)
                        } else {
                            Image(systemName: "arrow.clockwise").foregroundColor(.kacha)
                        }
                    }
                    .disabled(isSyncing)
                }
            }
            .onAppear { Task { await syncDeviceLogs() } }
            .overlay(alignment: .bottom) {
                if let result = syncResult {
                    Text(result)
                        .font(.caption).foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.kacha.opacity(0.9))
                        .clipShape(Capsule())
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation { syncResult = nil }
                            }
                        }
                }
            }
        }
    }

    private func syncDeviceLogs() async {
        isSyncing = true
        defer { isSyncing = false }
        let sesameUUIDs = home.sesameDeviceUUIDs
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let count = await DeviceLogSyncer.syncAll(
            context: context,
            homeId: home.id,
            sesameUUIDs: sesameUUIDs,
            sesameApiKey: home.sesameApiKey,
            switchBotToken: home.switchBotToken,
            switchBotSecret: home.switchBotSecret
        )
        withAnimation {
            syncResult = count > 0 ? "\(count)件の新しいログを取得" : "最新の状態です"
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
