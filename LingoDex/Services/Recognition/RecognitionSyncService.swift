import Foundation
import UIKit

/// When online, processes pending recognition jobs and updates SwiftData.
@MainActor
final class RecognitionSyncService {
    private let captureStore: SwiftDataCaptureStore
    private let imageStore: LocalLingoDexStore
    private let geminiClient: GeminiRecognitionClient
    private let networkMonitor: NetworkMonitor

    private var isSyncing = false

    init(
        captureStore: SwiftDataCaptureStore,
        imageStore: LocalLingoDexStore,
        geminiClient: GeminiRecognitionClient,
        networkMonitor: NetworkMonitor
    ) {
        self.captureStore = captureStore
        self.imageStore = imageStore
        self.geminiClient = geminiClient
        self.networkMonitor = networkMonitor

        networkMonitor.onReachabilityChanged = { [weak self] reachable in
            if reachable {
                Task { @MainActor in await self?.syncIfNeeded() }
            }
        }
    }

    /// Call on app launch and when returning to foreground.
    func syncIfNeeded() async {
        guard networkMonitor.isReachable, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let jobs = try captureStore.fetchPendingRecognitionJobs()
            for entity in jobs {
                await processJob(entity)
            }
        } catch {
            // Fail silently; will retry on next connectivity change.
        }
    }

    private func processJob(_ entity: CapturedWordEntity) async {
        guard let sourceFileName = entity.sourceImageFileName,
              let bbox = entity.normalizedBBox,
              let fullImage = try? await imageStore.loadPendingCapture(fileName: sourceFileName)
        else { return }

        do {
            let result = try await geminiClient.recognize(
                image: fullImage,
                boundingBox: bbox,
                nativeLanguage: entity.nativeLanguageRaw,
                learningLanguage: entity.learningLanguageRaw
            )

            let learnWord = result.targetTranslation
            let nativeWord = result.objectName ?? result.targetTranslation
            let recognizedEnglish = result.targetTranslation

            let phonetic: String? = {
                guard let p = result.phoneticBreakdown?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty else {
                    return nil
                }
                return p
            }()

            try captureStore.updateWithRecognitionResult(
                id: entity.id,
                learnWord: learnWord,
                nativeWord: nativeWord,
                recognizedEnglish: recognizedEnglish,
                phoneticBreakdown: phonetic,
                category: result.category.isEmpty ? nil : result.category,
                exampleSentencesJSON: try? JSONEncoder().encode(result.exampleSentences),
                confidence: result.confidence,
                errorFeedback: result.errorFeedback
            )

            try await captureStore.deletePendingCapture(fileName: sourceFileName)
        } catch {
            // Keep pending for next sync.
        }
    }
}
