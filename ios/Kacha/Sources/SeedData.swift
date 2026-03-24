import Foundation
import SwiftData

#if DEBUG
struct SeedData {
    static func insert(into context: ModelContext) {
        // Only seed if no bookings exist AND user has not completed onboarding
        // (avoid polluting real data)
        let hasOnboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        guard !hasOnboarded else { return }

        let descriptor = FetchDescriptor<Booking>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }

        // Don't seed in DEBUG — use real data only
        // Seed data was removed to prevent confusion with real bookings
    }
}
#endif
