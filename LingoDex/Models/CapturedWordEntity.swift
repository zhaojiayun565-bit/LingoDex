import Foundation
import SwiftData

/// SwiftData model for captured words. Replaces JSON-backed WordEntry persistence.
@Model
final class CapturedWordEntity {
    var id: UUID
    var createdAt: Date
    var imageFileName: String
    var learnWord: String
    var nativeWord: String
    var recognizedEnglish: String
    var srsRatingRaw: String
    var srsNextDueDate: Date?
    var srsLastReviewedAt: Date?

    /// Pending = awaiting Gemini; Ready = has terms; Failed = recognition failed.
    var recognitionStatusRaw: String
    var category: String?
    var exampleSentencesJSON: Data?
    var confidence: Double
    var errorFeedback: String?
    var learningLanguageRaw: String
    var nativeLanguageRaw: String

    /// For pending retry: full capture JPEG path, normalized bbox.
    var sourceImageFileName: String?
    var normalizedBBox: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        imageFileName: String,
        learnWord: String,
        nativeWord: String,
        recognizedEnglish: String,
        srsRatingRaw: String = SRSRating.good.rawValue,
        srsNextDueDate: Date? = nil,
        srsLastReviewedAt: Date? = nil,
        recognitionStatusRaw: String = RecognitionStatus.ready.rawValue,
        category: String? = nil,
        exampleSentencesJSON: Data? = nil,
        confidence: Double = 1.0,
        errorFeedback: String? = nil,
        learningLanguageRaw: String = "english",
        nativeLanguageRaw: String = "english",
        sourceImageFileName: String? = nil,
        normalizedBBox: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.imageFileName = imageFileName
        self.learnWord = learnWord
        self.nativeWord = nativeWord
        self.recognizedEnglish = recognizedEnglish
        self.srsRatingRaw = srsRatingRaw
        self.srsNextDueDate = srsNextDueDate
        self.srsLastReviewedAt = srsLastReviewedAt
        self.recognitionStatusRaw = recognitionStatusRaw
        self.category = category
        self.exampleSentencesJSON = exampleSentencesJSON
        self.confidence = confidence
        self.errorFeedback = errorFeedback
        self.learningLanguageRaw = learningLanguageRaw
        self.nativeLanguageRaw = nativeLanguageRaw
        self.sourceImageFileName = sourceImageFileName
        self.normalizedBBox = normalizedBBox
    }

    var recognitionStatus: RecognitionStatus {
        get { RecognitionStatus(rawValue: recognitionStatusRaw) ?? .ready }
        set { recognitionStatusRaw = newValue.rawValue }
    }

    var srs: SRSCardState {
        get {
            SRSCardState(
                rating: SRSRating(rawValue: srsRatingRaw) ?? .good,
                nextDueDate: srsNextDueDate,
                lastReviewedAt: srsLastReviewedAt
            )
        }
        set {
            srsRatingRaw = newValue.rating.rawValue
            srsNextDueDate = newValue.nextDueDate
            srsLastReviewedAt = newValue.lastReviewedAt
        }
    }

    /// Converts to WordEntry for views and clients that expect the struct.
    func toWordEntry() -> WordEntry {
        WordEntry(
            id: id,
            imageFileName: imageFileName,
            recognizedEnglish: recognizedEnglish,
            learnWord: learnWord,
            nativeWord: nativeWord,
            createdAt: createdAt,
            srs: srs
        )
    }
}

enum RecognitionStatus: String, CaseIterable {
    case pending
    case ready
    case failed
}
