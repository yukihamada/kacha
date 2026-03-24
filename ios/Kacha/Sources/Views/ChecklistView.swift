import SwiftUI
import SwiftData

struct ChecklistView: View {
    let home: Home
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ChecklistItem.sortOrder) private var allItems: [ChecklistItem]
    @State private var selectedTab = "checkin"
    @State private var newItemText = ""

    private var items: [ChecklistItem] {
        allItems.filter { $0.homeId == home.id && $0.category == selectedTab }
    }

    private var completedCount: Int { items.filter(\.isCompleted).count }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Tab picker
                    Picker("", selection: $selectedTab) {
                        Text("チェックイン").tag("checkin")
                        Text("チェックアウト").tag("checkout")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Progress
                    if !items.isEmpty {
                        HStack {
                            Text("\(completedCount)/\(items.count) 完了")
                                .font(.caption).foregroundColor(.secondary)
                            Spacer()
                            if completedCount == items.count && !items.isEmpty {
                                Label("完了!", systemImage: "checkmark.seal.fill")
                                    .font(.caption).foregroundColor(.kachaSuccess)
                            }
                            Button("リセット") {
                                items.forEach { $0.isCompleted = false }
                            }
                            .font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                        ProgressView(value: Double(completedCount), total: Double(max(items.count, 1)))
                            .tint(.kacha)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                    }

                    // Items
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(items) { item in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        item.isCompleted.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundColor(item.isCompleted ? .kachaSuccess : .secondary)
                                        Text(item.title)
                                            .font(.subheadline)
                                            .foregroundColor(item.isCompleted ? .secondary : .white)
                                            .strikethrough(item.isCompleted)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                                    .background(Color.kachaCard)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kachaCardBorder))
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        context.delete(item)
                                    } label: { Label("削除", systemImage: "trash") }
                                }
                            }

                            // Add new item
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle").foregroundColor(.kacha)
                                TextField("項目を追加...", text: $newItemText)
                                    .foregroundColor(.white)
                                    .onSubmit { addItem() }
                                if !newItemText.isEmpty {
                                    Button { addItem() } label: {
                                        Text("追加").font(.caption).bold().foregroundColor(.kacha)
                                    }
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(Color.kachaCard.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("チェックリスト")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
            .onAppear { seedDefaultsIfNeeded() }
        }
    }

    private func addItem() {
        let text = newItemText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let item = ChecklistItem(homeId: home.id, title: text, category: selectedTab, sortOrder: items.count)
        context.insert(item)
        newItemText = ""
    }

    private func seedDefaultsIfNeeded() {
        let existing = allItems.filter { $0.homeId == home.id }
        guard existing.isEmpty else { return }
        for (i, title) in ChecklistItem.defaultCheckIn.enumerated() {
            context.insert(ChecklistItem(homeId: home.id, title: title, category: "checkin", sortOrder: i))
        }
        for (i, title) in ChecklistItem.defaultCheckOut.enumerated() {
            context.insert(ChecklistItem(homeId: home.id, title: title, category: "checkout", sortOrder: i))
        }
    }
}
