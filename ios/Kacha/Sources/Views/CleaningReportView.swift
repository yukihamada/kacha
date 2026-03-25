import SwiftUI
import SwiftData
import PhotosUI

// MARK: - CleaningReportView
// 清掃スタッフ専用画面。チェックアウト後の清掃フロー全体を管理する。

struct CleaningReportView: View {
    let home: Home
    let cleanerName: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var report: CleaningReport
    @State private var checklistItems: [CleaningCheckItem]
    @State private var notes: String = ""
    @State private var suppliesNeeded: String = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoImages: [UIImage] = []
    @State private var showPhotosPicker = false
    @State private var isCompleting = false
    @State private var showCompletionAlert = false
    @State private var showCompletedBanner = false
    @State private var elapsedSeconds: Int = 0
    @State private var timerTask: Task<Void, Never>?

    private let maxPhotos = 5

    init(home: Home, cleanerName: String) {
        self.home = home
        self.cleanerName = cleanerName
        let r = CleaningReport(homeId: home.id, homeName: home.name, cleanerName: cleanerName)
        _report = State(initialValue: r)
        _checklistItems = State(initialValue: r.checklist)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.kachaBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        headerSection
                        timerSection
                        checklistSection
                        photoSection
                        notesSection
                        suppliesSection
                        completeButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 48)
                }

                // 完了バナー
                if showCompletedBanner {
                    completedBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                }
            }
            .navigationTitle("清掃レポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
            .onAppear { startTimer() }
            .onDisappear { timerTask?.cancel() }
            .alert("清掃を完了しますか？", isPresented: $showCompletionAlert) {
                Button("完了する", role: .none) { Task { await completeReport() } }
                Button("キャンセル", role: .cancel) {}
            } message: {
                let done = checklistItems.filter(\.isChecked).count
                let total = checklistItems.count
                if done < total {
                    Text("チェックリストが \(total - done) 件未完了です。このまま完了しますか？")
                } else {
                    Text("全項目が完了しています。オーナーに通知を送ります。")
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(.kacha)
            Text(home.name)
                .font(.title3).bold().foregroundColor(.white)
            Text("清掃スタッフ: \(cleanerName)")
                .font(.caption).foregroundColor(.secondary)
            Text(report.startedAt, style: .time)
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.top, 8)
    }

    private var timerSection: some View {
        KachaCard {
            HStack(spacing: 16) {
                Image(systemName: "timer")
                    .font(.title2)
                    .foregroundColor(.kacha)
                VStack(alignment: .leading, spacing: 2) {
                    Text("経過時間").font(.caption).foregroundColor(.secondary)
                    Text(formatElapsed(elapsedSeconds))
                        .font(.system(.title2, design: .monospaced)).bold()
                        .foregroundColor(.white)
                }
                Spacer()
                // 進捗インジケーター
                let done = checklistItems.filter(\.isChecked).count
                let total = checklistItems.count
                VStack(spacing: 4) {
                    Text("\(done)/\(total)")
                        .font(.caption).bold()
                        .foregroundColor(done == total ? .kachaSuccess : .kacha)
                    Text("完了").font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(16)
        }
    }

    private var checklistSection: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.clipboard.fill").foregroundColor(.kacha)
                    Text("チェックリスト").font(.subheadline).bold().foregroundColor(.white)
                    Spacer()
                    let done = checklistItems.filter(\.isChecked).count
                    Text("\(done)/\(checklistItems.count)")
                        .font(.caption2)
                        .foregroundColor(done == checklistItems.count ? .kachaSuccess : .secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider().background(Color.kachaCardBorder)

                // カテゴリごとにグループ表示
                let categories = ["cleaning", "check", "supplies"]
                ForEach(categories, id: \.self) { cat in
                    let items = checklistItems.filter { $0.category == cat }
                    if !items.isEmpty {
                        categoryHeader(cat)
                        ForEach(items) { item in
                            checklistRow(item)
                        }
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func categoryHeader(_ category: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: CleaningCheckItem.categoryIcon(category))
                .font(.caption)
                .foregroundColor(.kacha)
            Text(CleaningCheckItem.categoryLabel(category))
                .font(.caption2).bold()
                .foregroundColor(.kacha)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func checklistRow(_ item: CleaningCheckItem) -> some View {
        Button {
            withAnimation(.spring(response: 0.25)) {
                toggleItem(item)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isChecked ? .kachaSuccess : .secondary)
                    .font(.title3)
                Text(item.title)
                    .font(.subheadline)
                    .foregroundColor(item.isChecked ? .secondary : .white)
                    .strikethrough(item.isChecked, color: .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(item.isChecked ? Color.kachaSuccess.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var photoSectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "camera.fill").foregroundColor(.kacha)
            Text("写真 (\(photoImages.count)/\(maxPhotos))")
                .font(.subheadline).bold().foregroundColor(.white)
            Spacer()
            if photoImages.count < maxPhotos {
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: maxPhotos - photoImages.count,
                    matching: .images
                ) {
                    Label("追加", systemImage: "plus.circle.fill")
                        .font(.caption).bold()
                        .foregroundColor(.kacha)
                }
                .onChange(of: selectedPhotos) { _, items in
                    Task { await loadSelectedPhotos(items) }
                }
            }
        }
    }

    private var photoPlaceholder: some View {
        Button {
            showPhotosPicker = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "camera.badge.plus")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text("タップして写真を追加")
                    .font(.caption).foregroundColor(.secondary)
                Text("清掃前後・問題箇所を記録 (最大5枚)")
                    .font(.caption2).foregroundColor(Color.secondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color.kachaCard)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundColor(Color.kachaCardBorder)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $selectedPhotos,
            maxSelectionCount: maxPhotos,
            matching: .images
        )
        .onChange(of: selectedPhotos) { _, items in
            Task { await loadSelectedPhotos(items) }
        }
    }

    private func removePhoto(at index: Int) {
        photoImages.remove(at: index)
    }

    private func photoThumbnail(index i: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: photoImages[i])
                .resizable()
                .scaledToFill()
                .frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Button {
                withAnimation { removePhoto(at: i) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white)
                    .background(Color.kachaDanger)
                    .clipShape(Circle())
            }
            .offset(x: 4, y: -4)
        }
    }

    private var photoGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(photoImages.indices, id: \.self) { i in
                    photoThumbnail(index: i)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var photoSection: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 12) {
                photoSectionHeader
                if photoImages.isEmpty { photoPlaceholder } else { photoGrid }
            }
            .padding(16)
        }
    }

    private var notesSection: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "note.text").foregroundColor(.kacha)
                    Text("メモ・特記事項").font(.subheadline).bold().foregroundColor(.white)
                }
                TextField("気になった点や連絡事項を記入...", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.kachaCard)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.kachaCardBorder))
            }
            .padding(16)
        }
    }

    private var suppliesSection: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "archivebox.fill").foregroundColor(.kachaWarn)
                    Text("備品補充メモ").font(.subheadline).bold().foregroundColor(.white)
                    Spacer()
                    if !suppliesNeeded.isEmpty {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.kachaWarn)
                            .font(.caption)
                    }
                }
                TextField("例: シャンプー残り少ない、タオル追加必要...", text: $suppliesNeeded, axis: .vertical)
                    .lineLimit(2...4)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.kachaCard)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(suppliesNeeded.isEmpty ? Color.kachaCardBorder : Color.kachaWarn.opacity(0.5))
                    )
                Text("入力するとオーナーへの通知に含まれます")
                    .font(.caption2).foregroundColor(.secondary)
            }
            .padding(16)
        }
    }

    private var completeButton: some View {
        let allChecked = checklistItems.allSatisfy(\.isChecked)
        return Button {
            showCompletionAlert = true
        } label: {
            HStack(spacing: 8) {
                if isCompleting {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: allChecked ? "checkmark.seal.fill" : "checkmark.circle")
                }
                Text(allChecked ? "清掃完了を報告する" : "清掃完了（一部未チェック）")
                    .bold()
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(allChecked ? Color.kachaSuccess : Color.kacha)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isCompleting)
        .padding(.top, 4)
        .accessibilityLabel(isCompleting ? "送信中" : (allChecked ? "清掃完了を報告する" : "清掃完了（一部未チェック）"))
        .accessibilityHint(isCompleting ? "" : "ダブルタップでオーナーに通知を送ります")
    }

    private var completedBanner: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundColor(.kachaSuccess)
                Text("清掃完了をオーナーに通知しました").font(.subheadline).bold().foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Color(hex: "0F2D1F"))
        .overlay(
            Rectangle()
                .frame(height: 2)
                .foregroundColor(.kachaSuccess)
                .frame(maxHeight: .infinity, alignment: .bottom)
        )
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Actions

    private func toggleItem(_ item: CleaningCheckItem) {
        guard let idx = checklistItems.firstIndex(where: { $0.id == item.id }) else { return }
        checklistItems[idx].isChecked.toggle()
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        await MainActor.run {
            photoImages.append(contentsOf: loaded)
            if photoImages.count > maxPhotos {
                photoImages = Array(photoImages.prefix(maxPhotos))
            }
            selectedPhotos = []
        }
    }

    private func completeReport() async {
        isCompleting = true

        // 写真をローカルに保存
        let savedPaths = savePhotos()

        // レポートを更新
        report.checklist = checklistItems
        report.notes = notes
        report.suppliesNeeded = suppliesNeeded
        report.photoPaths = savedPaths.joined(separator: ",")
        report.completedAt = Date()
        report.status = "completed"

        // SwiftDataに保存
        context.insert(report)
        try? context.save()

        // オーナーへ通知
        CleaningNotificationService.notifyCleaningCompleted(report: report)
        if !suppliesNeeded.isEmpty {
            CleaningNotificationService.scheduleSuppliesReminder(
                homeName: home.name,
                supplies: suppliesNeeded,
                reportId: report.id
            )
        }

        isCompleting = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        timerTask?.cancel()

        withAnimation(.spring(response: 0.4)) { showCompletedBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            dismiss()
        }
    }

    /// 写真をDocuments/CleaningPhotos/へ保存し、ファイル名リストを返す
    private func savePhotos() -> [String] {
        let fm = FileManager.default
        guard let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        let folderURL = docsURL.appendingPathComponent("CleaningPhotos", isDirectory: true)
        try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var paths: [String] = []
        for (i, image) in photoImages.enumerated() {
            let filename = "\(report.id)_\(i).jpg"
            let fileURL = folderURL.appendingPathComponent(filename)
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: fileURL)
                paths.append(filename)
            }
        }
        return paths
    }

    private func startTimer() {
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run { elapsedSeconds += 1 }
            }
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - CleaningReportListView
// 過去の清掃レポート一覧（オーナー向け）

