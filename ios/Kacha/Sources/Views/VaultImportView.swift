import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 1Password / CSV からの鍵インポート
struct VaultImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false
    @State private var result: ImportResult?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("鍵をインポート")
                    .font(.title2).bold()

                Text("1Password, Chrome, その他のパスワード\nマネージャーからCSVファイルを読み込めます")
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 12) {
                    instructionRow("1", "元のアプリからCSVでエクスポート")
                    instructionRow("2", "このボタンでCSVファイルを選択")
                    instructionRow("3", "自動でAES-256暗号化して保存")
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button { isImporting = true } label: {
                    Label("CSVファイルを選択", systemImage: "doc.fill")
                        .font(.headline).foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if let result {
                    HStack(spacing: 8) {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(result.success ? .green : .red)
                        Text(result.message).font(.caption)
                    }
                    .padding(12)
                    .background(result.success ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Spacer()

                VStack(spacing: 6) {
                    Text("対応フォーマット").font(.caption).bold().foregroundColor(.secondary)
                    Text("1Password (CSV) / Chrome (CSV) / Firefox (CSV)\nBitwarden (CSV) / 汎用 CSV")
                        .font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding()
            .navigationTitle("インポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.commaSeparatedText, .plainText]) { res in
                switch res {
                case .success(let url):
                    let imported = importCSV(url: url)
                    result = imported
                case .failure(let error):
                    result = ImportResult(success: false, message: error.localizedDescription)
                }
            }
        }
    }

    private func instructionRow(_ num: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(num)
                .font(.caption).bold().foregroundColor(.black)
                .frame(width: 22, height: 22)
                .background(Color.orange)
                .clipShape(Circle())
            Text(text).font(.subheadline)
        }
    }

    /// Parse CSV and import items
    private func importCSV(url: URL) -> ImportResult {
        guard url.startAccessingSecurityScopedResource() else {
            return ImportResult(success: false, message: "ファイルにアクセスできません")
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? String(contentsOf: url, encoding: .utf8) else {
            return ImportResult(success: false, message: "ファイルを読み込めません")
        }

        let lines = data.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else {
            return ImportResult(success: false, message: "データがありません")
        }

        let header = parseCSVLine(lines[0]).map { $0.lowercased() }
        var count = 0

        // Detect format
        let titleIdx = header.firstIndex(where: { ["title", "name", "login_uri", "url"].contains($0) })
        let userIdx = header.firstIndex(where: { ["username", "login_username", "user"].contains($0) })
        let passIdx = header.firstIndex(where: { ["password", "login_password", "pass"].contains($0) })
        let urlIdx = header.firstIndex(where: { ["url", "login_uri", "website"].contains($0) })
        let noteIdx = header.firstIndex(where: { ["notes", "note", "extra"].contains($0) })
        let typeIdx = header.firstIndex(where: { ["type", "category"].contains($0) })

        for i in 1..<lines.count {
            let fields = parseCSVLine(lines[i])
            guard fields.count > 1 else { continue }

            let title = titleIdx.flatMap { $0 < fields.count ? fields[$0] : nil } ?? "Imported \(i)"
            let username = userIdx.flatMap { $0 < fields.count ? fields[$0] : nil } ?? ""
            let password = passIdx.flatMap { $0 < fields.count ? fields[$0] : nil } ?? ""
            let itemUrl = urlIdx.flatMap { $0 < fields.count ? fields[$0] : nil } ?? ""
            let itemNote = noteIdx.flatMap { $0 < fields.count ? fields[$0] : nil } ?? ""
            let typeStr = typeIdx.flatMap { $0 < fields.count ? fields[$0] : nil } ?? ""

            guard !title.isEmpty, !password.isEmpty else { continue }

            let category = detectCategory(type: typeStr, url: itemUrl, title: title)

            let item = SecureItem(homeId: "global", title: title, category: category)
            item.username = username
            item.encryptedValue = VaultEncryption.encrypt(password)
            item.url = itemUrl
            item.note = itemNote
            context.insert(item)
            count += 1
        }

        try? context.save()
        return ImportResult(success: true, message: "\(count) 件の鍵をインポートしました")
    }

    private func detectCategory(type: String, url: String, title: String) -> String {
        let lower = (type + url + title).lowercased()
        if lower.contains("api") || lower.contains("token") || lower.contains("key") { return "apikey" }
        if lower.contains("wifi") || lower.contains("ssid") { return "wifi" }
        if lower.contains("card") || lower.contains("credit") { return "card" }
        if lower.contains("bank") { return "bank" }
        if lower.contains("ssh") { return "ssh" }
        if lower.contains("crypto") || lower.contains("wallet") || lower.contains("seed") { return "crypto" }
        return "password"
    }

    /// Simple CSV line parser (handles quoted fields)
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }
}

struct ImportResult {
    let success: Bool
    let message: String
}
