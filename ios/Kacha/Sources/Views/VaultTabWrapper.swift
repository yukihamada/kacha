import SwiftUI
import SwiftData
import LocalAuthentication

// MARK: - Main Vault Tab

struct VaultTabWrapper: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SecureItem.sortOrder) private var items: [SecureItem]
    @State private var searchText = ""
    @State private var selectedCategory = "all"
    @State private var showAdd = false
    @State private var editingItem: SecureItem?
    @State private var revealedIds = Set<String>()
    @State private var isLocked = true
    @State private var copiedId: String?

    private var filtered: [SecureItem] {
        var list = items
        if selectedCategory != "all" {
            list = list.filter { $0.category == selectedCategory }
        }
        if !searchText.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.username.localizedCaseInsensitiveContains(searchText) ||
                $0.url.localizedCaseInsensitiveContains(searchText)
            }
        }
        return list
    }

    private var categories: [(key: String, label: String, icon: String, count: Int)] {
        let cats: [(String, String, String)] = [
            ("all", "すべて", "tray.full.fill"),
            ("apikey", "APIキー", "chevron.left.forwardslash.chevron.right"),
            ("password", "パスワード", "key.fill"),
            ("wifi", "Wi-Fi", "wifi"),
            ("pin", "暗証番号", "lock.fill"),
            ("card", "カード", "creditcard.fill"),
            ("note", "メモ", "note.text"),
        ]
        return cats.map { key, label, icon in
            let count = key == "all" ? items.count : items.filter { $0.category == key }.count
            return (key, label, icon, count)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if isLocked {
                    lockView
                } else if items.isEmpty && searchText.isEmpty {
                    emptyView
                } else {
                    mainContent
                }
            }
            .navigationTitle("鍵管理")
            .searchable(text: $searchText, prompt: "検索")
            .toolbar {
                if !isLocked {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showAdd = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button { withAnimation { isLocked = true } } label: {
                            Image(systemName: "lock.fill").font(.caption)
                        }
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
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            doAuth()
        }
    }

    // MARK: - Lock Screen

    private var lockView: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(.linearGradient(colors: [.orange.opacity(0.2), .yellow.opacity(0.1)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 100, height: 100)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.linearGradient(colors: [.orange, .yellow],
                                                     startPoint: .top, endPoint: .bottom))
            }
            VStack(spacing: 8) {
                Text("鍵管理").font(.title2).bold()
                Text("Face ID で解除してアクセス")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            Button { doAuth() } label: {
                Label("解除する", systemImage: "faceid")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 32).padding(.vertical, 14)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }
            Spacer()
            Text("\(items.count) 件のアイテムを保護中")
                .font(.caption).foregroundColor(.secondary)
                .padding(.bottom, 20)
        }
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "key.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("鍵を追加しましょう")
                .font(.headline)
            Text("APIキー、パスワード、Wi-Fi情報などを\n暗号化して安全に管理できます")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button { showAdd = true } label: {
                Label("追加する", systemImage: "plus.circle.fill")
                    .font(.subheadline).bold()
                    .foregroundColor(.black)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Main Content

    private var mainContent: some View {
        List {
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories.filter { $0.count > 0 || $0.key == "all" }, id: \.key) { cat in
                        Button {
                            withAnimation { selectedCategory = cat.key }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: cat.icon).font(.caption2)
                                Text(cat.label).font(.caption)
                                if cat.count > 0 && cat.key != "all" {
                                    Text("\(cat.count)")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(selectedCategory == cat.key ? Color.black.opacity(0.2) : Color.secondary.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(selectedCategory == cat.key ? Color.orange : Color(.tertiarySystemGroupedBackground))
                            .foregroundColor(selectedCategory == cat.key ? .black : .primary)
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            // Items
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

    // MARK: - Item Row

    private func itemRow(_ item: SecureItem) -> some View {
        let isRevealed = revealedIds.contains(item.id)
        let isCopied = copiedId == item.id

        return HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorFor(item.category).opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: iconFor(item.category))
                    .font(.system(size: 16))
                    .foregroundColor(colorFor(item.category))
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline).bold()
                    .lineLimit(1)
                if !item.username.isEmpty {
                    Text(item.username)
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if isRevealed {
                    Text(VaultEncryption.decrypt(item.encryptedValue))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.orange)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 4) {
                // Reveal
                Button {
                    withAnimation {
                        if isRevealed { revealedIds.remove(item.id) }
                        else { revealedIds.insert(item.id) }
                    }
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                // Copy
                Button {
                    UIPasteboard.general.string = VaultEncryption.decrypt(item.encryptedValue)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation { copiedId = item.id }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { if copiedId == item.id { copiedId = nil } }
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(isCopied ? .green : .secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

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

    private func colorFor(_ category: String) -> Color {
        switch category {
        case "apikey": return .blue
        case "password": return .orange
        case "wifi": return .green
        case "pin": return .red
        case "card": return .purple
        case "note": return .cyan
        default: return .orange
        }
    }

    private func doAuth() {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            withAnimation { isLocked = false }
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "鍵管理にアクセス") { success, _ in
            DispatchQueue.main.async {
                withAnimation { if success { isLocked = false } }
            }
        }
    }
}

// MARK: - Add / Edit Sheet

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

    private var isNew: Bool { item == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本情報") {
                    TextField("名前", text: $title)
                        .autocorrectionDisabled()
                    Picker("カテゴリ", selection: $category) {
                        Label("APIキー", systemImage: "chevron.left.forwardslash.chevron.right").tag("apikey")
                        Label("パスワード", systemImage: "key.fill").tag("password")
                        Label("Wi-Fi", systemImage: "wifi").tag("wifi")
                        Label("暗証番号", systemImage: "lock.fill").tag("pin")
                        Label("カード", systemImage: "creditcard.fill").tag("card")
                        Label("メモ", systemImage: "note.text").tag("note")
                    }
                }

                Section("認証情報") {
                    if category == "password" || category == "wifi" {
                        TextField("ユーザー名 / SSID", text: $username)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    HStack {
                        Group {
                            if showValue {
                                TextField("値", text: $value)
                            } else {
                                SecureField("値", text: $value)
                            }
                        }
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        Button { showValue.toggle() } label: {
                            Image(systemName: showValue ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if category == "password" || category == "apikey" {
                    Section("その他") {
                        TextField("URL (任意)", text: $url)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("メモ (任意)", text: $note)
                    }
                }

                if category == "apikey" {
                    Section {
                        Label("ChatWebと自動同期されます", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(isNew ? "追加" : "編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .bold()
                        .disabled(title.isEmpty || value.isEmpty)
                }
            }
            .onAppear {
                if let item {
                    title = item.title
                    category = item.category
                    username = item.username
                    value = VaultEncryption.decrypt(item.encryptedValue)
                    url = item.url
                    note = item.note
                }
            }
        }
    }

    private func save() {
        let target = item ?? SecureItem(homeId: "global", title: title, category: category)
        target.title = title
        target.category = category
        target.username = username
        target.encryptedValue = VaultEncryption.encrypt(value)
        target.url = url
        target.note = note
        target.updatedAt = Date()
        if item == nil { context.insert(target) }
        dismiss()
    }
}
