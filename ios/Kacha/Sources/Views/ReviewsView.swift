import SwiftUI
import SwiftData

// MARK: - GuestReview (SwiftData Model)

@Model
final class GuestReview {
    var id: String
    var homeId: String
    var platform: String       // "Airbnb", "Booking.com", "じゃらん", "Google", "その他"
    var rating: Int            // 1-5
    var comment: String
    var guestName: String
    var reviewDate: Date
    var replyText: String
    var createdAt: Date

    init(
        homeId: String,
        platform: String = "Airbnb",
        rating: Int = 5,
        comment: String = "",
        guestName: String = "",
        reviewDate: Date = Date(),
        replyText: String = ""
    ) {
        self.id = UUID().uuidString
        self.homeId = homeId
        self.platform = platform
        self.rating = rating
        self.comment = comment
        self.guestName = guestName
        self.reviewDate = reviewDate
        self.replyText = replyText
        self.createdAt = Date()
    }
}

// MARK: - ReviewsView

struct ReviewsView: View {
    let home: Home

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \GuestReview.reviewDate, order: .reverse) private var allReviews: [GuestReview]

    @State private var showAddReview = false
    @State private var showReplySheet = false
    @State private var selectedReview: GuestReview?
    @State private var isSyncing = false
    @State private var syncMessage: String?

    private var reviews: [GuestReview] {
        allReviews.filter { $0.homeId == home.id }
    }

    private var averageRating: Double {
        guard !reviews.isEmpty else { return 0 }
        return Double(reviews.reduce(0) { $0 + $1.rating }) / Double(reviews.count)
    }

    private var ratingDistribution: [Int: Int] {
        var dist: [Int: Int] = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
        for review in reviews {
            dist[review.rating, default: 0] += 1
        }
        return dist
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        headerCard
                        statsCard
                        if !reviews.isEmpty {
                            reviewsList
                        } else {
                            emptyState
                        }
                        addReviewButton
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showAddReview) {
                AddReviewSheet(home: home)
            }
            .sheet(item: $selectedReview) { review in
                ReplySheet(review: review)
            }
            .task { await syncReviewsFromOTAs() }
        }
    }

    // MARK: - OTA Review Sync

    private func syncReviewsFromOTAs() async {
        guard !home.beds24RefreshToken.isEmpty else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let token = try await Beds24Client.shared.getToken(refreshToken: home.beds24RefreshToken)
            let propId = Int(home.beds24ApiKey) ?? 0
            var imported = 0

            // Airbnb reviews
            let existingIds = Set(reviews.map(\.id))
            let airbnbURL = URL(string: "https://beds24.com/api/v2/channels/airbnb/reviews?roomId=\(home.beds24ApiKey.isEmpty ? "0" : String(propId))")!
            // Use roomId from booking poller
            for roomId in [512691, 512692, 512693, 512694] {
                guard let url = URL(string: "https://beds24.com/api/v2/channels/airbnb/reviews?roomId=\(roomId)") else { continue }
                var req = URLRequest(url: url)
                req.addValue(token, forHTTPHeaderField: "token")
                guard let (data, _) = try? await URLSession.shared.data(for: req),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let items = json["data"] as? [[String: Any]] else { continue }

                for item in items {
                    let reviewId = item["id"] as? String ?? UUID().uuidString
                    guard !existingIds.contains("airbnb-\(reviewId)") else { continue }

                    let rating = item["overall_rating"] as? Int ?? 0
                    guard rating > 0 else { continue }
                    let comment = item["public_review"] as? String ?? ""
                    let dateStr = item["submitted_at"] as? String ?? ""
                    let date = ISO8601DateFormatter().date(from: dateStr) ?? Date()

                    let review = GuestReview(
                        homeId: home.id,
                        platform: "Airbnb",
                        rating: min(rating, 5),
                        comment: comment,
                        guestName: "",
                        reviewDate: date
                    )
                    review.id = "airbnb-\(reviewId)"
                    context.insert(review)
                    imported += 1
                }
            }

            // Booking.com reviews
            guard let bcomURL = URL(string: "https://beds24.com/api/v2/channels/booking/reviews?propertyId=\(propId)&from=2024-01-01") else { return }
            var bcomReq = URLRequest(url: bcomURL)
            bcomReq.addValue(token, forHTTPHeaderField: "token")
            if let (data, _) = try? await URLSession.shared.data(for: bcomReq),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["data"] as? [[String: Any]] {
                for item in items {
                    let reviewId = item["review_id"] as? String ?? UUID().uuidString
                    guard !existingIds.contains("bcom-\(reviewId)") else { continue }

                    let scoring = item["scoring"] as? [String: Any] ?? [:]
                    let score10 = scoring["review_score"] as? Double ?? 0
                    let rating5 = Int(round(score10 / 2.0))
                    guard rating5 > 0 else { continue }

                    let content = item["content"] as? [String: Any] ?? [:]
                    let positive = content["positive"] as? String ?? ""
                    let negative = content["negative"] as? String ?? ""
                    let comment = [positive, negative].filter { !$0.isEmpty }.joined(separator: " / ")

                    let reviewer = item["reviewer"] as? [String: Any] ?? [:]
                    let guestName = reviewer["name"] as? String ?? ""
                    let dateStr = item["created_timestamp"] as? String ?? ""

                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    let date = df.date(from: dateStr) ?? Date()

                    let review = GuestReview(
                        homeId: home.id,
                        platform: "Booking.com",
                        rating: min(max(rating5, 1), 5),
                        comment: comment,
                        guestName: guestName,
                        reviewDate: date
                    )
                    review.id = "bcom-\(reviewId)"
                    context.insert(review)
                    imported += 1
                }
            }

            if imported > 0 {
                try? context.save()
                syncMessage = "\(imported)件のレビューを取得しました"
            }
        } catch {
            #if DEBUG
            print("[Reviews] Sync error: \(error)")
            #endif
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
                    Text("レビュー管理").font(.headline).bold().foregroundColor(.white)
                    Text(home.name).font(.caption).foregroundColor(.kacha)
                }
                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.bottom, 16)

            // Overall rating display
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", averageRating))
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.kacha)
                    starsRow(rating: averageRating)
                    Text("\(reviews.count)件のレビュー")
                        .font(.caption2).foregroundColor(.secondary)
                }

                Spacer()

                // Rating distribution bars
                VStack(spacing: 4) {
                    ForEach((1...5).reversed(), id: \.self) { star in
                        distributionRow(star: star)
                    }
                }
                .frame(maxWidth: 160)
            }
        }
        .padding(16)
        .background(Color.kachaCard)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.kachaCardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func starsRow(rating: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: starIcon(for: star, rating: rating))
                    .font(.system(size: 12))
                    .foregroundColor(.kacha)
            }
        }
    }

    private func starIcon(for star: Int, rating: Double) -> String {
        if Double(star) <= rating {
            return "star.fill"
        } else if Double(star) - 0.5 <= rating {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }

    private func distributionRow(star: Int) -> some View {
        let count = ratingDistribution[star] ?? 0
        let maxCount = ratingDistribution.values.max() ?? 1
        let ratio = maxCount > 0 ? CGFloat(count) / CGFloat(maxCount) : 0

        return HStack(spacing: 6) {
            Text("\(star)")
                .font(.caption2).foregroundColor(.secondary)
                .frame(width: 12, alignment: .trailing)
            Image(systemName: "star.fill")
                .font(.system(size: 8)).foregroundColor(.kacha.opacity(0.5))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.kacha)
                        .frame(width: geo.size.width * ratio, height: 6)
                }
            }
            .frame(height: 6)

            Text("\(count)")
                .font(.caption2).foregroundColor(.secondary)
                .frame(width: 20, alignment: .leading)
        }
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        KachaCard {
            HStack(spacing: 0) {
                statItem(value: String(format: "%.1f", averageRating), label: "平均評価", icon: "star.fill", color: .kacha)
                divider
                statItem(value: "\(reviews.count)", label: "レビュー数", icon: "text.bubble.fill", color: .kachaAccent)
                divider
                statItem(value: platformBreakdown, label: "最多プラット\nフォーム", icon: "globe", color: .kachaSuccess)
            }
            .padding(14)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: 1, height: 40)
    }

    private func statItem(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.caption2).foregroundColor(color)
                Text(value).font(.subheadline).bold().foregroundColor(.white)
            }
            Text(label)
                .font(.caption2).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    private var platformBreakdown: String {
        guard !reviews.isEmpty else { return "-" }
        var counts: [String: Int] = [:]
        for r in reviews { counts[r.platform, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? "-"
    }

    // MARK: - Reviews List

    private var reviewsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "text.bubble.fill").foregroundColor(.kacha)
                Text("レビュー一覧").font(.subheadline).bold().foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 4)

            ForEach(reviews) { review in
                reviewCard(review)
            }
        }
    }

    private func reviewCard(_ review: GuestReview) -> some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(platformColor(review.platform).opacity(0.15))
                            .frame(width: 36, height: 36)
                        Text(String(review.guestName.prefix(1).isEmpty ? "G" : review.guestName.prefix(1)))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(platformColor(review.platform))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(review.guestName.isEmpty ? "ゲスト" : review.guestName)
                            .font(.subheadline).bold().foregroundColor(.white)
                        HStack(spacing: 6) {
                            Text(review.platform)
                                .font(.caption2)
                                .foregroundColor(platformColor(review.platform))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(platformColor(review.platform).opacity(0.15))
                                .clipShape(Capsule())
                            Text(formattedDate(review.reviewDate))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    HStack(spacing: 1) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= review.rating ? "star.fill" : "star")
                                .font(.system(size: 10))
                                .foregroundColor(.kacha)
                        }
                    }
                }

                if !review.comment.isEmpty {
                    Text(review.comment)
                        .font(.caption).foregroundColor(.white.opacity(0.85))
                        .lineLimit(4)
                }

                if !review.replyText.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.caption2).foregroundColor(.kachaSuccess)
                        Text(review.replyText)
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color.kachaSuccess.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Reply button
                if review.replyText.isEmpty {
                    Button {
                        selectedReview = review
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrowshape.turn.up.left")
                            Text("返信する")
                        }
                        .font(.caption2).bold()
                        .foregroundColor(.kacha)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.kacha.opacity(0.12))
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
                    Image(systemName: "star.bubble")
                        .font(.system(size: 28))
                        .foregroundColor(.kacha)
                }

                Text("まだレビューがありません")
                    .font(.subheadline).bold().foregroundColor(.white)

                Text("ゲストからのレビューを手動で追加して\n評価を一元管理しましょう")
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }

    // MARK: - Add Review Button

    private var addReviewButton: some View {
        Button { showAddReview = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").font(.system(size: 14))
                Text("レビューを追加").font(.subheadline).bold()
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.kacha)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Helpers

    private func platformColor(_ platform: String) -> Color {
        switch platform {
        case "Airbnb":      return Color(hex: "FF5A5F")
        case "Booking.com": return Color(hex: "003580")
        case "じゃらん":     return Color(hex: "E95513")
        case "Google":      return Color(hex: "4285F4")
        default:            return .kacha
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/M/d"
        return f.string(from: date)
    }
}

// MARK: - AddReviewSheet

private struct AddReviewSheet: View {
    let home: Home

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var platform = "Airbnb"
    @State private var rating = 5
    @State private var comment = ""
    @State private var guestName = ""
    @State private var reviewDate = Date()

    private let platforms = ["Airbnb", "Booking.com", "じゃらん", "Google", "その他"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Platform picker
                        KachaCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("プラットフォーム").font(.caption).foregroundColor(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(platforms, id: \.self) { p in
                                            Button {
                                                platform = p
                                            } label: {
                                                Text(p)
                                                    .font(.caption).bold()
                                                    .foregroundColor(platform == p ? .black : .white)
                                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                                    .background(platform == p ? Color.kacha : Color.white.opacity(0.08))
                                                    .clipShape(Capsule())
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(14)
                        }

                        // Rating
                        KachaCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("評価").font(.caption).foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    ForEach(1...5, id: \.self) { star in
                                        Button {
                                            rating = star
                                        } label: {
                                            Image(systemName: star <= rating ? "star.fill" : "star")
                                                .font(.system(size: 28))
                                                .foregroundColor(.kacha)
                                        }
                                    }
                                    Spacer()
                                    Text("\(rating).0")
                                        .font(.title2).bold().foregroundColor(.kacha)
                                }
                            }
                            .padding(14)
                        }

                        // Guest name
                        KachaCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ゲスト名").font(.caption).foregroundColor(.secondary)
                                TextField("名前（任意）", text: $guestName)
                                    .font(.subheadline).foregroundColor(.white)
                                    .padding(10)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .padding(14)
                        }

                        // Date
                        KachaCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("レビュー日").font(.caption).foregroundColor(.secondary)
                                DatePicker("", selection: $reviewDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .tint(.kacha)
                            }
                            .padding(14)
                        }

                        // Comment
                        KachaCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("コメント").font(.caption).foregroundColor(.secondary)
                                TextEditor(text: $comment)
                                    .font(.subheadline).foregroundColor(.white)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 100)
                                    .padding(8)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .padding(14)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("レビュー追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveReview() }
                        .foregroundStyle(Color.kacha)
                        .bold()
                }
            }
        }
    }

    private func saveReview() {
        let review = GuestReview(
            homeId: home.id,
            platform: platform,
            rating: rating,
            comment: comment,
            guestName: guestName,
            reviewDate: reviewDate
        )
        context.insert(review)

        ActivityLogger.log(
            context: context,
            homeId: home.id,
            action: "review_add",
            detail: "\(platform)のレビューを追加（\(rating)星）"
        )
        try? context.save()
        dismiss()
    }
}

