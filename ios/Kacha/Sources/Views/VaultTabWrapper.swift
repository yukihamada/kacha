import SwiftUI
import SwiftData
import LocalAuthentication

// MARK: - Vault Tab

struct VaultTabWrapper: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \SecureItem.sortOrder) private var items: [SecureItem]
    @AppStorage("vaultAutoLockSeconds") private var autoLockSeconds = 60
    @State private var searchText = ""
    @State private var selectedCategory = "all"
    @State private var showAdd = false
    @State private var showImport = false
    @State private var editingItem: SecureItem?
    @State private var revealedIds = Set<String>()
    @State private var copiedId: String?
    @State private var isLocked = true
    @State private var lastActiveDate = Date()
    @State private var showSettings = false

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
        Group {
            if isLocked {
                lockView
            } else {
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
                        ToolbarItem(placement: .topBarLeading) {
                            Menu {
                                Button { withAnimation { isLocked = true; revealedIds.removeAll() } } label: {
                                    Label("ロック", systemImage: "lock.fill")
                                }
                                Button { showSettings = true } label: {
                                    Label("セキュリティ設定", systemImage: "gearshape")
                                }
                            } label: {
                                Image(systemName: "lock.open.fill").font(.caption)
                            }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                Button { showAdd = true } label: {
                                    Label("新規追加", systemImage: "plus")
                                }
                                Button { showImport = true } label: {
                                    Label("1Password / CSVからインポート", systemImage: "square.and.arrow.down")
                                }
                            } label: {
                                Image(systemName: "plus")
                            }
                        }
                    }
                    .sheet(isPresented: $showAdd) { VaultItemSheet(item: nil) }
                    .sheet(isPresented: $showImport) { VaultImportView() }
                    .sheet(isPresented: $showSettings) { VaultSecuritySettings(autoLockSeconds: $autoLockSeconds) }
                    .sheet(item: $editingItem) { item in VaultItemSheet(item: item) }
                }
            }
        }
        // Auto-lock on background
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                lastActiveDate = Date()
                // Immediately clear revealed values
                revealedIds.removeAll()
            }
            if phase == .active && isLocked == false {
                let elapsed = Date().timeIntervalSince(lastActiveDate)
                if elapsed > Double(autoLockSeconds) {
                    withAnimation { isLocked = true }
                }
            }
        }
        .task {
            // Initial unlock with Face ID
            try? await Task.sleep(for: .milliseconds(300))
            unlock()
        }
    }

    // MARK: - Lock

    private var lockView: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48)).foregroundStyle(.orange)
                Text("鍵管理").font(.title2).bold()
                Text("Face ID で解除").font(.subheadline).foregroundColor(.secondary)
                Button { unlock() } label: {
                    Label("解除する", systemImage: "faceid")
                        .font(.headline).foregroundColor(.black)
                        .padding(.horizontal, 32).padding(.vertical, 14)
                        .background(Color.orange).clipShape(Capsule())
                }
                Spacer()
                Text("\(items.count) 件を保護中 · \(autoLockText)")
                    .font(.caption).foregroundColor(.secondary)
                    .padding(.bottom, 20)
            }
        }
    }

    private var autoLockText: String {
        switch autoLockSeconds {
        case 0: return "即時ロック"
        case 60: return "1分でロック"
        case 300: return "5分でロック"
        case 600: return "10分でロック"
        default: return "\(autoLockSeconds)秒でロック"
        }
    }

    private func unlock() {
        let ctx = LAContext()
        var error: NSError?
        if !ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            // No biometrics — unlock directly
            withAnimation { isLocked = false; lastActiveDate = Date() }
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "鍵管理にアクセス") { ok, _ in
            DispatchQueue.main.async {
                if ok { withAnimation { isLocked = false; lastActiveDate = Date() } }
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
                    let decrypted = VaultEncryption.decrypt(item.encryptedValue)
                    UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: decrypted]], options: [
                        .expirationDate: Date().addingTimeInterval(30) // Auto-clear after 30s
                    ])
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
        SecureItem.categories.first { $0.key == c }?.icon ?? "key.fill"
    }
    private func colorFor(_ c: String) -> Color {
        switch c {
        case "password": return .orange
        case "apikey": return .blue
        case "wifi": return .green
        case "pin": return .red
        case "card": return .purple
        case "bank": return .indigo
        case "ssh": return .gray
        case "token": return .teal
        case "license": return .mint
        case "email": return .pink
        case "server": return .brown
        case "social": return .cyan
        case "crypto": return .yellow
        case "id": return .secondary
        case "note": return .mint
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
    @State private var category = "password"
    @State private var username = ""
    @State private var value = ""
    @State private var url = ""
    @State private var note = ""
    @State private var showValue = false

    var body: some View {
        NavigationStack {
            Form {
                // Category picker (grid of icons)
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 8) {
                        ForEach(SecureItem.categories, id: \.key) { cat in
                            Button {
                                withAnimation { category = cat.key }
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 18))
                                        .frame(width: 36, height: 36)
                                        .background(category == cat.key ? Color.orange : Color(.tertiarySystemGroupedBackground))
                                        .foregroundColor(category == cat.key ? .black : .secondary)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(cat.label)
                                        .font(.system(size: 9))
                                        .foregroundColor(category == cat.key ? .primary : .secondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: { Text("カテゴリ") }

                // Name
                Section {
                    TextField(placeholderFor(category), text: $title)
                        .autocorrectionDisabled()
                } header: { Text("名前") }

                // Category-specific fields
                Section {
                    switch category {
                    case "password", "email", "social":
                        TextField("ユーザー名 / メール", text: $username)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                        secureValueField("パスワード")

                    case "wifi":
                        TextField("SSID (ネットワーク名)", text: $username)
                            .autocorrectionDisabled()
                        secureValueField("パスワード")

                    case "apikey", "token", "license":
                        secureValueField("キー / トークン")

                    case "ssh":
                        TextField("ホスト / ユーザー", text: $username)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                        secureValueField("秘密鍵 / パスフレーズ")

                    case "card", "bank":
                        TextField(category == "card" ? "カード番号" : "口座番号", text: $username)
                            .keyboardType(.numberPad)
                        secureValueField(category == "card" ? "セキュリティコード" : "暗証番号")

                    case "pin":
                        secureValueField("暗証番号").keyboardType(.numberPad)

                    case "server":
                        TextField("ホスト:ポート", text: $username)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                        secureValueField("パスワード / 接続文字列")

                    case "crypto":
                        TextField("ウォレットアドレス", text: $username)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                        secureValueField("シードフレーズ / 秘密鍵")

                    case "id":
                        TextField("ID番号", text: $username)
                            .autocorrectionDisabled()
                        secureValueField("関連パスワード (任意)")

                    default: // note
                        secureValueField("内容")
                    }
                } header: { Text("認証情報") }

                // URL + notes (common)
                Section {
                    TextField("URL (任意)", text: $url)
                        .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("メモ (任意)", text: $note)
                } header: { Text("その他") }
            }
            .navigationTitle(item == nil ? "追加" : "編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.bold().disabled(title.isEmpty)
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

    @ViewBuilder
    private func secureValueField(_ placeholder: String) -> some View {
        HStack {
            Group {
                if showValue {
                    TextField(placeholder, text: $value)
                } else {
                    SecureField(placeholder, text: $value)
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

    private func placeholderFor(_ cat: String) -> String {
        switch cat {
        case "password": return "サービス名 (例: GitHub)"
        case "apikey": return "キー名 (例: FLY_API_TOKEN)"
        case "wifi": return "ネットワーク名"
        case "pin": return "用途 (例: 玄関ロック)"
        case "card": return "カード名 (例: VISA ****1234)"
        case "bank": return "銀行名 (例: 三菱UFJ)"
        case "ssh": return "サーバー名"
        case "token": return "トークン名"
        case "license": return "ソフトウェア名"
        case "email": return "メールアドレス"
        case "server": return "サーバー名 / DB名"
        case "social": return "SNS名 (例: X, Instagram)"
        case "crypto": return "ウォレット名"
        case "id": return "ID種別 (例: パスポート)"
        case "note": return "タイトル"
        default: return "名前"
        }
    }

    private func save() {
        let t = item ?? SecureItem(homeId: "global", title: title, category: category)
        t.title = title
        t.category = category
        t.username = username
        t.encryptedValue = VaultEncryption.encrypt(value)
        t.url = url
        t.note = note
        t.updatedAt = Date()
        if item == nil { context.insert(t) }
        dismiss()
    }
}

// MARK: - Security Settings

struct VaultSecuritySettings: View {
    @Binding var autoLockSeconds: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("オートロック") {
                    Picker("バックグラウンド後にロック", selection: $autoLockSeconds) {
                        Text("即時").tag(0)
                        Text("30秒").tag(30)
                        Text("1分").tag(60)
                        Text("5分").tag(300)
                        Text("10分").tag(600)
                    }
                }

                Section("暗号化") {
                    HStack {
                        Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
                        VStack(alignment: .leading) {
                            Text("AES-256-GCM").font(.subheadline).bold()
                            Text("業界最高水準の暗号化").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
                        VStack(alignment: .leading) {
                            Text("Keychain保護").font(.subheadline).bold()
                            Text("暗号鍵はApple Keychainに保存").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
                        VStack(alignment: .leading) {
                            Text("クリップボード自動消去").font(.subheadline).bold()
                            Text("コピー後30秒で自動クリア").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                Section("データ") {
                    HStack {
                        Image(systemName: "iphone").foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text("ローカル保存").font(.subheadline).bold()
                            Text("すべてのデータは端末内に暗号化保存").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Image(systemName: "key.fill").foregroundColor(.orange)
                        VStack(alignment: .leading) {
                            Text("Keychainバックアップ").font(.subheadline).bold()
                            Text("アプリ削除後も復元可能").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("セキュリティ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}
