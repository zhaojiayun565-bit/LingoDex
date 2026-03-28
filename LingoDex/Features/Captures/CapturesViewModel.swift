import Foundation
import SwiftData
import UIKit
import Observation

enum CaptureFlowPhase: Equatable {
    case camera
    case processing
    case result
}

@MainActor
@Observable final class CapturesViewModel {
    private let deps: Dependencies
    var sessions: [CaptureSession] = []
    var isProcessingCapture: Bool = false

    // MARK: Pending capture (two-phase flow)
    var captureFlowPhase: CaptureFlowPhase = .camera
    var pendingWord: WordEntry?
    var pendingExtractedImage: UIImage?

    /// Word card expanded to full detail on Captures (drives tab bar visibility in `MainTabContainer`).
    var selectedWord: WordEntry?

    /// Metadata for pending recognition (offline queue).
    private var pendingFullImage: UIImage?
    private var pendingNormalizedBBox: String?
    private var pendingLearningLang: String = "english"
    private var pendingNativeLang: String = "english"
    private var hasStartedInitialLoad = false
    private var isLoadingFullCaptureHistory = false
    private var pendingThumbnailBackfillIDs: Set<UUID> = []
    private var thumbnailBackfillTask: Task<Void, Never>?

    init(deps: Dependencies) {
        self.deps = deps
        Task { await loadInitialCaptures() }
    }

    func load() async {
        await loadFullCaptures()
    }

    /// Loads the initial, bounded capture history for fast first paint.
    func loadInitialCaptures() async {
        guard !hasStartedInitialLoad else { return }
        hasStartedInitialLoad = true
        do {
            sessions = try await deps.captureStore.loadSessionsAsync(maxCalendarDays: 10)
        } catch {
            sessions = []
        }
        Task { await loadFullCaptures() }
    }

    /// Loads complete capture history in the background and swaps in once ready.
    func loadFullCaptures() async {
        guard !isLoadingFullCaptureHistory else { return }
        isLoadingFullCaptureHistory = true
        defer { isLoadingFullCaptureHistory = false }

        do {
            sessions = try await deps.captureStore.loadSessionsAsync()
        } catch {
            if sessions.isEmpty {
                sessions = []
            }
        }
    }

    /// Processes captured image: subject lift and Gemini run in parallel when online. Shows result when both complete.
    func processCapturedImage(_ info: CapturedImageInfo) async {
        setCaptureFlowState(
            phase: .processing,
            isProcessing: true,
            word: nil,
            extractedImage: nil,
            fullImage: nil,
            normalizedBBox: nil
        )

        defer { isProcessingCapture = false }

        let image = info.image
        let normalizedBBox = info.normalizedBBoxString
        let learningLang = Language.currentLearning.rawValue
        let nativeLang = UserDefaults.standard.string(forKey: "lingodex_native_language") ?? Language.english.rawValue
        let wordId = UUID()
        let imageFileName = "\(wordId).png"

        // Run subject lift and Gemini recognition in parallel when online.
        let sticker: UIImage
        let recognitionResult: GeminiRecognitionResult?

        if deps.networkMonitor.isReachable {
            async let stickerTask = deps.subjectLift.extractSticker(from: image)
            async let recognitionTask = deps.geminiRecognition.recognize(
                image: image,
                boundingBox: normalizedBBox,
                nativeLanguage: nativeLang,
                learningLanguage: learningLang
            )

            let stickerResult = try? await stickerTask
            sticker = stickerResult ?? image

            recognitionResult = try? await recognitionTask
        } else {
            // Offline: sticker only, queue for sync.
            if let s = try? await deps.subjectLift.extractSticker(from: image) {
                sticker = s
            } else {
                sticker = image
            }
            recognitionResult = nil
        }

        // Build word entry: use recognition result or pending state.
        if let r = recognitionResult {
            let nextWord = WordEntry(
                id: wordId,
                imageFileName: imageFileName,
                recognizedEnglish: r.targetTranslation,
                learnWord: r.targetTranslation,
                nativeWord: r.objectName ?? r.targetTranslation,
                phoneticBreakdown: Self.nonEmptyOptionalString(r.phoneticBreakdown),
                createdAt: Date(),
                srs: SRSCardState()
            )
            setCaptureFlowState(
                phase: .result,
                isProcessing: isProcessingCapture,
                word: nextWord,
                extractedImage: sticker,
                fullImage: nil,
                normalizedBBox: nil
            )
        } else {
            let nextWord = WordEntry(
                id: wordId,
                imageFileName: imageFileName,
                recognizedEnglish: "Loading…",
                learnWord: "Loading…",
                nativeWord: "Pending",
                createdAt: Date(),
                srs: SRSCardState()
            )
            setCaptureFlowState(
                phase: .result,
                isProcessing: isProcessingCapture,
                word: nextWord,
                extractedImage: sticker,
                fullImage: image,
                normalizedBBox: normalizedBBox
            )
            pendingLearningLang = learningLang
            pendingNativeLang = nativeLang
        }
    }

