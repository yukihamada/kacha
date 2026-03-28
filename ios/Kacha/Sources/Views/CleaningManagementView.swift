import SwiftUI
import SwiftData

// MARK: - CleaningManagementView
// 今日の清掃タスク一覧。チェックアウト済み予約を清掃ステータスで管理し、
// 完了時に次のゲストへ自動通知する。

struct CleaningManagementView: View {
    @Query private var bookings: [Booking]
    @Query(sort: \Home.sortOrder) private var homes: [Home]
    @Environment(\.modelContext) private var context

    private var cleaningTasks: [CleaningTask] {
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .hour, value: -24, to: now) ?? now

        return bookings
            .filter { booking in
                let isRelevantStatus = booking.status == "completed" || booking.status == "active"
                let checkOutDay = calendar.startOfDay(for: booking.checkOut)
                let yesterdayStart = calendar.startOfDay(for: yesterday)
                let tomorrowEnd = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)) ?? now
                let isInRange = checkOutDay >= yesterdayStart && checkOutDay < tomorrowEnd
                return isRelevantStatus && isInRange
            }
            .sorted { $0.checkOut < $1.checkOut }
            .map { booking in
                let home = homes.first { $0.id == booking.homeId }
                let nextGuest = findNextGuest(for: booking)
                return CleaningTask(booking: booking, home: home, nextGuest: nextGuest)
            }
    }

    private var completedCount: Int {
        cleaningTasks.filter { $0.booking.cleaningDone }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        statsHeader
                        tasksList
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("清掃管理")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.kachaBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Stats Header

    private var statsHeader: some View {
        KachaCard {
            HStack(spacing: 0) {
                statBlock(
                    icon: "sparkles",
                    value: "\(cleaningTasks.count)",
                    label: "今日の清掃",
                    color: .kacha
                )

                Divider()
                    .frame(height: 40)
                    .background(Color.kachaCardBorder)

                statBlock(
                    icon: "checkmark.circle.fill",
                    value: "\(completedCount)",
                    label: "完了",
                    color: .kachaSuccess
                )

                Divider()
                    .frame(height: 40)
                    .background(Color.kachaCardBorder)

                statBlock(
                    icon: "clock.fill",
                    value: "\(cleaningTasks.count - completedCount)",
                    label: "残り",
                    color: cleaningTasks.count - completedCount > 0 ? .kachaWarn : .secondary
                )
            }
            .padding(.vertical, 16)
        }
    }

    private func statBlock(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.title2).bold()
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tasks List

    @ViewBuilder
    private var tasksList: some View {
        if cleaningTasks.isEmpty {
            emptyState
        } else {
            VStack(spacing: 12) {
                ForEach(cleaningTasks, id: \.booking.id) { task in
                    CleaningTaskCard(
                        task: task,
                        onStart: { startCleaning(task) },
                        onComplete: { completeCleaning(task) }
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            Text("清掃タスクはありません")
                .font(.subheadline).bold()
                .foregroundColor(.white)
            Text("チェックアウト予定の予約があると\nここに清掃タスクが表示されます")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    // MARK: - Actions

    private func startCleaning(_ task: CleaningTask) {
        let homeName = task.home?.name ?? "物件"
        CleaningNotificationService.notifyCleaningStarted(
            homeName: homeName,
            cleanerName: "清掃スタッフ"
        )
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func completeCleaning(_ task: CleaningTask) {
        task.booking.cleaningDone = true
        try? context.save()

        if let nextGuest = task.nextGuest {
            scheduleRoomReadyNotification(
                guestName: nextGuest.guestName,
                bookingId: nextGuest.id,
                homeName: task.home?.name ?? "物件"
            )
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func findNextGuest(for current: Booking) -> Booking? {
        let calendar = Calendar.current
        let checkOutDay = calendar.startOfDay(for: current.checkOut)

        return bookings
            .filter { booking in
                booking.id != current.id &&
                booking.homeId == current.homeId &&
                booking.status == "upcoming" &&
                calendar.startOfDay(for: booking.checkIn) >= checkOutDay
            }
            .sorted { $0.checkIn < $1.checkIn }
            .first
    }

    private func scheduleRoomReadyNotification(guestName: String, bookingId: String, homeName: String) {
        let content = UNMutableNotificationContent()
        content.title = "お部屋の準備が整いました"
        content.body = "\(guestName)様 — \(homeName)のお部屋の清掃が完了し、チェックインの準備ができました。"
        content.sound = .default
        content.userInfo = [
            "type": "room_ready",
            "bookingId": bookingId
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "room_ready_\(bookingId)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - CleaningTask

struct CleaningTask {
    let booking: Booking
    let home: Home?
    let nextGuest: Booking?

    var status: CleaningStatus {
        if booking.cleaningDone { return .completed }
        return .waiting
    }
}

enum CleaningStatus {
    case waiting
    case inProgress
    case completed

    var label: String {
        switch self {
        case .waiting:    return "待機"
        case .inProgress: return "清掃中"
        case .completed:  return "完了"
        }
    }

    var color: Color {
        switch self {
        case .waiting:    return .kachaWarn
        case .inProgress: return .kachaAccent
        case .completed:  return .kachaSuccess
        }
    }

    var icon: String {
        switch self {
        case .waiting:    return "clock.fill"
        case .inProgress: return "figure.walk"
        case .completed:  return "checkmark.circle.fill"
        }
    }
}

// MARK: - CleaningTaskCard

struct CleaningTaskCard: View {
    let task: CleaningTask
    let onStart: () -> Void
    let onComplete: () -> Void

    @State private var isInProgress = false

    private var currentStatus: CleaningStatus {
        if task.booking.cleaningDone { return .completed }
        if isInProgress { return .inProgress }
        return .waiting
    }

    var body: some View {
        KachaCard {
            VStack(spacing: 12) {
                headerRow
                Divider().background(Color.kachaCardBorder)
                detailRow
                if let next = task.nextGuest {
                    nextGuestRow(next)
                }
                if currentStatus == .completed {
                    completionRow
                } else {
                    actionButton
                }
            }
            .padding(16)
        }
    }

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.home?.name ?? "物件")
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
                Text(task.booking.guestName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            statusBadge
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: currentStatus.icon)
                .font(.caption2)
            Text(currentStatus.label)
                .font(.caption2).bold()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(currentStatus.color.opacity(0.15))
        .foregroundColor(currentStatus.color)
        .clipShape(Capsule())
    }

    private var detailRow: some View {
        HStack(spacing: 16) {
            Label {
                Text(task.booking.checkOut.formatted(date: .omitted, time: .shortened))
                    .font(.caption).foregroundColor(.white)
            } icon: {
                Image(systemName: "arrow.left.square")
                    .font(.caption).foregroundColor(.kachaAccent)
            }

            Label {
                Text(task.booking.platformLabel)
                    .font(.caption).foregroundColor(.white)
            } icon: {
                Image(systemName: "globe")
                    .font(.caption).foregroundColor(.kacha)
            }

            if task.booking.guestCount > 0 {
                Label {
                    Text("\(task.booking.guestCount)名")
                        .font(.caption).foregroundColor(.white)
                } icon: {
                    Image(systemName: "person.2.fill")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }

    private func nextGuestRow(_ next: Booking) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.caption)
                .foregroundColor(.kachaAccent)
            Text("次のゲスト: \(next.guestName)")
                .font(.caption)
                .foregroundColor(.kachaAccent)
            Text("(\(next.checkIn.formatted(date: .abbreviated, time: .omitted)))")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(10)
        .background(Color.kachaAccent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var completionRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.kachaSuccess)
            Text("清掃完了")
                .font(.caption).bold()
                .foregroundColor(.kachaSuccess)
            Spacer()
            if task.nextGuest != nil {
                HStack(spacing: 4) {
                    Image(systemName: "bell.fill")
                        .font(.caption2)
                    Text("ゲストに通知済み")
                        .font(.caption2)
                }
                .foregroundColor(.kachaSuccess.opacity(0.7))
            }
        }
        .padding(10)
        .background(Color.kachaSuccess.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var actionButton: some View {
        Button {
            if isInProgress {
                withAnimation(.spring(response: 0.3)) {
                    onComplete()
                }
            } else {
                withAnimation(.spring(response: 0.3)) {
                    isInProgress = true
                    onStart()
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isInProgress ? "checkmark.circle.fill" : "play.fill")
                Text(isInProgress ? "清掃完了" : "清掃開始")
                    .bold()
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isInProgress ? Color.kachaSuccess : Color.kacha)
            .foregroundColor(isInProgress ? .white : .black)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
