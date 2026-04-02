import SwiftUI
import SwiftData

// MARK: - TeamView

struct TeamView: View {
    let home: Home

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ShareRecord.createdAt, order: .reverse) private var allRecords: [ShareRecord]
    @ObservedObject private var subscription = SubscriptionManager.shared

    @State private var showNewShare = false
    @State private var revokeTarget: ShareRecord?
    @State private var showRevokeConfirm = false
    @State private var revoking = false
    @State private var showRoleLegend = false

    private var records: [ShareRecord] {
        allRecords.filter { $0.homeId == home.id }
    }

    private var activeMembers: [ShareRecord] {
        records.filter { $0.isActive }
    }

    private var inactiveMembers: [ShareRecord] {
        records.filter { !$0.isActive }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()

                if !subscription.isBusiness {
                    ScrollView {
                        VStack(spacing: 20) {
                            headerCard
                            UpgradePromptView(
                                title: "チーム管理はBusinessプランで",
                                message: "メンバーの招待・権限管理はBusinessプランで利用できます。チームでの民泊運営を効率化しましょう。",
                                requiredPlan: "business"
                            )
                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            headerCard
                            if !activeMembers.isEmpty {
                                memberSection(title: "有効なメンバー", members: activeMembers, isActive: true)
                            }
                            if !inactiveMembers.isEmpty {
                                memberSection(title: "過去のメンバー", members: inactiveMembers, isActive: false)
                            }
                            if records.isEmpty {
                                emptyState
                            }
                            roleLegendCard
                            inviteButton
                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showNewShare) {
                HomeShareView(home: home)
            }
            .alert("このメンバーのアクセスを取り消しますか？", isPresented: $showRevokeConfirm) {
                Button("取り消す", role: .destructive) {
                    if let target = revokeTarget {
                        Task { await revokeRecord(target) }
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                if let r = revokeTarget {
                    Text("\(r.recipientName.isEmpty ? "ゲスト" : r.recipientName)のアクセス権を取り消します。取り消し後は物件にアクセスできなくなります。")
                }
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("チーム管理").font(.headline).bold().foregroundColor(.white)
                    Text(home.name).font(.caption).foregroundColor(.kacha)
                }
                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.bottom, 16)

            HStack(spacing: 20) {
                statColumn(value: "\(activeMembers.count)", label: "有効", color: .kachaSuccess)
                statColumn(value: "\(records.count)", label: "累計", color: .kacha)
                statColumn(value: "\(roleCount("admin"))", label: "管理者", color: .kachaWarn)
                statColumn(value: "\(roleCount("cleaner"))", label: "清掃", color: .kachaAccent)
            }
        }
        .padding(16)
        .background(Color.kachaCard)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.kachaCardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statColumn(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2).bold().foregroundColor(color)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func roleCount(_ role: String) -> Int {
        activeMembers.filter { $0.role == role }.count
    }

    // MARK: - Member Section

    private func memberSection(title: String, members: [ShareRecord], isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: isActive ? "person.2.fill" : "clock.arrow.circlepath")
                    .foregroundColor(isActive ? .kacha : .secondary)
                Text(title).font(.subheadline).bold().foregroundColor(.white)
                Spacer()
                Text("\(members.count)人")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)

            ForEach(members) { record in
                memberCard(record)
            }
        }
    }

    private func memberCard(_ record: ShareRecord) -> some View {
        KachaCard {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(roleColor(record.role).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Text(avatarInitial(record.recipientName))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(roleColor(record.role))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(record.recipientName.isEmpty ? "ゲスト" : record.recipientName)
                            .font(.subheadline).bold().foregroundColor(.white)

                        Text(record.roleLabel)
                            .font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(roleColor(record.role).opacity(0.2))
                            .foregroundColor(roleColor(record.role))
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 4) {
                        statusDot(record)
                        Text(record.statusLabel)
                            .font(.caption2)
                            .foregroundColor(record.isActive ? .kachaSuccess : .secondary)
                    }

                    Text("\(formatted(record.validFrom)) 〜 \(formatted(record.expiresAt))")
                        .font(.caption2).foregroundColor(.secondary)
                }

                Spacer()

                if record.isActive || (!record.revoked && Date() < record.validFrom) {
                    Button {
                        revokeTarget = record
                        showRevokeConfirm = true
                    } label: {
                        Text("取り消す")
                            .font(.caption2).bold()
                            .foregroundColor(.kachaDanger)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.kachaDanger.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(14)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        KachaCard {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.kacha.opacity(0.1))
                        .frame(width: 64, height: 64)
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 28))
                        .foregroundColor(.kacha)
                }

                Text("まだメンバーがいません")
                    .font(.subheadline).bold().foregroundColor(.white)

                Text("清掃スタッフやマネージャーを招待して\n物件管理を効率化しましょう")
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }

    // MARK: - Role Legend

    private var roleLegendCard: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "info.circle.fill").foregroundColor(.kacha)
                    Text("ロール権限一覧").font(.subheadline).bold().foregroundColor(.white)
                    Spacer()
                    Button {
                        withAnimation { showRoleLegend.toggle() }
                    } label: {
                        Image(systemName: showRoleLegend ? "chevron.up" : "chevron.down")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                if showRoleLegend {
                    VStack(spacing: 8) {
                        roleLegendRow(
                            role: "オーナー代理",
                            color: .kachaWarn,
                            permissions: ["デバイス操作", "予約管理", "料金設定", "メンバー招待"]
                        )
                        roleLegendRow(
                            role: "マネージャー",
                            color: .kacha,
                            permissions: ["デバイス操作", "予約閲覧", "ゲスト対応"]
                        )
                        roleLegendRow(
                            role: "清掃スタッフ",
                            color: .kachaSuccess,
                            permissions: ["チェックリスト", "清掃報告", "入室"]
                        )
                        roleLegendRow(
                            role: "ゲスト",
                            color: .kachaAccent,
                            permissions: ["ドアコード閲覧", "WiFi情報", "ハウスマニュアル"]
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(16)
        }
    }

    private func roleLegendRow(role: String, color: Color, permissions: [String]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(role)
                .font(.caption).bold()
                .foregroundColor(color)
                .frame(width: 80, alignment: .leading)

            FlowLayout(spacing: 4) {
                ForEach(permissions, id: \.self) { perm in
                    Text(perm)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Invite Button

    private var inviteButton: some View {
        Button { showNewShare = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").font(.system(size: 14))
                Text("メンバーを招待").font(.subheadline).bold()
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.kacha)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Actions

    private func revokeRecord(_ record: ShareRecord) async {
        revoking = true
        defer { revoking = false }
        do {
            try await ShareClient.revokeShare(token: record.token, ownerToken: record.ownerToken)
            record.revoked = true
            ActivityLogger.log(
                context: context,
                homeId: record.homeId,
                action: "team_revoke",
                detail: "\(record.recipientName.isEmpty ? "ゲスト" : record.recipientName)のアクセスを取り消し"
            )
            try? context.save()
        } catch {
            record.revoked = true
            try? context.save()
        }
    }

    // MARK: - Helpers

    private func avatarInitial(_ name: String) -> String {
        guard let first = name.first, !name.isEmpty else { return "G" }
        return String(first)
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "admin":   return .kachaWarn
        case "manager": return .kacha
        case "cleaner": return .kachaSuccess
        default:        return .kachaAccent
        }
    }

    private func statusDot(_ record: ShareRecord) -> some View {
        Circle()
            .fill(record.isActive ? Color.kachaSuccess : (record.revoked ? Color.kachaDanger : Color.secondary))
            .frame(width: 6, height: 6)
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d HH:mm"
        return f.string(from: date)
    }
}

// MARK: - FlowLayout (simple horizontal wrap)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? .infinity, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func layout(in maxWidth: CGFloat, subviews: Subviews) -> (offsets: [CGPoint], size: CGSize) {
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (offsets, CGSize(width: maxX, height: y + rowHeight))
    }
}
