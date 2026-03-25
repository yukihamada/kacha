import SwiftUI
import SwiftData
import LocalAuthentication
import UniformTypeIdentifiers

// MARK: - Vault Page (rightmost page in HomePager)
// 全物件横断のパスワードマネージャー。Face ID/Touch ID認証後にアクセス可能。
// UIPasteboard.general はユニバーサルクリップボード対応（同一iCloudアカウントのMacに自動コピー）。

struct VaultPageView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SecureItem.updatedAt, order: .reverse) private var allItems: [SecureItem]
    @Query(sort: \Home.sortOrder) private var homes: [Home]

    @State private var isUnlocked = false
    @State private var searchText = ""
    @State private var selectedCategory = "all"
    @State private var showAdd = false
    @State private var copiedItemId: String?
    @State private var revealedIds = Set<String>()
    @State private var selectedHomeId = "all"

    private var filteredItems: [SecureItem] {
        var items = allItems
        if selectedHomeId != "all" {
            items = items.filter { $0.homeId == selectedHomeId }
        }
        if selectedCategory != "all" {
            items = items.filter { $0.category == selectedCategory }
        }
        if !searchText.isEmpty {
            items = items.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.username.localizedCaseInsensitiveContains(searchText) ||
                $0.url.localizedCaseInsensitiveContains(searchText)
            }
        }
        return items
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
            .navigationBarHidden(true)
            .sheet(isPresented: $showAdd) {
                if let home = homes.first(where: { $0.id == selectedHomeId }) ?? homes.first {
                    VaultItemEditor(home: home, item: nil)
                }
            }
        }
        .onAppear { authenticate() }
    }

    // MARK: - Lock Screen

    private var lockScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle().fill(Color.kacha.opacity(0.12)).frame(width: 100, height: 100)
                Image(systemName: "key.viewfinder")
                    .font(.system(size: 44)).foregroundColor(.kacha)
            }
            Text("パスワード管理")
                .font(.title2).bold().foregroundColor(.white)
            Text("Face ID / Touch IDで解除")
                .font(.caption).foregroundColor(.secondary)
            Button { authenticate() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "faceid")
                    Text("解除する")
                }
                .foregroundColor(.black).font(.subheadline).bold()
                .padding(.horizontal, 32).padding(.vertical, 14)
                .background(Color.kacha)
                .clipShape(Capsule())
            }
            Spacer()
            Text("← スワイプで物件へ")
                .font(.caption2).foregroundColor(.secondary.opacity(0.4))
                .padding(.bottom, 20)
        }
    }

    // MARK: - Vault Content

    private var vaultContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("パスワード管理")
                        .font(.title2).bold().foregroundColor(.white)
                    Text("\(filteredItems.count)件のアイテム")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2).foregroundColor(.kacha)
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            // Search
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("検索", text: $searchText)
                    .foregroundColor(.white).autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color.kachaCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)

            // Home filter
            if homes.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip("all", "すべて", isSelected: selectedHomeId == "all") {
                            selectedHomeId = "all"
                        }
                        ForEach(homes) { home in
                            filterChip(home.id, home.name, isSelected: selectedHomeId == home.id) {
                                selectedHomeId = home.id
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }

            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("all", "すべて", isSelected: selectedCategory == "all") {
                        selectedCategory = "all"
                    }
                    ForEach(SecureItem.categories, id: \.key) { cat in
                        filterChip(cat.key, cat.label, icon: cat.icon, isSelected: selectedCategory == cat.key) {
                            selectedCategory = cat.key
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
            }

            // Items
            if filteredItems.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 40)).foregroundColor(.secondary)
                    Text("アイテムがありません")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredItems) { item in
                            vaultItemRow(item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 60)
                }
            }
        }
    }

    // MARK: - Item Row

    private func vaultItemRow(_ item: SecureItem) -> some View {
        let catInfo = SecureItem.categories.first { $0.key == item.category }
        let isRevealed = revealedIds.contains(item.id)
        let isCopied = copiedItemId == item.id
        let homeName = homes.first { $0.id == item.homeId }?.name ?? ""

        return KachaCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.kacha.opacity(0.12)).frame(width: 40, height: 40)
                        Image(systemName: catInfo?.icon ?? "key.fill")
                            .font(.system(size: 16)).foregroundColor(.kacha)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline).bold().foregroundColor(.white)
                        HStack(spacing: 6) {
                            if !item.username.isEmpty {
                                Text(item.username).font(.caption).foregroundColor(.secondary)
                            }
                            if !homeName.isEmpty {
                                Text("·").font(.caption).foregroundColor(.secondary.opacity(0.5))
                                Text(homeName).font(.caption2).foregroundColor(.secondary.opacity(0.6))
                            }
                        }
                    }
                    Spacer()

                    // Copy password (Universal Clipboard → Mac)
                    Button {
                        copyToUniversalClipboard(item.encryptedValue, itemId: item.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12))
                            if isCopied {
                                Text("コピー済み").font(.system(size: 10))
                            }
                        }
                        .foregroundColor(isCopied ? .kachaSuccess : .kachaAccent)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background((isCopied ? Color.kachaSuccess : Color.kachaAccent).opacity(0.12))
                        .clipShape(Capsule())
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

                // Revealed password
                if isRevealed {
                    HStack {
                        Text(item.encryptedValue)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.kacha)
                            .textSelection(.enabled)
                        Spacer()
                        // Copy username
                        if !item.username.isEmpty {
                            Button {
                                copyToUniversalClipboard(item.username, itemId: "\(item.id)-user")
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: "person").font(.system(size: 10))
                                    Text("ID").font(.system(size: 10))
                                }
                                .foregroundColor(.kachaAccent)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.kachaAccent.opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.kacha.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // URL
                if !item.url.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "link").font(.system(size: 10))
                        Text(item.url).font(.caption2).lineLimit(1)
                        Spacer()
                        Button {
                            copyToUniversalClipboard(item.url, itemId: "\(item.id)-url")
                        } label: {
                            Image(systemName: "doc.on.doc").font(.system(size: 9))
                        }
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(14)
        }
        .contextMenu {
            Button {
                copyToUniversalClipboard(item.encryptedValue, itemId: item.id)
            } label: {
                Label("パスワードをコピー (Mac対応)", systemImage: "doc.on.doc")
            }
            if !item.username.isEmpty {
                Button {
                    copyToUniversalClipboard(item.username, itemId: "\(item.id)-user")
                } label: {
                    Label("ユーザー名をコピー", systemImage: "person")
                }
            }
            if !item.url.isEmpty {
                Button {
                    copyToUniversalClipboard(item.url, itemId: "\(item.id)-url")
                } label: {
                    Label("URLをコピー", systemImage: "link")
                }
            }
            Divider()
            Button(role: .destructive) { context.delete(item) } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    // MARK: - Universal Clipboard Copy

    /// UIPasteboard.general は同一iCloudアカウントのMac/iPadに自動同期（Handoff経由）。
    /// expiration: 120秒後に自動削除（セキュリティ対策）。
    private func copyToUniversalClipboard(_ value: String, itemId: String) {
        // Set with expiration for security
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: value]],
            options: [.expirationDate: Date().addingTimeInterval(120)]
        )
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        withAnimation { copiedItemId = itemId }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                if copiedItemId == itemId { copiedItemId = nil }
            }
        }
    }

    // MARK: - Filter Chip

    private func filterChip(_ key: String, _ label: String, icon: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 10))
                }
                Text(label).font(.caption2).bold()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isSelected ? Color.kacha : Color.kacha.opacity(0.08))
            .foregroundColor(isSelected ? .black : .kacha)
            .clipShape(Capsule())
        }
    }

    // MARK: - Auth

    private func authenticate() {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isUnlocked = false
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "パスワード管理にアクセス") { success, _ in
            DispatchQueue.main.async { isUnlocked = success }
        }
    }
}
