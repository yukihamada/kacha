import SwiftUI
import SwiftData

// MARK: - Vault Tab (no Face ID — crashes on some devices)

struct VaultTabWrapper: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SecureItem.sortOrder) private var items: [SecureItem]
    @State private var searchText = ""
    @State private var selectedCategory = "all"
    @State private var showAdd = false
    @State private var editingItem: SecureItem?
    @State private var revealedIds = Set<String>()
    @State private var copiedId: String?

    private var filtered: [SecureItem] {
        var list = items
        if selectedCategory != "all" {
            list = list.filter { $0.category == selectedCategory }
        }
        if !searchText.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.username.localizedCaseInsensitiveContains(searchText)
            }
        }
        return list
    }

    private var categoriesWithCounts: [(key: String, label: String, icon: String, count: Int)] {
        let all: [(String, String, String)] = [
            ("all", "すべて", "tray.full.fill"),
            ("apikey", "API", "chevron.left.forwardslash.chevron.right"),
            ("password", "PW", "key.fill"),
            ("wifi", "Wi-Fi", "wifi"),
            ("pin", "PIN", "lock.fill"),
            ("card", "Card", "creditcard.fill"),
            ("note", "Note", "note.text"),
        ]
        return all.compactMap { key, label, icon in
            let count = key == "all" ? items.count : items.filter { $0.category == key }.count
            if count > 0 || key == "all" { return (key, label, icon, count) }
            return nil
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                if items.isEmpty && searchText.isEmpty {
                    emptyView
                } else {
                    mainContent
                }
            }
            .navigationTitle("鍵管理")
            .searchable(text: $searchText, prompt: "検索")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                VaultItemSheet(item: nil)
            }
            .sheet(item: $editingItem) { item in
                VaultItemSheet(item: item)
            }
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "key.viewfinder")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text("鍵を追加しましょう").font(.headline)
            Text("APIキー、パスワード、Wi-Fi等を\n暗号化して安全に管理").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button { showAdd = true } label: {
                Label("追加する", systemImage: "plus.circle.fill")
                    .font(.subheadline).bold().foregroundColor(.black)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(Color.orange).clipShape(Capsule())
            }
            Spacer()
        }
    }

    // MARK: - Main

    private var mainContent: some View {
        List {
            // Category pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(categoriesWithCounts, id: \.key) { cat in
                        Button {
                            withAnimation { selectedCategory = cat.key }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: cat.icon).font(.system(size: 10))
                                Text(cat.label).font(.caption2)
                                if cat.key != "all" {
                                    Text("\(cat.count)").font(.system(size: 9, weight: .bold, design: .rounded))
                                }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(selectedCategory == cat.key ? Color.orange : Color(.tertiarySystemGroupedBackground))
                            .foregroundColor(selectedCategory == cat.key ? .black : .primary)
                            .clipShape(Capsule())
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)

            ForEach(filtered) { item in
                itemRow(item)
                    .contentShape(Rectangle())
                    .onTapGesture { editingItem = item }
            }
            .onDelete { offsets in
                for i in offsets { context.delete(filtered[i]) }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Row

    private func itemRow(_ item: SecureItem) -> some View {
        let revealed = revealedIds.contains(item.id)
        let copied = copiedId == item.id
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorFor(item.category).opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: iconFor(item.category))
                    .font(.system(size: 15)).foregroundColor(colorFor(item.category))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline).bold().lineLimit(1)
                if !item.username.isEmpty {
                    Text(item.username).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                if revealed {
                    Text(VaultEncryption.decrypt(item.encryptedValue))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.orange).textSelection(.enabled).lineLimit(2)
                }
            }
            Spacer()
            HStack(spacing: 2) {
                Button {
                    withAnimation {
                        if revealed { revealedIds.remove(item.id) } else { revealedIds.insert(item.id) }
                    }
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye").font(.caption).foregroundColor(.secondary).frame(width: 32, height: 32)
                }.buttonStyle(.plain)
                Button {
                    UIPasteboard.general.string = VaultEncryption.decrypt(item.encryptedValue)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation { copiedId = item.id }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { if copiedId == item.id { copiedId = nil } }
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.caption).foregroundColor(copied ? .green : .secondary).frame(width: 32, height: 32)
                }.buttonStyle(.plain)
            }
        }.padding(.vertical, 4)
    }

    private func iconFor(_ c: String) -> String {
        switch c {
        case "password": return "key.fill"
        case "apikey": return "chevron.left.forwardslash.chevron.right"
        case "wifi": return "wifi"
        case "pin": return "lock.fill"
        case "card": return "creditcard.fill"
        case "note": return "note.text"
        default: return "key.fill"
        }
    }
    private func colorFor(_ c: String) -> Color {
        switch c {
        case "apikey": return .blue
        case "password": return .orange
        case "wifi": return .green
        case "pin": return .red
        case "card": return .purple
        case "note": return .cyan
        default: return .orange
        }
    }
}

// MARK: - Add / Edit

struct VaultItemSheet: View {
    let item: SecureItem?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var category = "apikey"
    @State private var username = ""
    @State private var value = ""
    @State private var url = ""
    @State private var note = ""
    @State private var showValue = false

    var body: some View {
        NavigationStack {
            Form {
                Section("基本情報") {
                    TextField("名前", text: $title).autocorrectionDisabled()
                    Picker("カテゴリ", selection: $category) {
                        Label("APIキー", systemImage: "chevron.left.forwardslash.chevron.right").tag("apikey")
                        Label("パスワード", systemImage: "key.fill").tag("password")
                        Label("Wi-Fi", systemImage: "wifi").tag("wifi")
                        Label("暗証番号", systemImage: "lock.fill").tag("pin")
                        Label("カード", systemImage: "creditcard.fill").tag("card")
                        Label("メモ", systemImage: "note.text").tag("note")
                    }
                }
                Section("値") {
                    if ["password", "wifi"].contains(category) {
                        TextField("ユーザー名 / SSID", text: $username)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                    HStack {
                        Group {
                            if showValue { TextField("値", text: $value) }
                            else { SecureField("値", text: $value) }
                        }.autocorrectionDisabled().textInputAutocapitalization(.never)
                        Button { showValue.toggle() } label: {
                            Image(systemName: showValue ? "eye.slash" : "eye").foregroundColor(.secondary)
                        }
                    }
                }
                Section {
                    TextField("URL (任意)", text: $url).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("メモ (任意)", text: $note)
                }
            }
            .navigationTitle(item == nil ? "追加" : "編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.bold().disabled(title.isEmpty || value.isEmpty)
                }
            }
            .onAppear {
                if let item {
                    title = item.title; category = item.category; username = item.username
                    value = VaultEncryption.decrypt(item.encryptedValue); url = item.url; note = item.note
                }
            }
        }
    }

    private func save() {
        let t = item ?? SecureItem(homeId: "global", title: title, category: category)
        t.title = title; t.category = category; t.username = username
        t.encryptedValue = VaultEncryption.encrypt(value); t.url = url; t.note = note; t.updatedAt = Date()
        if item == nil { context.insert(t) }
        dismiss()
    }
}
