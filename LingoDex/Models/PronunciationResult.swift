import Foundation

struct PronunciationResult: Sendable, Codable, Equatable {
    let isCorrect: Bool
    let transcript: String
    /// Accuracy 0...1; isCorrect when accuracy >= 0.6
    let accuracy: Double
}