    /// Persists pending word and sticker. Uses pending entity when offline (queued for sync).
    func savePendingWord() async {
        guard let word = pendingWord, let sticker = pendingExtractedImage else { return }

        do {
            let isPending = pendingFullImage != nil
            let entity = CapturedWordEntity(
                id: word.id,
                createdAt: word.createdAt,
                imageFileName: word.imageFileName,
                learnWord: word.learnWord,
                nativeWord: word.nativeWord,
                phoneticBreakdown: word.phoneticBreakdown,
                recognizedEnglish: word.recognizedEnglish,
                srsRatingRaw: word.srs.rating.rawValue,
                srsNextDueDate: word.srs.nextDueDate,
                srsLastReviewedAt: word.srs.lastReviewedAt,
                recognitionStatusRaw: isPending ? RecognitionStatus.pending.rawValue : RecognitionStatus.ready.rawValue,
                learningLanguageRaw: pendingLearningLang,
                nativeLanguageRaw: pendingNativeLang,
                sourceImageFileName: isPending ? "\(word.id)_capture.jpg" : nil,
                normalizedBBox: isPending ? pendingNormalizedBBox : nil
            )

            if isPending, let fullImage = pendingFullImage {
                try await deps.captureStore.insertPendingWord(entity, stickerImage: sticker, fullCaptureForRetry: fullImage)
            } else {
                try await deps.captureStore.insertWord(entity, stickerImage: sticker)
            }
            await load()
        } catch {
            // Fail silently for MVP.
        }

        setCaptureFlowState(
            phase: .camera,
            isProcessing: false,
            word: nil,
            extractedImage: nil,
            fullImage: nil,
            normalizedBBox: nil
        )
    }

    /// Discards pending capture without saving.
    func dismissPending() {
        setCaptureFlowState(
            phase: .camera,
            isProcessing: false,
            word: nil,
            extractedImage: nil,
            fullImage: nil,
            normalizedBBox: nil
        )
    }

    /// Schedules lazy thumbnail backfill for words missing SwiftData thumbnail blobs.
    func scheduleThumbnailBackfill(for ids: [UUID]) {
        let missing = Set(ids)
        guard !missing.isEmpty else { return }
        pendingThumbnailBackfillIDs.formUnion(missing)
        guard thumbnailBackfillTask == nil else { return }

        thumbnailBackfillTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self else { return }
            let batch = Array(self.pendingThumbnailBackfillIDs)
            self.pendingThumbnailBackfillIDs.removeAll()
            self.thumbnailBackfillTask = nil

            do {
                let changed = try await deps.captureStore.backfillMissingThumbnails(for: batch)
                if changed {
                    await loadFullCaptures()
                }
            } catch {
                // Ignore backfill failures; placeholders remain.
            }
        }
    }

    /// Deletes a word from sessions and its image file.
    func deleteWord(_ word: WordEntry) async {
        do {
            try await deps.captureStore.deleteWord(id: word.id)
            await load()
        } catch {
            // Fail silently for MVP.
        }
    }

    /// Updates a word's learn and native labels.
    func updateWord(_ word: WordEntry, learnWord: String, nativeWord: String) async {
        guard !learnWord.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            try deps.captureStore.updateWord(
                id: word.id,
                learnWord: learnWord.trimmingCharacters(in: .whitespaces),
                nativeWord: nativeWord.trimmingCharacters(in: .whitespaces)
            )
            await load()
        } catch {
            // Fail silently for MVP.
        }
    }

    private static func nonEmptyOptionalString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func setCaptureFlowState(
        phase: CaptureFlowPhase,
        isProcessing: Bool,
        word: WordEntry?,
        extractedImage: UIImage?,
        fullImage: UIImage?,
        normalizedBBox: String?
    ) {
        captureFlowPhase = phase
        isProcessingCapture = isProcessing
        pendingWord = word
        pendingExtractedImage = extractedImage
        pendingFullImage = fullImage
        pendingNormalizedBBox = normalizedBBox
    }
}

