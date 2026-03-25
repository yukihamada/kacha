import SwiftUI
import SwiftData
import LocalAuthentication

struct VaultView: View {
    let home: Home
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SecureItem.sortOrder) private var allItems: [SecureItem]
    @State private var isUnlocked = false
    @State private var showAdd = false
    @State private var searchText = ""
    @State private var selectedCategory = "all"
    @State private var revealedIds = Set<String>()

    private var items: [SecureItem] {
        var filtered = allItems.filter { $0.homeId == home.id }
        if selectedCategory != "all" {
            filtered = filtered.filter { $0.category == selectedCategory }
        }
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.username.localizedCaseInsensitiveContains(searchText) ||
                $0.url.localizedCaseInsensitiveContains(searchText)
            }
        }
        return filtered
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                if !isUnlocked {
                    lockScreen
                } else {
                    vaultContent
                }
            }
            .navigationTitle("パスワード管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
                if isUnlocked {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showAdd = true } label: {
                            Image(systemName: "plus.circle.fill").foregroundColor(.kacha)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                VaultItemEditor(home: home, item: nil)
            }
        }
        .onAppear { authenticate() }
    }

    // MARK: - Lock Screen

    private var lockScreen: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(Color.kacha.opacity(0.12)).frame(width: 80, height: 80)
                Image(systemName: "lock.shield.fill").font(.system(size: 36)).foregroundColor(.kacha)
            }
            Text("Face ID / Touch IDで\nロックを解除してください")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button { authenticate() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "faceid")
                    Text("解除する")
                }
                .foregroundColor(.black).font(.subheadline).bold()
                .padding(.horizontal, 28).padding(.vertical, 12)
                .background(Color.kacha)
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Vault Content

    private var vaultContent: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("検索", text: $searchText)
                    .foregroundColor(.white).autocorrectionDisabled()
            }
            .padding(10)
            .background(Color.kachaCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16).padding(.top, 8)

            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip("all", "すべて")
                    ForEach(SecureItem.categories, id: \.key) { cat in
                        categoryChip(cat.key, cat.label)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }

            // Items
            if items.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "shield.checkered").font(.system(size: 40)).foregroundColor(.secondary)
                    Text("保存されたパスワードはありません").font(.subheadline).foregroundColor(.secondary)
                    Button { showAdd = true } label: {
                        Text("追加する").font(.caption).foregroundColor(.kacha)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { item in
                            itemRow(item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: - Item Row

    private func itemRow(_ item: SecureItem) -> some View {
        let catInfo = SecureItem.categories.first { $0.key == item.category }
        let isRevealed = revealedIds.contains(item.id)

        return KachaCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.kacha.opacity(0.12)).frame(width: 36, height: 36)
                        Image(systemName: catInfo?.icon ?? "key.fill")
                            .font(.system(size: 14)).foregroundColor(.kacha)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline).bold().foregroundColor(.white)
                        if !item.username.isEmpty {
                            Text(item.username).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    // Copy button
                    Button {
                        UIPasteboard.general.string = item.encryptedValue
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "doc.on.doc").font(.caption).foregroundColor(.kachaAccent)
                    }
                    // Reveal toggle
                    Button {
                        withAnimation {
                            if isRevealed { revealedIds.remove(item.id) }
                            else { revealedIds.insert(item.id) }
                        }
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                if isRevealed {
                    Text(item.encryptedValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.kacha)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.kacha.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                if !item.url.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "link").font(.system(size: 10))
                        Text(item.url).font(.caption2).lineLimit(1)
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(14)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { context.delete(item) } label: {
                Label("削除", systemImage: "trash")
            }
        }
        .contextMenu {
            Button { UIPasteboard.general.string = item.encryptedValue } label: {
                Label("パスワードをコピー", systemImage: "doc.on.doc")
            }
            if !item.username.isEmpty {
                Button { UIPasteboard.general.string = item.username } label: {
                    Label("ユーザー名をコピー", systemImage: "person")
                }
            }
            Button(role: .destructive) { context.delete(item) } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    // MARK: - Category Chip

    private func categoryChip(_ key: String, _ label: String) -> some View {
        Button {
            withAnimation { selectedCategory = key }
        } label: {
            Text(label).font(.caption2).bold()
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selectedCategory == key ? Color.kacha : Color.kacha.opacity(0.1))
                .foregroundColor(selectedCategory == key ? .black : .kacha)
                .clipShape(Capsule())
        }
    }

    // MARK: - Auth

    private func authenticate() {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            isUnlocked = true // No biometrics available, allow access
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "パスワード管理にアクセス") { success, _ in
            DispatchQueue.main.async {
                isUnlocked = success
            }
        }
    }
}

