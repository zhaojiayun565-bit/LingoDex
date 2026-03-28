import Foundation
import SwiftData
import UIKit
import Observation

enum CaptureFlowPhase: Equatable {
    case camera
    case processing
    case result
}

/// Drives unified post-capture reveal: edge scan → pixel dissolve → card → chrome.
enum CaptureRevealPhase: Equatable {
    case scanning
    case isolating
    case morphing
    case revealed
}

private enum CaptureRevealTiming {
    static let minEdgeScanMs: UInt64 = 160
    /// Matches StickerResultView pixel dissolve animation + buffer.
    static let pixelIsolateMs: UInt64 = 420
    static let morphingMs: UInt64 = 320
}

@MainActor
@Observable final class CapturesViewModel {
    private let deps: Dependencies
    var sessions: [CaptureSession] = []
    var isProcessingCapture: Bool = false

    // MARK: Pending capture
    var captureFlowPhase: CaptureFlowPhase = .camera
    var captureRevealPhase: CaptureRevealPhase = .scanning
    var pendingWord: WordEntry?
    var pendingExtractedImage: UIImage?
    /// Vision mask raster for razor edge scan (nil if lift failed).
    var pendingMaskImage: UIImage?
    var pendingCapturedImageInfo: CapturedImageInfo?

    // MARK: Story Mode
    var isStorySheetPresented: Bool = false
    var isStoryGenerating: Bool = false
    var storyTriggerWords: [WordEntry] = []
    var generatedStory: Story?

    private let storyMetaLastWordCountKey = "lingodex_last_story_word_count"
    private let storiesKey = "lingodex_saved_stories"

    private var pendingFullImage: UIImage?
    private var pendingNormalizedBBox: String?
    private var pendingLearningLang: String = "english"
    private var pendingNativeLang: String = "english"
    private var hasStartedInitialLoad = false
    private var isLoadingFullCaptureHistory = false
    private var pendingThumbnailBackfillIDs: Set<UUID> = []
    private var thumbnailBackfillTask: Task<Void, Never>?
    private var revealChoreographyTask: Task<Void, Never>?

    init(deps: Dependencies) {
        self.deps = deps
        Task { await loadInitialCaptures() }
    }

    func load() async {
        await loadFullCaptures()
    }

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

    /// Subject lift + recognition; reveal choreography after sticker is ready.
    func processCapturedImage(_ info: CapturedImageInfo) async {
        revealChoreographyTask?.cancel()
        revealChoreographyTask = nil

        pendingCapturedImageInfo = info
        captureRevealPhase = .scanning

        let image = info.image
        let normalizedBBox = info.normalizedBBoxString
        let learningLang = Language.currentLearning.rawValue
        let nativeLang = Self.languageFromSystem().rawValue
        let wordId = UUID()
        let imageFileName = "\(wordId).png"

        let placeholderWord = WordEntry(
            id: wordId,
            imageFileName: imageFileName,
            recognizedEnglish: "Loading…",
            learnWord: "Loading…",
            nativeWord: "Pending",
            createdAt: Date(),
            srs: SRSCardState()
        )

        setCaptureFlowState(
            phase: .processing,
            isProcessing: true,
            word: placeholderWord,
            extractedImage: nil,
            maskImage: nil,
            fullImage: nil,
            normalizedBBox: nil
        )

        defer { isProcessingCapture = false }

        let sticker: UIImage
        let maskUIImage: UIImage?
        let recognitionResult: (learnWord: String, nativeWord: String, recognizedEnglish: String)?

        if deps.networkMonitor.isReachable {
            async let liftOptional: SubjectLiftResult? = try? await deps.subjectLift.extractStickerAndMask(from: image)
            async let recognitionTask = deps.geminiRecognition.recognize(
                image: image,
                boundingBox: normalizedBBox,
                nativeLanguage: nativeLang,
                learningLanguage: learningLang
            )

            let lift = await liftOptional
            sticker = lift?.sticker ?? image
            maskUIImage = lift?.mask

            if let result = try? await recognitionTask {
                recognitionResult = (
                    result.targetTranslation,
                    result.objectName ?? result.targetTranslation,
                    result.targetTranslation
                )
            } else {
                recognitionResult = nil
            }
        } else {
            let lift = try? await deps.subjectLift.extractStickerAndMask(from: image)
            sticker = lift?.sticker ?? image
            maskUIImage = lift?.mask
            recognitionResult = nil
        }

        pendingExtractedImage = sticker
        pendingMaskImage = maskUIImage

        if let r = recognitionResult {
            pendingWord = WordEntry(
                id: wordId,
                imageFileName: imageFileName,
                recognizedEnglish: r.recognizedEnglish,
                learnWord: r.learnWord,
                nativeWord: r.nativeWord,
                createdAt: placeholderWord.createdAt,
                srs: SRSCardState()
            )
            pendingFullImage = nil
            pendingNormalizedBBox = nil
        } else {
            pendingWord = WordEntry(
                id: wordId,
                imageFileName: imageFileName,
                recognizedEnglish: "Loading…",
                learnWord: "Loading…",
                nativeWord: "Pending",
                createdAt: placeholderWord.createdAt,
                srs: SRSCardState()
            )
            pendingFullImage = image
            pendingNormalizedBBox = normalizedBBox
            pendingLearningLang = learningLang
            pendingNativeLang = nativeLang
        }

        revealChoreographyTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(CaptureRevealTiming.minEdgeScanMs))
            guard !Task.isCancelled else { return }
            captureRevealPhase = .isolating

