import SwiftUI
import SwiftData

// MARK: - AutomationView

struct AutomationView: View {
    let home: Home

    @StateObject private var engine = AutomationEngine.shared
    @State private var scenes: [AutomationScene] = AutomationScene.presets
    @State private var showHistory = false
    @State private var showCreateSheet = false
    @State private var completedSceneId: String? = nil
    @State private var errorMessage: String? = nil

    private var switchBotToken:  String { home.switchBotToken }
    private var switchBotSecret: String { home.switchBotSecret }
    private var hueBridgeIP:     String { home.hueBridgeIP }
    private var hueUsername:     String { home.hueUsername }
    private var sesameUUIDs: [String] {
        home.sesameDeviceUUIDs
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        ZStack {
            Color.kachaBg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    headerArea
                    scenesGrid
                    if !engine.executionHistory.isEmpty {
                        historyPreview
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .navigationTitle("オートメーション")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.secondary)
                    }
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.kacha)
                    }
                }
            }
        }
        .sheet(isPresented: $showHistory) {
            AutomationHistoryView(records: engine.executionHistory)
        }
        .sheet(isPresented: $showCreateSheet) {
            AutomationCreateView(scenes: $scenes, home: home)
        }
        .overlay(alignment: .bottom) {
            if let msg = errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.kachaDanger.opacity(0.9))
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { errorMessage = nil }
                        }
                    }
            }
        }
    }

    // MARK: - Header

    private var headerArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("シーンをタップして即実行")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("チェックイン30分前に「ウェルカム」が自動起動します")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Scenes Grid

    private var scenesGrid: some View {
        Group {
            if scenes.isEmpty {
                scenesEmptyState
            } else {
                VStack(spacing: 16) {
                    ForEach(scenes) { scene in
                        AutomationSceneCard(
                            scene: scene,
                            isRunning: engine.isExecuting.contains(scene.id),
                            isCompleted: completedSceneId == scene.id
                        ) {
                            runScene(scene)
                        }
                        .accessibilityLabel("\(scene.name)シーン。\(scene.trigger.displayName)。実行するにはダブルタップ。")
                        .accessibilityAddTraits(.isButton)
                    }
                }
            }
        }
    }

    private var scenesEmptyState: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 40)
            Image(systemName: "wand.and.stars")
                .font(.system(size: 52))
                .foregroundColor(.kacha.opacity(0.35))
            Text("シーンがありません")
                .font(.title3).bold()
                .foregroundColor(.white)
            Text("右上の + ボタンからカスタムシーンを作成できます")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("シーンがありません。右上のプラスボタンから作成できます。")
    }

    // MARK: - History Preview

    private var historyPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近の実行")
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(.white)
                Spacer()
                Button("すべて見る") { showHistory = true }
                    .font(.caption)
                    .foregroundColor(.kacha)
            }
            ForEach(engine.executionHistory.prefix(3)) { record in
                AutomationHistoryRow(record: record)
            }
        }
    }

    // MARK: - Execution

    private func runScene(_ scene: AutomationScene) {
        Task {
            await engine.executeScene(
                scene,
                switchBotToken: switchBotToken,
                switchBotSecret: switchBotSecret,
                hueBridgeIP: hueBridgeIP,
                hueUsername: hueUsername,
                sesameUUIDs: sesameUUIDs,
                sesameApiKey: home.sesameApiKey
            )
            // Show checkmark on success
            let latest = engine.executionHistory.first
            if latest?.sceneName == scene.name {
                if latest?.success == true {
                    withAnimation(.spring(response: 0.4)) { completedSceneId = scene.id }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { completedSceneId = nil }
                    }
                } else if let err = latest?.errorMessage {
                    withAnimation { errorMessage = err }
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - AutomationSceneCard

struct AutomationSceneCard: View {
    let scene: AutomationScene
    let isRunning: Bool
    let isCompleted: Bool
    let onRun: () -> Void

    @State private var isPulsing = false

    private var gradientColors: [Color] {
        switch scene.color {
        case .amber:  return [Color(hex: "#F59E0B"), Color(hex: "#92400E")]
        case .teal:   return [Color(hex: "#14B8A6"), Color(hex: "#0F4C40")]
        case .indigo: return [Color(hex: "#6366F1"), Color(hex: "#1E1B4B")]
        case .rose:   return [Color(hex: "#F43F5E"), Color(hex: "#4C0519")]
        case .purple: return [Color(hex: "#A855F7"), Color(hex: "#3B0764")]
        }
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Content
            HStack(spacing: 16) {
                // Icon + pulse ring
                ZStack {
                    if isRunning {
                        Circle()
                            .stroke(gradientColors[0].opacity(0.4), lineWidth: 2)
                            .frame(width: 68, height: 68)
                            .scaleEffect(isPulsing ? 1.3 : 1.0)
                            .opacity(isPulsing ? 0 : 0.8)
                            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: false), value: isPulsing)
                            .onAppear { isPulsing = true }
                            .onDisappear { isPulsing = false }
                    }
                    Circle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Group {
                        if isCompleted {
                            Image(systemName: "checkmark")
                                .font(.title2)
                                .bold()
                                .foregroundColor(.white)
                                .transition(.scale.combined(with: .opacity))
                        } else if isRunning {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: scene.icon)
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                    .animation(.spring(response: 0.35), value: isCompleted)
                }
                .frame(width: 60)

                // Text block
                VStack(alignment: .leading, spacing: 4) {
                    Text(scene.name)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(scene.trigger.displayName)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Spacer().frame(height: 2)
                    // Action chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(scene.actions.indices, id: \.self) { i in
                                ActionChip(action: scene.actions[i])
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Run button
                Button(action: onRun) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(isRunning ? 0.08 : 0.18))
                            .frame(width: 44, height: 44)
                        Image(systemName: isCompleted ? "checkmark" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .disabled(isRunning)
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: gradientColors[0].opacity(0.35), radius: 12, x: 0, y: 6)
    }
}

// MARK: - ActionChip

struct ActionChip: View {
    let action: AutomationAction

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: action.icon)
                .font(.system(size: 9))
            Text(action.displayName)
                .font(.system(size: 10))
                .lineLimit(1)
        }
        .foregroundColor(.white.opacity(0.85))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.white.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - History Views

struct AutomationHistoryView: View {
    let records: [AutomationExecutionRecord]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                if records.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("実行履歴はまだありません")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("実行履歴はまだありません")
                } else {
                    List(records) { record in
                        AutomationHistoryRow(record: record)
                            .listRowBackground(Color.kachaBg)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("実行履歴")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct AutomationHistoryRow: View {
    let record: AutomationExecutionRecord

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(record.success ? .kachaSuccess : .kachaDanger)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.sceneName)
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(.white)
                Text(Self.formatter.localizedString(for: record.executedAt, relativeTo: Date()))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let err = record.errorMessage {
                    Text(err)
                        .font(.caption2)
                        .foregroundColor(.kachaDanger)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Create Sheet

struct AutomationCreateView: View {
    @Binding var scenes: [AutomationScene]
    let home: Home
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedIcon = "star.fill"
    @State private var selectedTrigger: AutomationTrigger = .manual
    @State private var selectedColor: AutomationScene.SceneColor = .teal
    @State private var selectedActions: [AutomationAction] = []
    @State private var showActionPicker = false

    private let iconOptions = [
        "star.fill", "house.fill", "bell.fill", "heart.fill",
        "bolt.fill", "leaf.fill", "flame.fill", "drop.fill"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                Form {
                    Section("基本情報") {
                        TextField("シーン名", text: $name)
                            .foregroundColor(.white)
                        Picker("トリガー", selection: $selectedTrigger) {
                            ForEach(AutomationTrigger.allCases, id: \.self) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .listRowBackground(Color.kachaCard)

                    Section("アイコン") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                            ForEach(iconOptions, id: \.self) { icon in
                                Button {
                                    selectedIcon = icon
                                } label: {
                                    Image(systemName: icon)
                                        .font(.title2)
                                        .frame(width: 48, height: 48)
                                        .background(selectedIcon == icon ? Color.kacha.opacity(0.3) : Color.white.opacity(0.05))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(selectedIcon == icon ? Color.kacha : Color.clear, lineWidth: 1.5)
                                        )
                                }
                                .foregroundColor(selectedIcon == icon ? .kacha : .secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.kachaCard)

                    Section("アクション (\(selectedActions.count)件)") {
                        ForEach(selectedActions.indices, id: \.self) { i in
                            HStack {
                                Image(systemName: selectedActions[i].icon)
                                    .foregroundColor(.kacha)
                                Text(selectedActions[i].displayName)
                                    .foregroundColor(.white)
                                    .font(.subheadline)
                            }
                        }
                        .onDelete { selectedActions.remove(atOffsets: $0) }

                        Button {
                            showActionPicker = true
                        } label: {
                            Label("アクションを追加", systemImage: "plus")
                                .foregroundColor(.kacha)
                        }
                    }
                    .listRowBackground(Color.kachaCard)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("カスタムシーン作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") { addScene() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedActions.isEmpty)
                        .bold()
                }
            }
            .sheet(isPresented: $showActionPicker) {
                ActionPickerView { action in
                    selectedActions.append(action)
                }
            }
        }
    }

    private func addScene() {
        let newScene = AutomationScene(
            id: UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespaces),
            icon: selectedIcon,
            color: selectedColor,
            trigger: selectedTrigger,
            actions: selectedActions,
            isEnabled: true
        )
        scenes.append(newScene)
        dismiss()
    }
}

// MARK: - Action Picker

struct ActionPickerView: View {
    let onSelect: (AutomationAction) -> Void
    @Environment(\.dismiss) private var dismiss

    private let options: [(String, AutomationAction)] = [
        ("照明オン (暖色 70%)", .lightsOn(brightness: 70, colorTemp: 2700)),
        ("照明オン (白色 100%)", .lightsOn(brightness: 100, colorTemp: 4000)),
        ("照明オフ",           .lightsOff),
        ("ドア施錠",           .lockDoor),
        ("ドア解錠",           .unlockDoor),
        ("エアコン 24℃ 冷房",  .setAC(temp: 24, mode: "cool")),
        ("エアコン 26℃ 暖房",  .setAC(temp: 26, mode: "heat")),
        ("全デバイスOFF",      .allOff)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                List(options, id: \.0) { label, action in
                    Button {
                        onSelect(action)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: action.icon)
                                .foregroundColor(.kacha)
                                .frame(width: 24)
                            Text(label)
                                .foregroundColor(.white)
                        }
                    }
                    .listRowBackground(Color.kachaCard)
                }
                .listStyle(.plain)
            }
            .navigationTitle("アクションを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Automation Preview Card (used in HomeView)

struct AutomationPreviewCard: View {
    let home: Home
    @StateObject private var engine = AutomationEngine.shared
    @State private var completedSceneId: String? = nil

    private var switchBotToken:  String { home.switchBotToken }
    private var switchBotSecret: String { home.switchBotSecret }
    private var hueBridgeIP:     String { home.hueBridgeIP }
    private var hueUsername:     String { home.hueUsername }
    private var sesameUUIDs: [String] {
        home.sesameDeviceUUIDs
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                AutomationView(home: home)
            } label: {
                HStack {
                    SectionHeader(title: "オートメーション", icon: "wand.and.stars")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AutomationScene.presets.prefix(4)) { scene in
                        CompactSceneButton(
                            scene: scene,
                            isRunning: engine.isExecuting.contains(scene.id),
                            isCompleted: completedSceneId == scene.id
                        ) {
                            runScene(scene)
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func runScene(_ scene: AutomationScene) {
        Task {
            await engine.executeScene(
                scene,
                switchBotToken: switchBotToken,
                switchBotSecret: switchBotSecret,
                hueBridgeIP: hueBridgeIP,
                hueUsername: hueUsername,
                sesameUUIDs: sesameUUIDs,
                sesameApiKey: home.sesameApiKey
            )
            if engine.executionHistory.first?.success == true {
                withAnimation(.spring(response: 0.35)) { completedSceneId = scene.id }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { completedSceneId = nil }
                }
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

struct CompactSceneButton: View {
    let scene: AutomationScene
    let isRunning: Bool
    let isCompleted: Bool
    let onRun: () -> Void

    private var accent: Color {
        switch scene.color {
        case .amber:  return Color(hex: "#F59E0B")
        case .teal:   return Color(hex: "#14B8A6")
        case .indigo: return Color(hex: "#6366F1")
        case .rose:   return Color(hex: "#F43F5E")
        case .purple: return Color(hex: "#A855F7")
        }
    }

    private var accessibilityDescription: String {
        if isRunning { return "\(scene.name)実行中" }
        if isCompleted { return "\(scene.name)完了" }
        return "\(scene.name)シーンを実行"
    }

    var body: some View {
        Button(action: onRun) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Group {
                        if isCompleted {
                            Image(systemName: "checkmark")
                                .foregroundColor(accent)
                                .bold()
                        } else if isRunning {
                            ProgressView().tint(accent)
                        } else {
                            Image(systemName: scene.icon)
                                .foregroundColor(accent)
                        }
                    }
                    .font(.title3)
                    .animation(.spring(response: 0.35), value: isCompleted)
                }
                Text(scene.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .frame(width: 72, height: 80)
            .background(accent.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(accent.opacity(isCompleted ? 0.6 : 0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isRunning)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isRunning ? .updatesFrequently : .isButton)
    }
}

