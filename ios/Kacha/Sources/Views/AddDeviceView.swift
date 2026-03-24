import SwiftUI
import SwiftData

// MARK: - AddDeviceView
// プラットフォーム選択グリッド → 認証情報フォーム → 保存

struct AddDeviceView: View {
    let homeId: String
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlatform: DevicePlatform?
    @State private var nameText = ""
    @State private var fieldValues: [String: String] = [:]
    @State private var isSaving = false
    @State private var showOnlyAvailable = false

    private var displayedPlatforms: [DevicePlatform] {
        showOnlyAvailable ? DevicePlatform.all.filter { $0.isAvailable } : DevicePlatform.all
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                if let platform = selectedPlatform {
                    credentialsForm(for: platform)
                } else {
                    platformGrid
                }
            }
            .navigationTitle(selectedPlatform == nil ? "デバイスを追加" : selectedPlatform!.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if selectedPlatform != nil {
                        Button { selectedPlatform = nil } label: {
                            Image(systemName: "chevron.left").foregroundColor(.kacha)
                        }
                    } else {
                        Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                    }
                }
                if selectedPlatform != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { save() }
                            .foregroundColor(.kacha)
                            .disabled(isSaving || nameText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    // MARK: - Platform Grid

    private var platformGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Filter toggle
                Toggle(isOn: $showOnlyAvailable) {
                    Text("対応済みのみ表示").font(.subheadline).foregroundColor(.secondary)
                }
                .tint(.kacha)
                .padding(.horizontal, 4)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(displayedPlatforms, id: \.id) { platform in
                        PlatformCard(platform: platform) {
                            if platform.isAvailable {
                                selectedPlatform = platform
                                nameText = platform.name
                                fieldValues = [:]
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Credentials Form

    private func credentialsForm(for platform: DevicePlatform) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Icon + description
                KachaCard {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: platform.colorHex).opacity(0.15))
                                .frame(width: 56, height: 56)
                            Image(systemName: platform.icon)
                                .font(.title2)
                                .foregroundColor(Color(hex: platform.colorHex))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(platform.name).font(.headline).foregroundColor(.white)
                            Text(platform.description).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(16)
                }

                // API guide link
                if !platform.apiGuideURL.isEmpty {
                    KachaCard {
                        ApiGuideRow(
                            label: "APIキー・トークンの取得",
                            urlString: platform.apiGuideURL,
                            note: "\(platform.name)の開発者ポータルでAPIキーを発行してください"
                        )
                        .padding(16)
                    }
                }

                // Fields
                KachaCard {
                    VStack(spacing: 14) {
                        SettingsTextField(label: "表示名", placeholder: "\(platform.name)（例: リビング）", text: $nameText)
                        ForEach(platform.fields, id: \.key) { field in
                            Divider().background(Color.kachaCardBorder)
                            SettingsTextField(
                                label: field.label + (field.isOptional ? "（任意）" : ""),
                                placeholder: field.placeholder,
                                text: Binding(
                                    get: { fieldValues[field.key] ?? "" },
                                    set: { fieldValues[field.key] = $0 }
                                ),
                                isSecure: field.isSecure
                            )
                        }
                    }
                    .padding(16)
                }

                Spacer(minLength: 40)
            }
            .padding(16)
        }
    }

    // MARK: - Save

    private func save() {
        guard let platform = selectedPlatform else { return }
        isSaving = true
        let integration = DeviceIntegration(
            homeId: homeId,
            platform: platform.id,
            name: nameText.trimmingCharacters(in: .whitespaces),
            credentials: fieldValues.filter { !$0.value.isEmpty }
        )
        modelContext.insert(integration)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Platform Card

private struct PlatformCard: View {
    let platform: DevicePlatform
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: platform.colorHex).opacity(platform.isAvailable ? 0.15 : 0.06))
                        .frame(width: 48, height: 48)
                    Image(systemName: platform.icon)
                        .font(.title3)
                        .foregroundColor(
                            platform.isAvailable
                                ? Color(hex: platform.colorHex)
                                : Color(hex: platform.colorHex).opacity(0.4)
                        )
                }
                Text(platform.name)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(platform.isAvailable ? .white : .secondary)
                    .lineLimit(2).multilineTextAlignment(.center)
                if !platform.isAvailable {
                    Text("近日対応").font(.system(size: 9)).foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.kachaCard)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        platform.isAvailable
                            ? Color(hex: platform.colorHex).opacity(0.3)
                            : Color.kachaCardBorder,
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(platform.isAvailable ? 1 : 0.7)
        }
        .disabled(!platform.isAvailable)
    }
}
