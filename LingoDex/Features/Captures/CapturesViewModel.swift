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

    // MARK: Story Mode
    var isStorySheetPresented: Bool = false
    var isStoryGenerating: Bool = false
    var storyTriggerWords: [WordEntry] = []
    var generatedStory: Story?

    private let storyMetaLastWordCountKey = "lingodex_last_story_word_count"
    private let storiesKey = "lingodex_saved_stories"

    /// Metadata for pending recognition (offline queue).
    private var pendingFullImage: UIImage?
    private var pendingNormalizedBBox: String?
    private var pendingLearningLang: String = "english"
    private var pendingNativeLang: String = "english"

    init(deps: Dependencies) {
        self.deps = deps
        SwiftDataMigration.runIfNeeded(modelContext: deps.modelContext)
        Task {
            await load()
            await deps.recognitionSync.syncIfNeeded()
        }
    }

    func load() async {
        do {
            sessions = try deps.captureStore.loadSessions()
        } catch {
            sessions = []
        }
    }

    /// Processes captured image: subject lift → Gemini recognition (or queue if offline). Shows result immediately.
    func processCapturedImage(_ info: CapturedImageInfo) async {
        captureFlowPhase = .processing
        isProcessingCapture = true
        pendingWord = nil
        pendingExtractedImage = nil
        pendingFullImage = nil
        pendingNormalizedBBox = nil

        defer { isProcessingCapture = false }

        let image = info.image
        let normalizedBBox = info.normalizedBBoxString
        let learningLang = Language.currentLearning.rawValue
        let nativeLang = Self.languageFromSystem().rawValue

        // 1. Subject lift (sticker) — always
        let sticker: UIImage
        if let s = try? await deps.subjectLift.extractSticker(from: image) {
            sticker = s
        } else {
            sticker = image
        }

        let wordId = UUID()
        let imageFileName = "\(wordId).png"

        // 2. Recognition: Gemini if online, else queue
        if deps.networkMonitor.isReachable {
            do {
                let result = try await deps.geminiRecognition.recognize(
                    image: image,
                    boundingBox: normalizedBBox,
                    nativeLanguage: nativeLang,
                    learningLanguage: learningLang
                )
                let learnWord = result.targetTranslation
                let nativeWord = result.objectName ?? result.targetTranslation
                let word = WordEntry(
                    id: wordId,
                    imageFileName: imageFileName,
                    recognizedEnglish: result.targetTranslation,
                    learnWord: learnWord,
                    nativeWord: nativeWord,
                    createdAt: Date(),
                    srs: SRSCardState()
                )
                pendingWord = word
                pendingExtractedImage = sticker
                pendingFullImage = nil
            } catch {
                // Fallback: show pending so user can retry or save for sync.
                let word = WordEntry(
                    id: wordId,
                    imageFileName: imageFileName,
                    recognizedEnglish: "Loading…",
                    learnWord: "Loading…",
                    nativeWord: "Pending",
                    createdAt: Date(),
                    srs: SRSCardState()
                )
                pendingWord = word
                pendingExtractedImage = sticker
                pendingFullImage = image
                pendingNormalizedBBox = normalizedBBox
                pendingLearningLang = learningLang
                pendingNativeLang = nativeLang
            }
        } else {
            let word = WordEntry(
                id: wordId,
                imageFileName: imageFileName,
                recognizedEnglish: "Loading…",
                learnWord: "Loading…",
                nativeWord: "Pending",
                createdAt: Date(),
                srs: SRSCardState()
            )
            pendingWord = word
            pendingExtractedImage = sticker
            pendingFullImage = image
            pendingNormalizedBBox = normalizedBBox
            pendingLearningLang = learningLang
            pendingNativeLang = nativeLang
        }

        captureFlowPhase = .result
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
            // Fail silently for MVP.
        }

        pendingWord = nil
        pendingExtractedImage = nil
        pendingFullImage = nil
        pendingNormalizedBBox = nil
        captureFlowPhase = .camera
    }

    /// Discards pending capture without saving.
    func dismissPending() {
        pendingWord = nil
        pendingExtractedImage = nil
        pendingFullImage = nil
        pendingNormalizedBBox = nil
        captureFlowPhase = .camera
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

        // Mark progress immediately to avoid re-triggering while the sheet is open.
        UserDefaults.standard.set(totalWordCount, forKey: storyMetaLastWordCountKey)
    }

    func createStoryIfNeeded() async {
        guard !isStoryGenerating, generatedStory == nil, !storyTriggerWords.isEmpty else { return }
        isStoryGenerating = true
        generatedStory = nil

        do {
            let story = try await deps.storyGenerator.generateStory(from: storyTriggerWords, language: .english)
            generatedStory = story
        } catch {
            // For MVP, keep UI stable.
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

