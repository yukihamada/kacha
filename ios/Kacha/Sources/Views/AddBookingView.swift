import SwiftUI
import SwiftData

struct AddBookingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var guestName = ""
    @State private var guestEmail = ""
    @State private var guestPhone = ""
    @State private var platform = "airbnb"
    @State private var checkIn = Date()
    @State private var checkOut = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    @State private var totalAmount = ""
    @State private var notes = ""
    @State private var autoUnlock = true
    @State private var autoLight = true

    private let platforms = [
        ("airbnb", "Airbnb", "FF5A5F"),
        ("jalan", "じゃらん", "FF6600"),
        ("direct", "直接予約", "3B9FE8"),
        ("other", "その他", "6B7280")
    ]

    private var isValid: Bool { !guestName.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kachaBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        guestInfoSection
                        platformSection
                        datesSection
                        amountSection
                        autoActionsSection
                        notesSection
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("予約を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kachaBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { saveBooking() }
                        .bold()
                        .foregroundColor(isValid ? .kacha : .secondary)
                        .disabled(!isValid)
                }
            }
        }
    }

    // MARK: - Sections

    private var guestInfoSection: some View {
        KachaCard {
            VStack(spacing: 14) {
                formField(label: "ゲスト名 *", icon: "person.fill", text: $guestName, placeholder: "山田 太郎")
                Divider().background(Color.kachaCardBorder)
                formField(label: "メールアドレス", icon: "envelope.fill", text: $guestEmail,
                          placeholder: "guest@example.com", keyboard: .emailAddress)
                Divider().background(Color.kachaCardBorder)
                formField(label: "電話番号", icon: "phone.fill", text: $guestPhone,
                          placeholder: "090-0000-0000", keyboard: .phonePad)
            }
            .padding(16)
        }
    }

    private var platformSection: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "globe").foregroundColor(.kacha)
                    Text("プラットフォーム").font(.subheadline).bold().foregroundColor(.white)
                }

                HStack(spacing: 8) {
                    ForEach(platforms, id: \.0) { (key, label, hexColor) in
                        Button {
                            platform = key
                        } label: {
                            Text(label)
                                .font(.caption).bold()
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(platform == key
                                            ? Color(hex: hexColor).opacity(0.3)
                                            : Color.kachaCard)
                                .foregroundColor(platform == key
                                                 ? Color(hex: hexColor)
                                                 : .secondary)
                                .overlay(
                                    Capsule().stroke(
                                        platform == key ? Color(hex: hexColor).opacity(0.5) : Color.clear,
                                        lineWidth: 1
                                    )
                                )
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var datesSection: some View {
        KachaCard {
            VStack(spacing: 12) {
                DatePicker("チェックイン", selection: $checkIn, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .foregroundColor(.white)
                    .colorScheme(.dark)
                    .onChange(of: checkIn) { _, newValue in
                        if checkOut <= newValue {
                            checkOut = Calendar.current.date(byAdding: .day, value: 1, to: newValue) ?? newValue
                        }
                    }

                Divider().background(Color.kachaCardBorder)

                DatePicker(
                    "チェックアウト",
                    selection: $checkOut,
                    in: (Calendar.current.date(byAdding: .day, value: 1, to: checkIn) ?? checkIn)...,
                    displayedComponents: .date
                )
                    .datePickerStyle(.compact)
                    .foregroundColor(.white)
                    .colorScheme(.dark)

                Divider().background(Color.kachaCardBorder)

                let nights = Calendar.current.dateComponents([.day], from: checkIn, to: checkOut).day ?? 0
                HStack {
                    Image(systemName: "moon.fill").foregroundColor(.kachaAccent)
                    Text("\(nights)泊")
                        .font(.subheadline).bold()
                        .foregroundColor(.white)
                    Spacer()
                }
            }
            .padding(16)
        }
    }

    private var amountSection: some View {
        KachaCard {
            HStack {
                Image(systemName: "yensign.circle.fill").foregroundColor(.kacha)
                Text("金額").font(.subheadline).bold().foregroundColor(.white)
                Spacer()
                TextField("0", text: $totalAmount)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.white)
                    .frame(width: 120)
                Text("円").foregroundColor(.secondary)
            }
            .padding(16)
        }
    }

    private var autoActionsSection: some View {
        KachaCard {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "bolt.fill").foregroundColor(.kacha)
                    Text("自動アクション").font(.subheadline).bold().foregroundColor(.white)
                    Spacer()
                }

                Toggle(isOn: $autoUnlock) {
                    Label("チェックイン時に自動解錠", systemImage: "lock.open.fill")
                        .font(.subheadline).foregroundColor(.white)
                }
                .tint(.kacha)

                Toggle(isOn: $autoLight) {
                    Label("ウェルカムライト自動点灯", systemImage: "lightbulb.fill")
                        .font(.subheadline).foregroundColor(.white)
                }
                .tint(.kacha)
            }
            .padding(16)
        }
    }

    private var notesSection: some View {
        KachaCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "note.text").foregroundColor(.kacha)
                    Text("メモ").font(.subheadline).bold().foregroundColor(.white)
                }
                TextEditor(text: $notes)
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .frame(height: 80)
                    .overlay(
                        Group {
                            if notes.isEmpty {
                                Text("アレルギー情報、特記事項など")
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 4)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                        }
                    )
            }
            .padding(16)
        }
    }

    // MARK: - Helpers

    private func formField(
        label: String,
        icon: String,
        text: Binding<String>,
        placeholder: String,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.kacha)
                .frame(width: 24)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            TextField(placeholder, text: text)
                .foregroundColor(.white)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
        }
    }

    private func saveBooking() {
        let booking = Booking(
            guestName: guestName.trimmingCharacters(in: .whitespaces),
            guestEmail: guestEmail,
            guestPhone: guestPhone,
            platform: platform,
            checkIn: checkIn,
            checkOut: checkOut,
            totalAmount: Int(totalAmount) ?? 0,
            notes: notes,
            autoUnlock: autoUnlock,
            autoLight: autoLight
        )
        context.insert(booking)

        if autoUnlock {
            NotificationManager.shared.scheduleCheckInReminder(booking: booking)
            NotificationManager.shared.scheduleCheckOutReminder(booking: booking)
            NotificationManager.shared.scheduleCleaningReminder(booking: booking)
        }

        dismiss()
    }
}
