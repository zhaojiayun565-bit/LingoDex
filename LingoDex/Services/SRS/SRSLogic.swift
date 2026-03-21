import Foundation

enum SRSLogic {
    /// Simple MVP intervals (in days) for the Again/Hard/Good/Easy states.
    static func intervalDays(for rating: SRSRating) -> Double {
        switch rating {
        case .again: return 1
        case .hard: return 5
        case .good: return 20
        case .easy: return 60
        }
    }

    /// Updates SRS state for a word based on the user's self-rating.
    ///
    /// - Note: For MVP we use a lightweight multiplier when the user repeats the same rating.
    static func nextState(
        current: SRSCardState,
        rating: SRSRating,
        now: Date
    ) -> SRSCardState {
        let base = intervalDays(for: rating)

        // MVP multiplier: if the user rates the same grade again, increase the interval.
        let multiplier: Double = (current.rating == rating) ? 2 : 1
        let days = base * multiplier

        let next = Calendar.current.date(byAdding: .day, value: Int(days.rounded(.up)), to: now)
        return SRSCardState(
            rating: rating,
            nextDueDate: next,
            lastReviewedAt: now
        )
    }
}

