import SwiftUI
import SwiftData

struct HouseManualView: View {
    let home: Home
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allManuals: [HouseManual]
    @State private var editingSection: ManualSection?
    @State private var editText = ""
    @State private var showPreview = false

    private var manual: HouseManual {
        if let m = allManuals.first(where: { $0.homeId == home.id }) { return m }
        let m = HouseManual(homeId: home.id)
        context.insert(m)
        return m
    }

    private var sections: [ManualSection] {
        get { manual.decodedSections }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        // Header
                        VStack(spacing: 4) {
                            Text(home.name).font(.title2).bold().foregroundColor(.white)
                            Text("ハウスマニュアル").font(.caption).foregroundColor(.kacha)
                        }
                        .padding(.top, 8)

                        // Active sections
                        ForEach(sections.filter(\.enabled)) { section in
                            sectionCard(section)
                        }

                        // Add sections
                        KachaCard {
                            VStack(alignment: .leading, spacing: 12) {
                                SettingsHeader(icon: "plus.circle.fill", title: "セクションを追加", color: .kacha)
                                let existing = Set(sections.map(\.type))
                                let available = ManualSection.templates.filter { !existing.contains($0.key) || $0.key == "custom" }
                                ForEach(available, id: \.key) { template in
                                    Button {
                                        addSection(template)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: template.icon).foregroundColor(.kacha).frame(width: 20)
                                            Text(template.title).font(.subheadline).foregroundColor(.white)
                                            Spacer()
                                            Image(systemName: "plus").font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                    if template.key != available.last?.key {
                                        Divider().background(Color.kachaCardBorder)
                                    }
                                }
                            }
                            .padding(16)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("マニュアル編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showPreview = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "eye")
                            Text("プレビュー")
                        }
                        .font(.caption).foregroundColor(.kacha)
                    }
                }
            }
            .sheet(item: $editingSection) { section in
                editSheet(section)
            }
            .sheet(isPresented: $showPreview) {
                ManualPreviewView(home: home, sections: sections.filter(\.enabled))
            }
        }
    }

    private func sectionCard(_ section: ManualSection) -> some View {
        let template = ManualSection.templates.first { $0.key == section.type }
        return KachaCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: template?.icon ?? "doc").foregroundColor(.kacha)
                    Text(section.title).font(.subheadline).bold().foregroundColor(.white)
                    Spacer()
                    Button {
                        editingSection = section
                        editText = section.content
                    } label: {
                        Image(systemName: "pencil").font(.caption).foregroundColor(.secondary)
                    }
                    Button { removeSection(section) } label: {
                        Image(systemName: "xmark.circle").font(.caption).foregroundColor(.kachaDanger.opacity(0.6))
                    }
                }
                if !section.content.isEmpty {
                    Text(section.content)
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(14)
        }
    }

    private func editSheet(_ section: ManualSection) -> some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                VStack(spacing: 16) {
                    TextEditor(text: $editText)
                        .scrollContentBackground(.hidden)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.kachaCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kachaCardBorder))
                        .padding(.horizontal)
                    Spacer()
                }
                .padding(.top, 16)
            }
            .navigationTitle(section.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { editingSection = nil }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveSection(section) }.foregroundColor(.kacha)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Actions

    private func addSection(_ template: (key: String, icon: String, title: String, defaultContent: String)) {
        var s = sections
        // Auto-fill WiFi from home
        var content = template.defaultContent
        if template.key == "wifi" && !home.wifiPassword.isEmpty {
            content = "ネットワーク名: \(home.name)\nパスワード: \(home.wifiPassword)"
        }
        if template.key == "checkin" && !home.doorCode.isEmpty {
            content = "チェックイン: 15:00以降\nドアコード: \(home.doorCode)"
        }
        s.append(ManualSection(type: template.key, title: template.title, content: content))
        manual.decodedSections = s
    }

    private func removeSection(_ section: ManualSection) {
        var s = sections
        s.removeAll { $0.id == section.id }
        manual.decodedSections = s
    }

    private func saveSection(_ section: ManualSection) {
        var s = sections
        if let idx = s.firstIndex(where: { $0.id == section.id }) {
            s[idx].content = editText
        }
        manual.decodedSections = s
        editingSection = nil
    }
}

// MARK: - Manual Preview (shareable)

struct ManualPreviewView: View {
    let home: Home
    let sections: [ManualSection]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0F0F1A").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "house.fill").font(.system(size: 40)).foregroundColor(.kacha)
                            Text(home.name).font(.title).bold().foregroundColor(.white)
                            if !home.address.isEmpty {
                                Text(home.address).font(.caption).foregroundColor(.secondary)
                            }
                            Text("ハウスマニュアル").font(.caption).foregroundColor(.kacha)
                        }
                        .padding(.top, 24)

                        ForEach(sections) { section in
                            let template = ManualSection.templates.first { $0.key == section.type }
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Image(systemName: template?.icon ?? "doc")
                                        .foregroundColor(.kacha).font(.title3)
                                    Text(section.title).font(.headline).foregroundColor(.white)
                                }
                                Text(section.content)
                                    .font(.subheadline).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("プレビュー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
        }
    }
}