// MARK: - Vault Item Editor

struct VaultItemEditor: View {
    let home: Home
    let item: SecureItem?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var category = "password"
    @State private var username = ""
    @State private var password = ""
    @State private var url = ""
    @State private var note = ""
    @State private var showPassword = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        // Category
                        KachaCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("カテゴリ").font(.caption).foregroundColor(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(SecureItem.categories, id: \.key) { cat in
                                            Button { category = cat.key } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: cat.icon).font(.caption)
                                                    Text(cat.label).font(.caption)
                                                }
                                                .padding(.horizontal, 10).padding(.vertical, 6)
                                                .background(category == cat.key ? Color.kacha : Color.kacha.opacity(0.1))
                                                .foregroundColor(category == cat.key ? .black : .kacha)
                                                .clipShape(Capsule())
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(14)
                        }

                        // Fields
                        KachaCard {
                            VStack(spacing: 14) {
                                field("タイトル", "例: Gmail, AWS", $title)
                                Divider().background(Color.kachaCardBorder)
                                field("ユーザー名 / メール", "user@example.com", $username)
                                Divider().background(Color.kachaCardBorder)
                                HStack {
                                    if showPassword {
                                        field("パスワード / キー", "••••••••", $password)
                                    } else {
                                        HStack {
                                            Text("パスワード").font(.caption).foregroundColor(.secondary).frame(width: 90, alignment: .leading)
                                            SecureField("••••••••", text: $password)
                                                .foregroundColor(.white)
                                        }
                                    }
                                    Button { showPassword.toggle() } label: {
                                        Image(systemName: showPassword ? "eye.slash" : "eye")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Divider().background(Color.kachaCardBorder)

                                // Generate password button
                                Button { password = generatePassword() } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "dice.fill")
                                        Text("パスワード生成").bold()
                                    }
                                    .font(.caption).foregroundColor(.kacha)
                                }

                                Divider().background(Color.kachaCardBorder)
                                field("URL", "https://example.com", $url)
                                Divider().background(Color.kachaCardBorder)
                                field("メモ", "メモ", $note)
                            }
                            .padding(14)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
                }
            }
            .navigationTitle(item == nil ? "追加" : "編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .foregroundColor(.kacha)
                        .disabled(title.isEmpty || password.isEmpty)
                }
            }
            .onAppear {
                if let item {
                    title = item.title
                    category = item.category
                    username = item.username
                    password = item.encryptedValue
                    url = item.url
                    note = item.note
                }
            }
        }
    }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.secondary).frame(width: 90, alignment: .leading)
            TextField(placeholder, text: text)
                .foregroundColor(.white).autocorrectionDisabled().textInputAutocapitalization(.never)
        }
    }

    private func save() {
        let secureItem = item ?? SecureItem(homeId: home.id, title: title, category: category)
        secureItem.title = title
        secureItem.category = category
        secureItem.username = username
        secureItem.encryptedValue = password
        secureItem.url = url
        secureItem.note = note
        secureItem.updatedAt = Date()
        if item == nil { context.insert(secureItem) }
        dismiss()
    }

    private func generatePassword() -> String {
        let chars = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%&*"
        return String((0..<20).map { _ in chars.randomElement()! })
    }
}
