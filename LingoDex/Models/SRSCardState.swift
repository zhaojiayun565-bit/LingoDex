import Foundation

struct SRSCardState: Sendable, Codable, Equatable {
    var rating: SRSRating = .good
    var nextDueDate: Date? = nil
    var lastReviewedAt: Date? = nil
}