            try? await Task.sleep(for: .milliseconds(CaptureRevealTiming.pixelIsolateMs))
            guard !Task.isCancelled else { return }
            captureRevealPhase = .morphing

            try? await Task.sleep(for: .milliseconds(CaptureRevealTiming.morphingMs))
            guard !Task.isCancelled else { return }
            captureRevealPhase = .revealed
            captureFlowPhase = .result
        }
    }

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
            prepareStoryIfNeeded()
        } catch {
        }

        cancelRevealAndResetFlow()
    }

    func dismissPending() {
        cancelRevealAndResetFlow()
    }

    private func cancelRevealAndResetFlow() {
        revealChoreographyTask?.cancel()
        revealChoreographyTask = nil
        pendingCapturedImageInfo = nil
        captureRevealPhase = .scanning
        setCaptureFlowState(
            phase: .camera,
            isProcessing: false,
            word: nil,
            extractedImage: nil,
            maskImage: nil,
            fullImage: nil,
            normalizedBBox: nil
        )
    }

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
            }
        }
    }

    func deleteWord(_ word: WordEntry) async {
        do {
            try await deps.captureStore.deleteWord(id: word.id)
            await load()
        } catch {
        }
    }

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
        }
    }

    private static func languageFromSystem() -> Language {
        guard let code = Locale.current.languageCode else { return .english }
        switch code.lowercased() {
        case "fr": return .french
        case "es": return .spanish
        case "ja": return .japanese
        case "ko": return .korean
        case "zh": return .mandarinChinese
        case "en": fallthrough
        default: return .english
        }
    }

    private func prepareStoryIfNeeded() {
        let totalWordCount = sessions.reduce(0) { $0 + $1.words.count }
        let lastStoryWordCount = UserDefaults.standard.integer(forKey: storyMetaLastWordCountKey)
        let newWordsSinceLastStory = totalWordCount - lastStoryWordCount

        guard newWordsSinceLastStory >= 5 else { return }

        let recentWords = sessions
            .flatMap { $0.words }
            .sorted(by: { $0.createdAt > $1.createdAt })
            .prefix(5)
            .sorted(by: { $0.createdAt < $1.createdAt })

        storyTriggerWords = Array(recentWords)
        generatedStory = nil
        isStoryGenerating = false
        isStorySheetPresented = true

        UserDefaults.standard.set(totalWordCount, forKey: storyMetaLastWordCountKey)
    }

    private func setCaptureFlowState(
        phase: CaptureFlowPhase,
        isProcessing: Bool,
        word: WordEntry?,
        extractedImage: UIImage?,
        maskImage: UIImage?,
        fullImage: UIImage?,
        normalizedBBox: String?
    ) {
        captureFlowPhase = phase
        isProcessingCapture = isProcessing
        pendingWord = word
        pendingExtractedImage = extractedImage
        pendingMaskImage = maskImage
        pendingFullImage = fullImage
        pendingNormalizedBBox = normalizedBBox
    }

    func createStoryIfNeeded() async {
        guard !isStoryGenerating, generatedStory == nil, !storyTriggerWords.isEmpty else { return }
        isStoryGenerating = true
        generatedStory = nil

        do {
            let story = try await deps.storyGenerator.generateStory(from: storyTriggerWords, language: .english)
            generatedStory = story
        } catch {
        }

        isStoryGenerating = false
    }

    func saveGeneratedStory() {
        guard let story = generatedStory else { return }

        var existing: [Story] = []
        if let data = UserDefaults.standard.data(forKey: storiesKey) {
            existing = (try? JSONDecoder().decode([Story].self, from: data)) ?? []
        }

        if !existing.contains(where: { $0.id == story.id }) {
            existing.append(story)
        }

        if let encoded = try? JSONEncoder().encode(existing) {
            UserDefaults.standard.set(encoded, forKey: storiesKey)
        }
    }
}
