import Foundation
import SwiftData
import UIKit

/// SwiftData-backed persistence for captures. Replaces JSON sessions.
final class SwiftDataCaptureStore {
    private let modelContext: ModelContext
    private let imageStore: LocalLingoDexStore

    init(modelContext: ModelContext, imageStore: LocalLingoDexStore) {
        self.modelContext = modelContext
        self.imageStore = imageStore
    }

    /// Loads all words and groups by calendar day.
    func loadSessions() throws -> [CaptureSession] {
        let descriptor = FetchDescriptor<CapturedWordEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let entities = try modelContext.fetch(descriptor)
        let words = entities.map { $0.toWordEntry() }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: words) { word in
            calendar.startOfDay(for: word.createdAt)
        }
        return grouped.map { date, dayWords in
            CaptureSession(
                id: UUID(),
                date: date,
                words: dayWords.sorted { $0.createdAt > $1.createdAt }
            )
        }.sorted { $0.date > $1.date }
    }

    /// Inserts a new word entity and saves the sticker image.
    func insertWord(_ entity: CapturedWordEntity, stickerImage: UIImage) async throws {
        modelContext.insert(entity)
        try modelContext.save()
        try await imageStore.saveImagePng(stickerImage, fileName: entity.imageFileName)
    }

    /// Inserts a pending word (sticker + optional full capture for retry).
    func insertPendingWord(
        _ entity: CapturedWordEntity,
        stickerImage: UIImage,
        fullCaptureForRetry: UIImage?
    ) async throws {
        modelContext.insert(entity)
        try modelContext.save()
        try await imageStore.saveImagePng(stickerImage, fileName: entity.imageFileName)
        if let full = fullCaptureForRetry, let sourceName = entity.sourceImageFileName {
            try await imageStore.savePendingCapture(full, fileName: sourceName)
        }
    }

    /// Fetches all pending recognition jobs.
    func fetchPendingRecognitionJobs() throws -> [CapturedWordEntity] {
        var descriptor = FetchDescriptor<CapturedWordEntity>(
            predicate: #Predicate<CapturedWordEntity> { $0.recognitionStatusRaw == "pending" },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 10
        return try modelContext.fetch(descriptor)
    }

    /// Updates entity with recognition result.
    func updateWithRecognitionResult(
        id: UUID,
        learnWord: String,
        nativeWord: String,
        recognizedEnglish: String,
        category: String?,
        exampleSentencesJSON: Data?,
        confidence: Double,
        errorFeedback: String?
    ) throws {
        guard let entity = fetchEntity(by: id) else { return }
        entity.learnWord = learnWord
        entity.nativeWord = nativeWord
        entity.recognizedEnglish = recognizedEnglish
        entity.recognitionStatusRaw = RecognitionStatus.ready.rawValue
        entity.category = category
        entity.exampleSentencesJSON = exampleSentencesJSON
        entity.confidence = confidence
        entity.errorFeedback = errorFeedback
        entity.sourceImageFileName = nil
        entity.normalizedBBox = nil
        try modelContext.save()
    }

    /// Deletes a pending capture file (after successful sync).
    func deletePendingCapture(fileName: String) async throws {
        try await imageStore.deletePendingCapture(fileName: fileName)
    }

    /// Updates learn/native labels for a word.
    func updateWord(id: UUID, learnWord: String, nativeWord: String) throws {
        guard let entity = fetchEntity(by: id) else { return }
        entity.learnWord = learnWord
        entity.nativeWord = nativeWord
        try modelContext.save()
    }

    /// Updates SRS state for a word.
    func updateWordSRS(id: UUID, srs: SRSCardState) throws {
        guard let entity = fetchEntity(by: id) else { return }
        entity.srs = srs
        try modelContext.save()
    }

    /// Deletes a word entity and its image file.
    func deleteWord(id: UUID) async throws {
        guard let entity = fetchEntity(by: id) else { return }
        modelContext.delete(entity)
        try modelContext.save()
        try await imageStore.deleteImage(fileName: entity.imageFileName)
    }

    /// Fetches entity by ID (for recognition sync to update).
    func fetchEntity(by id: UUID) -> CapturedWordEntity? {
        var descriptor = FetchDescriptor<CapturedWordEntity>(
            predicate: #Predicate<CapturedWordEntity> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Saves a pending word's sticker; entity already inserted. Used when creating pending then saving.
    func saveStickerImage(_ image: UIImage, fileName: String) async throws {
        try await imageStore.saveImagePng(image, fileName: fileName)
    }
}
