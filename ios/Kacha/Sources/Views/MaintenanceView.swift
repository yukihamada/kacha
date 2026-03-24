import SwiftUI
import SwiftData

struct MaintenanceView: View {
    let home: Home
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MaintenanceTask.createdAt) private var allTasks: [MaintenanceTask]
    @Query(sort: \NearbyPlace.sortOrder) private var allPlaces: [NearbyPlace]
    @State private var showAddTask = false
    @State private var showAddPlace = false
    @State private var newTaskTitle = ""
    @State private var newTaskDays = 90
    @State private var newPlaceName = ""
    @State private var newPlaceCategory = "convenience"
    @State private var newPlaceNote = ""
    @State private var selectedTab = "maintenance"

    private var tasks: [MaintenanceTask] { allTasks.filter { $0.homeId == home.id } }
    private var places: [NearbyPlace] { allPlaces.filter { $0.homeId == home.id } }
    private var overdueTasks: [MaintenanceTask] { tasks.filter(\.isOverdue) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                VStack(spacing: 0) {
                    Picker("", selection: $selectedTab) {
                        Text("メンテナンス").tag("maintenance")
                        Text("近隣施設").tag("places")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16).padding(.top, 8)

                    ScrollView {
                        if selectedTab == "maintenance" {
                            maintenanceContent
                        } else {
                            placesContent
                        }
                    }
                }
            }
            .navigationTitle("家の管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
            .onAppear { seedDefaultsIfNeeded() }
        }
    }

    // MARK: - Maintenance

    private var maintenanceContent: some View {
        VStack(spacing: 12) {
            if !overdueTasks.isEmpty {
                KachaCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.kachaDanger)
                            Text("期限切れ \(overdueTasks.count)件").font(.subheadline).bold().foregroundColor(.kachaDanger)
                        }
                        ForEach(overdueTasks) { task in
                            taskRow(task)
                        }
                    }
                    .padding(16)
                }
            }

            ForEach(tasks.filter { !$0.isOverdue }) { task in
                KachaCard { taskRow(task).padding(16) }
            }

            // Add
            Button { showAddTask = true } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("メンテナンス項目を追加")
                }
                .font(.subheadline).foregroundColor(.kacha)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color.kacha.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .alert("メンテナンス追加", isPresented: $showAddTask) {
                TextField("項目名", text: $newTaskTitle)
                TextField("間隔（日）", value: $newTaskDays, format: .number)
                Button("追加") { addTask() }
                Button("キャンセル", role: .cancel) { newTaskTitle = "" }
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 40)
    }

    private func taskRow(_ task: MaintenanceTask) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(task.isOverdue ? Color.kachaDanger.opacity(0.15) : Color.kachaSuccess.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: task.isOverdue ? "exclamationmark.triangle" : "wrench.and.screwdriver")
                    .font(.system(size: 16))
                    .foregroundColor(task.isOverdue ? .kachaDanger : .kachaSuccess)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.subheadline).foregroundColor(.white)
                if task.isOverdue {
                    Text("\(-task.daysUntilDue)日超過").font(.caption).foregroundColor(.kachaDanger)
                } else {
                    Text("あと\(task.daysUntilDue)日").font(.caption).foregroundColor(.secondary)
                }
                Text("\(task.intervalDays)日ごと").font(.caption2).foregroundColor(.secondary.opacity(0.6))
            }
            Spacer()
            Button {
                withAnimation { task.lastCompletedAt = Date() }
            } label: {
                Text("完了").font(.caption).bold()
                    .foregroundColor(.kachaSuccess)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.kachaSuccess.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { context.delete(task) } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    // MARK: - Places

    private var placesContent: some View {
        VStack(spacing: 12) {
            ForEach(NearbyPlace.categoryInfo, id: \.key) { cat in
                let filtered = places.filter { $0.category == cat.key }
                if !filtered.isEmpty {
                    KachaCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: cat.icon).foregroundColor(.kacha)
                                Text(cat.label).font(.subheadline).bold().foregroundColor(.white)
                            }
                            ForEach(filtered) { place in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(place.name).font(.subheadline).foregroundColor(.white)
                                        if !place.note.isEmpty {
                                            Text(place.note).font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { context.delete(place) } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }

            Button { showAddPlace = true } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("施設を追加")
                }
                .font(.subheadline).foregroundColor(.kacha)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color.kacha.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .alert("近隣施設を追加", isPresented: $showAddPlace) {
                TextField("名前", text: $newPlaceName)
                TextField("メモ（距離など）", text: $newPlaceNote)
                Button("追加") { addPlace() }
                Button("キャンセル", role: .cancel) { newPlaceName = "" }
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 40)
    }

    // MARK: - Actions

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        context.insert(MaintenanceTask(homeId: home.id, title: title, intervalDays: newTaskDays))
        newTaskTitle = ""
        newTaskDays = 90
    }

    private func addPlace() {
        let name = newPlaceName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        context.insert(NearbyPlace(homeId: home.id, name: name, category: newPlaceCategory,
                                   note: newPlaceNote, sortOrder: places.count))
        newPlaceName = ""
        newPlaceNote = ""
    }

    private func seedDefaultsIfNeeded() {
        let existing = allTasks.filter { $0.homeId == home.id }
        guard existing.isEmpty else { return }
        for (title, days) in MaintenanceTask.defaults {
            context.insert(MaintenanceTask(homeId: home.id, title: title, intervalDays: days))
        }
    }
}
