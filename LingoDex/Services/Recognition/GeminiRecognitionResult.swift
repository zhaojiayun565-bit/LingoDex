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
        case phoneticBreakdownCamel = "phoneticBreakdown"
        case category
        case confidence
        case exampleSentences = "example_sentences"
        case errorFeedback = "error_feedback"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        objectName = try c.decodeIfPresent(String.self, forKey: .objectName)
        targetTranslation = try c.decode(String.self, forKey: .targetTranslation)

        let rawPhonetic =
            try c.decodeIfPresent(String.self, forKey: .phoneticBreakdown)
            ?? c.decodeIfPresent(String.self, forKey: .phoneticBreakdownCamel)
        if let raw = rawPhonetic {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            phoneticBreakdown = trimmed.isEmpty ? nil : trimmed
        } else {
            phoneticBreakdown = nil
        }

        category = try c.decode(String.self, forKey: .category)
        confidence = try c.decode(Double.self, forKey: .confidence)
        exampleSentences = try c.decode([String].self, forKey: .exampleSentences)
        errorFeedback = try c.decodeIfPresent(String.self, forKey: .errorFeedback)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(objectName, forKey: .objectName)
        try c.encode(targetTranslation, forKey: .targetTranslation)
        try c.encodeIfPresent(phoneticBreakdown, forKey: .phoneticBreakdown)
        try c.encode(category, forKey: .category)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(exampleSentences, forKey: .exampleSentences)
        try c.encodeIfPresent(errorFeedback, forKey: .errorFeedback)
    }
}
