import Foundation
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

    init(deps: Dependencies) {
        self.deps = deps
        Task {
            await load()
        }
    }

    func load() async {
        do {
            sessions = try await deps.localStore.loadSessions()
        } catch {
            sessions = []
        }
    }

    /// Processes captured image: recognition → background removal → translation. Sets pending state for review.
    /// Heavy work runs in Task.detached to avoid blocking the main thread.
    func processCapturedImage(_ image: UIImage) async {
        captureFlowPhase = .processing
        isProcessingCapture = true
        pendingWord = nil
        pendingExtractedImage = nil

        defer {
            isProcessingCapture = false
        }

        let objectRecognition = deps.objectRecognition
        let translation = deps.translation
        let backgroundRemoval = deps.backgroundRemoval
        let nativeLang = Self.languageFromSystem()

        let result: (WordEntry, UIImage)? = await Task.detached(priority: .userInitiated) {
            do {
                let recognized = try await objectRecognition.recognizeObject(from: image)
                let nativeTranslation = (try? await translation.translate(recognized.englishWord, to: nativeLang)) ?? recognized.englishWord

                var extractedImage = image
                if let removed = try? await backgroundRemoval.removeBackground(from: image) {
                    extractedImage = removed
                }

                let wordId = UUID()
                let imageFileName = "\(wordId).png"
                let word = WordEntry(
                    id: wordId,
                    imageFileName: imageFileName,
                    recognizedEnglish: recognized.englishWord,
                    learnWord: recognized.englishWord,
                    nativeWord: nativeTranslation,
                    createdAt: Date(),
                    srs: SRSCardState()
                )
                return (word, extractedImage)
            } catch {
                return nil
            }
        }.value

        if let (word, extractedImage) = result {
            pendingWord = word
            pendingExtractedImage = extractedImage
            captureFlowPhase = .result
        } else {
            captureFlowPhase = .camera
        }
    }

    /// Persists pending word and extracted image, clears pending state.
    func savePendingWord() async {
        guard let word = pendingWord, let image = pendingExtractedImage else { return }

        do {
            try await deps.localStore.saveImagePng(image, fileName: word.imageFileName)

            let now = Date()
            if let existingIndex = sessions.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: now) }) {
                sessions[existingIndex].words.append(word)
            } else {
                sessions.insert(CaptureSession(date: now, words: [word]), at: 0)
            }

            try await deps.localStore.saveSessions(sessions)
            prepareStoryIfNeeded()
        } catch {
            // Fail silently for MVP.
        }

        pendingWord = nil
        pendingExtractedImage = nil
        captureFlowPhase = .camera
    }

    /// Discards pending capture without saving.
    func dismissPending() {
        pendingWord = nil
        pendingExtractedImage = nil
        captureFlowPhase = .camera
    }

    /// Deletes a word from sessions and its image file.
    func deleteWord(_ word: WordEntry) async {
        for i in sessions.indices {
            if let j = sessions[i].words.firstIndex(where: { $0.id == word.id }) {
                sessions[i].words.remove(at: j)
                if sessions[i].words.isEmpty {
                    sessions.remove(at: i)
                }
                try? await deps.localStore.deleteImage(fileName: word.imageFileName)
                try? await deps.localStore.saveSessions(sessions)
                break
            }
        }
    }

    /// Updates a word's learn and native labels.
    func updateWord(_ word: WordEntry, learnWord: String, nativeWord: String) async {
        guard !learnWord.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        for i in sessions.indices {
            if let j = sessions[i].words.firstIndex(where: { $0.id == word.id }) {
                var updated = sessions[i].words[j]
                updated = WordEntry(
                    id: updated.id,
                    imageFileName: updated.imageFileName,
                    recognizedEnglish: updated.recognizedEnglish,
                    learnWord: learnWord.trimmingCharacters(in: .whitespaces),
                    nativeWord: nativeWord.trimmingCharacters(in: .whitespaces),
                    createdAt: updated.createdAt,
                    srs: updated.srs
                )
                sessions[i].words[j] = updated
                try? await deps.localStore.saveSessions(sessions)
                break
            }
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

