import Foundation
import SwiftData
import UIKit
import ImageIO

/// SwiftData-backed persistence for captures. Replaces JSON sessions.
final class SwiftDataCaptureStore {
    private let modelContext: ModelContext
    private let modelContainer: ModelContainer
    private let imageStore: LocalLingoDexStore
    private let defaultThumbnailPixelSize = 320

    init(modelContext: ModelContext, modelContainer: ModelContainer, imageStore: LocalLingoDexStore) {
        self.modelContext = modelContext
        self.modelContainer = modelContainer
        self.imageStore = imageStore
    }

    /// Loads all words and groups by calendar day (main `ModelContext`; prefer `loadSessionsAsync` from UI).
    func loadSessions() throws -> [CaptureSession] {
        try Self.mapSessions(from: modelContext)
    }

    /// Fetches and maps on a background `ModelContext` so large collections do not block the main actor.
    func loadSessionsAsync(maxCalendarDays: Int? = nil) async throws -> [CaptureSession] {
        let container = modelContainer
        return try await Task.detached {
            let context = ModelContext(container)
            if let maxCalendarDays, maxCalendarDays > 0 {
                return try Self.mapSessions(from: context, maxCalendarDays: maxCalendarDays)
            }
            return try Self.mapSessions(from: context)
        }.value
    }

    /// Maps fetched entities into value-type sessions (caller’s context thread).
    private static func mapSessions(from context: ModelContext) throws -> [CaptureSession] {
        let descriptor = FetchDescriptor<CapturedWordEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let entities = try context.fetch(descriptor)
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

    /// Maps only the newest N calendar-day sessions using paged fetches on descending creation date.
    private static func mapSessions(from context: ModelContext, maxCalendarDays: Int) throws -> [CaptureSession] {
        let calendar = Calendar.current
        let fetchLimit = 200
        var cursorDate: Date?
        var dayOrder: [Date] = []
        var grouped: [Date: [WordEntry]] = [:]

        while dayOrder.count < maxCalendarDays {
            var descriptor: FetchDescriptor<CapturedWordEntity>
            if let cursorDate {
                descriptor = FetchDescriptor<CapturedWordEntity>(
                    predicate: #Predicate<CapturedWordEntity> { $0.createdAt < cursorDate },
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                )
            } else {
                descriptor = FetchDescriptor<CapturedWordEntity>(
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                )
            }
            descriptor.fetchLimit = fetchLimit

            let entities = try context.fetch(descriptor)
            guard !entities.isEmpty else { break }

            for entity in entities {
                let word = entity.toWordEntry()
                let day = calendar.startOfDay(for: word.createdAt)
                if grouped[day] == nil {
                    guard dayOrder.count < maxCalendarDays else {
                        return dayOrder.compactMap { date in
                            guard let words = grouped[date] else { return nil }
                            return CaptureSession(id: UUID(), date: date, words: words)
                        }
                    }
                    dayOrder.append(day)
                    grouped[day] = []
                }
                grouped[day]?.append(word)
            }

            cursorDate = entities.last?.createdAt
        }

        return dayOrder.compactMap { date in
            guard let words = grouped[date] else { return nil }
            return CaptureSession(id: UUID(), date: date, words: words)
        }
    }

    /// Inserts a new word entity and saves the sticker image.
    func insertWord(_ entity: CapturedWordEntity, stickerImage: UIImage) async throws {
        entity.thumbnailData = Self.thumbnailData(from: stickerImage, maxPixelSize: defaultThumbnailPixelSize)
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
        entity.thumbnailData = Self.thumbnailData(from: stickerImage, maxPixelSize: defaultThumbnailPixelSize)
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
        phoneticBreakdown: String?,
        category: String?,
        exampleSentencesJSON: Data?,
        confidence: Double,
        errorFeedback: String?
    ) throws {
        guard let entity = fetchEntity(by: id) else { return }
        entity.learnWord = learnWord
        entity.nativeWord = nativeWord
        entity.phoneticBreakdown = phoneticBreakdown
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

    /// Backfills missing thumbnail blobs for a set of word IDs.
    func backfillMissingThumbnails(for ids: [UUID], maxPixelSize: Int = 320) async throws -> Bool {
        let uniqueIDs = Array(Set(ids))
        guard !uniqueIDs.isEmpty else { return false }

        let container = modelContainer
        return try await Task.detached {
            let context = ModelContext(container)
            let imagesDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent("lingodex_images", isDirectory: true)
            var changed = false

            for id in uniqueIDs {
                var descriptor = FetchDescriptor<CapturedWordEntity>(
                    predicate: #Predicate<CapturedWordEntity> { $0.id == id }
                )
                descriptor.fetchLimit = 1
                guard let entity = try context.fetch(descriptor).first else { continue }
                guard entity.thumbnailData == nil else { continue }

                let fileURL = imagesDirectoryURL.appendingPathComponent(entity.imageFileName)
                guard let data = Self.thumbnailData(fromImageAt: fileURL, maxPixelSize: maxPixelSize) else { continue }
                entity.thumbnailData = data
                changed = true
            }

            if changed {
                try context.save()
            }
            return changed
        }.value
    }

    private static func thumbnailData(from image: UIImage, maxPixelSize: Int) -> Data? {
        guard let sourceCGImage = image.cgImage else { return image.pngData() }
        let width = sourceCGImage.width
        let height = sourceCGImage.height
        let maxDimension = max(width, height)
        let scale = min(1.0, CGFloat(maxPixelSize) / CGFloat(maxDimension))
        let targetSize = CGSize(
            width: max(1, CGFloat(width) * scale),
            height: max(1, CGFloat(height) * scale)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.pngData()
    }

    private static func thumbnailData(fromImageAt url: URL, maxPixelSize: Int) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage).pngData()
    }
}