// MARK: - ReplySheet

private struct ReplySheet: View {
    let review: GuestReview

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var replyText = ""

    private let templates = [
        "ご宿泊いただきありがとうございます！快適にお過ごしいただけたようで嬉しいです。またのお越しをお待ちしております。",
        "素敵なレビューをありがとうございます。ご指摘いただいた点は改善に努めてまいります。",
        "Thank you for staying with us! We're glad you enjoyed your stay. Hope to welcome you back soon!",
        "この度はご利用いただきありがとうございました。お客様のご意見を参考に、サービス向上に努めます。",
        "ご不便をおかけし申し訳ございませんでした。いただいたフィードバックを真摯に受け止め、改善いたします。",
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Original review
                        KachaCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(review.guestName.isEmpty ? "ゲスト" : review.guestName)
                                        .font(.subheadline).bold().foregroundColor(.white)
                                    Spacer()
                                    HStack(spacing: 1) {
                                        ForEach(1...5, id: \.self) { star in
                                            Image(systemName: star <= review.rating ? "star.fill" : "star")
                                                .font(.system(size: 10))
                                                .foregroundColor(.kacha)
                                        }
                                    }
                                }
                                if !review.comment.isEmpty {
                                    Text(review.comment)
                                        .font(.caption).foregroundColor(.white.opacity(0.8))
                                }
                            }
                            .padding(14)
                        }

                        // Quick reply templates
                        KachaCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "text.badge.star").foregroundColor(.kacha)
                                    Text("テンプレート").font(.subheadline).bold().foregroundColor(.white)
                                }

                                ForEach(templates, id: \.self) { template in
                                    Button {
                                        replyText = template
                                    } label: {
                                        Text(template)
                                            .font(.caption2)
                                            .foregroundColor(replyText == template ? .black : .white.opacity(0.7))
                                            .multilineTextAlignment(.leading)
                                            .padding(10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(replyText == template ? Color.kacha : Color.white.opacity(0.06))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                            .padding(14)
                        }

                        // Custom reply
                        KachaCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("返信文").font(.caption).foregroundColor(.secondary)
                                TextEditor(text: $replyText)
                                    .font(.subheadline).foregroundColor(.white)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 100)
                                    .padding(8)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .padding(14)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("返信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveReply() }
                        .foregroundStyle(Color.kacha)
                        .bold()
                        .disabled(replyText.isEmpty)
                }
            }
        }
    }

    private func saveReply() {
        review.replyText = replyText
        try? context.save()
        dismiss()
    }
}
