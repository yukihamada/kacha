import SwiftUI
import SwiftData

/// Minimal vault tab - no Face ID, no complex views
struct VaultTabWrapper: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SecureItem.sortOrder) private var items: [SecureItem]
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView("鍵がありません", systemImage: "key", description: Text("右上の＋ボタンで追加"))
                } else {
                    ForEach(items) { item in
                        HStack {
                            Image(systemName: iconFor(item.category))
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(item.title).font(.subheadline).bold()
                                if !item.username.isEmpty {
                                    Text(item.username).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Text("••••••••").font(.caption).foregroundColor(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) { context.delete(item) } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("鍵管理")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                SimpleVaultAdd()
            }
        }
    }

    private func iconFor(_ category: String) -> String {
        switch category {
        case "password": return "key.fill"
        case "apikey": return "chevron.left.forwardslash.chevron.right"
        case "wifi": return "wifi"
        case "pin": return "lock.fill"
        case "card": return "creditcard.fill"
        case "note": return "note.text"
        default: return "key.fill"
        }
    }
}

struct SimpleVaultAdd: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var value = ""
    @State private var category = "apikey"

    var body: some View {
        NavigationStack {
            Form {
                TextField("名前 (例: FLY_API_TOKEN)", text: $title)
                    .autocorrectionDisabled()
                SecureField("値", text: $value)
                Picker("カテゴリ", selection: $category) {
                    Text("APIキー").tag("apikey")
                    Text("パスワード").tag("password")
                    Text("Wi-Fi").tag("wifi")
                    Text("暗証番号").tag("pin")
                    Text("メモ").tag("note")
                }
            }
            .navigationTitle("追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard !title.isEmpty, !value.isEmpty else { return }
                        let item = SecureItem(homeId: "global", title: title, category: category)
                        item.encryptedValue = VaultEncryption.encrypt(value)
                        context.insert(item)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}