struct CleaningReportListView: View {
    let homeId: String
    @Environment(\.dismiss) private var dismiss
    @Query private var reports: [CleaningReport]

    init(homeId: String) {
        self.homeId = homeId
        _reports = Query(
            filter: #Predicate<CleaningReport> { $0.homeId == homeId },
            sort: \.startedAt,
            order: .reverse
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                if reports.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(reports) { report in
                                reportCard(report)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle("清掃レポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            Text("清掃レポートはまだありません")
                .font(.subheadline).bold()
                .foregroundColor(.white)
            Text("清掃スタッフがレポートを提出すると\nここに表示されます")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("清掃レポートはまだありません")
    }

    private func reportCard(_ report: CleaningReport) -> some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.cleanerName).font(.subheadline).bold().foregroundColor(.white)
                        Text(report.startedAt, style: .date).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    statusBadge(report.status)
                }

                HStack(spacing: 16) {
                    statItem("timer", report.durationLabel)
                    let done = report.checklist.filter(\.isChecked).count
                    let total = report.checklist.count
                    statItem("checkmark.circle", "\(done)/\(total)")
                    if !report.photoPathList.isEmpty {
                        statItem("photo", "\(report.photoPathList.count)枚")
                    }
                }

                if !report.suppliesNeeded.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "archivebox.fill")
                            .font(.caption).foregroundColor(.kachaWarn)
                        Text(report.suppliesNeeded)
                            .font(.caption).foregroundColor(.kachaWarn)
                            .lineLimit(1)
                    }
                }

                if !report.notes.isEmpty {
                    Text(report.notes)
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(14)
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let (label, color) = status == "completed"
            ? ("完了", Color.kachaSuccess)
            : ("進行中", Color.kacha)
        return Text(label)
            .font(.caption2).bold()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func statItem(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2).foregroundColor(.kacha)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }
}
