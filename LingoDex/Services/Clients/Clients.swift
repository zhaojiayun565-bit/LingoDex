import Foundation
import UIKit
import AVFoundation

import Observation

protocol ObjectRecognitionClient: Sendable {
    func recognizeObject(from image: UIImage) async throws -> RecognizedObject
}

protocol TranslationClient: Sendable {
    func translate(_ text: String, to language: Language) async throws -> String
}

protocol TTSClient: Sendable {
    func speak(_ text: String, language: Language) async throws
}

protocol SpeechVerificationClient: Sendable {
    func verifyPronunciation(expectedText: String, language: Language) async throws -> PronunciationResult
}

protocol StoryGeneratorClient: Sendable {
    func generateStory(from words: [WordEntry], language: Language) async throws -> Story
}

struct AuthUser: Sendable, Equatable, Identifiable {
    let id: String
    var displayName: String
}

protocol AuthClient: Sendable {
    var currentUser: AuthUser? { get }
    func signInWithAppleIdToken(_ idToken: String, nonce: String?, fullName: String?) async throws -> AuthUser
    func signOut() async throws
}

// MARK: - Live Stubs (MVP-safe)

struct MockObjectRecognitionClient: ObjectRecognitionClient {
    func recognizeObject(from image: UIImage) async throws -> RecognizedObject {
        // Placeholder word list until Vision object recognition is implemented.
        let candidates = ["Donut", "Banana", "Clock", "Bicycle", "Toast", "Watch"]
        return RecognizedObject(englishWord: candidates.randomElement() ?? "Donut")
    }
}

struct MockTranslationClient: TranslationClient {
    func translate(_ text: String, to language: Language) async throws -> String {
        // Placeholder translation until Apple Translation integration is wired.
        if language == .english { return text }
        return "\(text) (\(language.displayName))"
    }
}

struct AppleTTSClient: TTSClient {
    func speak(_ text: String, language: Language) async throws {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.localeTag)
        utterance.rate = 0.95

        return try await withCheckedThrowingContinuation { continuation in
            let synthesizer = AVSpeechSynthesizer()

            final class Delegate: NSObject, AVSpeechSynthesizerDelegate {
                let continuation: CheckedContinuation<Void, Error>
                var isResolved = false

                init(continuation: CheckedContinuation<Void, Error>) {
                    self.continuation = continuation
                }

                func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
                    guard !isResolved else { return }
                    isResolved = true
                    continuation.resume(returning: ())
                }

                func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
                    guard !isResolved else { return }
                    isResolved = true
                    continuation.resume(throwing: LingoDexServiceError.recognitionFailed)
                }
            }

            let delegate = Delegate(continuation: continuation)
            synthesizer.delegate = delegate
            synthesizer.speak(utterance)
        }
    }
}

struct MockSpeechVerificationClient: SpeechVerificationClient {
    func verifyPronunciation(expectedText: String, language: Language) async throws -> PronunciationResult {
        let transcript = expectedText
        return PronunciationResult(isCorrect: true, transcript: transcript, accuracy: 1.0)
    }
}

struct LocalStoryGeneratorClient: StoryGeneratorClient {
    func generateStory(from words: [WordEntry], language: Language) async throws -> Story {
        let wordTexts = words.prefix(5).map { $0.learnWord }
        let joined = wordTexts.joined(separator: ", ")
        let body = "Yesterday I saw \(joined) and decided to learn them by speaking the words out loud."
        return Story(title: "My Quick Adventure", body: body, createdAt: Date(), associatedWordIds: words.map(\.id))
    }
}

@Observable final class LocalAuthClient: AuthClient {
    private(set) var currentUser: AuthUser? = nil

    func signInWithAppleIdToken(_ idToken: String, nonce: String?, fullName: String?) async throws -> AuthUser {
        let display = fullName?.isEmpty == false ? (fullName ?? "") : "Learner"
        let user = AuthUser(id: UUID().uuidString, displayName: display)
        self.currentUser = user
        return user
    }

    func signOut() async throws {
        self.currentUser = nil
    }
}

