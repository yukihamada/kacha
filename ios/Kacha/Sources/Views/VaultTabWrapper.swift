import SwiftUI
import SwiftData
import LocalAuthentication

struct VaultTabWrapper: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \SecureItem.sortOrder) private var items: [SecureItem]
    @AppStorage("vaultAutoLockSeconds") private var autoLockSeconds = 60
    @State private var showAdd = false
    @State private var showTransfer = false
    @State private var revealedId: String?
    @State private var copiedId: String?
    @State private var lastActive = Date()
    @State private var locked = false

    var body: some View {
        NavigationStack {
            Group {
                if locked {
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 44)).foregroundStyle(.orange)
                        Text("鍵管理").font(.title3).bold()
                        Button("Face IDで解除") { unlock() }
                            .buttonStyle(.borderedProminent).tint(.orange)
                        Spacer()
                    }
                } else if items.isEmpty {
                    ContentUnavailableView("鍵がありません", systemImage: "key",
                        description: Text("右上の＋ボタンで追加してください"))
                } else {
                    List {
                        ForEach(items) { item in
                            row(item)
                        }
                        .onDelete { idx in idx.forEach { context.delete(items[$0]) } }
                    }
                }
            }
            .navigationTitle("鍵管理")
            .toolbar {
                if !locked {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showAdd = true } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button { locked = true; revealedId = nil } label: {
                                Label("ロック", systemImage: "lock.fill")
                            }
                            if !items.isEmpty {
                                Button { showTransfer = true } label: {
                                    Label("ChatWebに送る", systemImage: "arrow.right.circle")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.caption)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddItemView()
            }
            .sheet(isPresented: $showTransfer) {
                TransferView(items: Array(items))
            }
        }
        .onChange(of: scenePhase) { _, p in
            if p == .background { lastActive = Date(); revealedId = nil }
            if p == .active && !locked {
                if Date().timeIntervalSince(lastActive) > Double(autoLockSeconds) {
                    locked = true; revealedId = nil
                }
            }
        }
        .onAppear { unlock() }
    }

    // MARK: - Row

    private func row(_ item: SecureItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ico(item.category))
                .foregroundColor(clr(item.category))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline).bold()
                if !item.username.isEmpty {
                    Text(item.username).font(.caption).foregroundColor(.secondary)
                }
                if revealedId == item.id {
                    Text(VaultEncryption.decrypt(item.encryptedValue))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.orange)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            // Reveal
            Button {
                revealedId = revealedId == item.id ? nil : item.id
            } label: {
                Image(systemName: revealedId == item.id ? "eye.slash" : "eye")
                    .font(.caption).foregroundColor(.secondary)
            }.buttonStyle(.plain)
            // Copy
            Button {
                UIPasteboard.general.setItems(
                    [[UIPasteboard.typeAutomatic: VaultEncryption.decrypt(item.encryptedValue)]],
                    options: [.expirationDate: Date().addingTimeInterval(30)]
                )
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                copiedId = item.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if copiedId == item.id { copiedId = nil }
                }
            } label: {
                Image(systemName: copiedId == item.id ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(copiedId == item.id ? .green : .secondary)
            }.buttonStyle(.plain)
        }
    }

    private func ico(_ c: String) -> String {
        switch c {
        case "password": return "key.fill"
        case "apikey": return "chevron.left.forwardslash.chevron.right"
        case "wifi": return "wifi"
        case "pin": return "lock.fill"
        case "card": return "creditcard.fill"
        case "bank": return "building.columns.fill"
        case "ssh": return "terminal.fill"
        case "token": return "shield.checkered"
        case "license": return "checkmark.seal.fill"
        case "email": return "envelope.fill"
        case "server": return "server.rack"
        case "social": return "person.crop.circle.fill"
        case "crypto": return "bitcoinsign.circle.fill"
        case "id": return "person.text.rectangle.fill"
        case "note": return "note.text"
        default: return "key.fill"
        }
    }

    private func clr(_ c: String) -> Color {
        switch c {
        case "apikey": return .blue
        case "password": return .orange
        case "wifi": return .green
        case "pin": return .red
        case "card": return .purple
        case "bank": return .indigo
        case "note": return .mint
        default: return .orange
        }
    }

    private func unlock() {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            locked = false; return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "鍵管理") { ok, _ in
            DispatchQueue.main.async { if ok { locked = false; lastActive = Date() } }
        }
    }
}

// MARK: - Add

struct AddItemView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var value = ""
    @State private var username = ""
    @State private var category = "password"
    @State private var showValue = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("カテゴリ", selection: $category) {
                    ForEach(SecureItem.categories, id: \.key) { cat in
                        Label(cat.label, systemImage: cat.icon).tag(cat.key)
                    }
                }
                TextField("名前", text: $title).autocorrectionDisabled()
                if ["password","wifi","email","social","server"].contains(category) {
                    TextField("ユーザー名", text: $username)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                HStack {
                    if showValue { TextField("値", text: $value) }
                    else { SecureField("値", text: $value) }
                    Button { showValue.toggle() } label: {
                        Image(systemName: showValue ? "eye.slash" : "eye").foregroundColor(.secondary)
                    }
                }
                .autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            .navigationTitle("追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let item = SecureItem(homeId: "global", title: title, category: category)
                        item.username = username
                        item.encryptedValue = VaultEncryption.encrypt(value)
                        context.insert(item)
                        dismiss()
                    }.bold().disabled(title.isEmpty || value.isEmpty)
                }
            }
        }
    }
}
