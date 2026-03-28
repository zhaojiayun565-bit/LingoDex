import Foundation

/// Response from the recognize-object Edge Function (Gemini).
struct GeminiRecognitionResult: Sendable, Codable, Equatable {
    let objectName: String?
    let targetTranslation: String
    let phoneticBreakdown: String?
    let category: String
    let confidence: Double
    let exampleSentences: [String]
    let errorFeedback: String?

    enum CodingKeys: String, CodingKey {
        case objectName = "object_name"
        case targetTranslation = "target_translation"
        case phoneticBreakdown = "phonetic_breakdown"
        case category
        case confidence
        case exampleSentences = "example_sentences"
        case errorFeedback = "error_feedback"
    }
}
