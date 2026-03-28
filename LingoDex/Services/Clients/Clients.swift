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

struct AuthUser: Sendable, Equatable, Identifiable {
    let id: String
    var displayName: String
}

protocol AuthClient: Sendable {
    var currentUser: AuthUser? { get }
    /// Access token for Supabase Edge Function auth; nil if not signed in.
    var accessToken: String? { get }
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

private var _ttsDelegateKey: UInt8 = 0

struct AppleTTSClient: TTSClient {
    func speak(_ text: String, language: Language) async throws {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.localeTag)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        return try await withCheckedThrowingContinuation { continuation in
            let synthesizer = AVSpeechSynthesizer()

            final class Delegate: NSObject, AVSpeechSynthesizerDelegate {
                let continuation: CheckedContinuation<Void, Error>
                var synthesizer: AVSpeechSynthesizer?
                var isResolved = false

                init(continuation: CheckedContinuation<Void, Error>, synthesizer: AVSpeechSynthesizer) {
                    self.continuation = continuation
                    self.synthesizer = synthesizer
                }

                func speechSynthesizer(_ synth: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
                    guard !isResolved else { return }
                    isResolved = true
                    synthesizer = nil
                    objc_setAssociatedObject(synth, &_ttsDelegateKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                    continuation.resume(returning: ())
                }

                func speechSynthesizer(_ synth: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
                    guard !isResolved else { return }
                    isResolved = true
                    synthesizer = nil
                    objc_setAssociatedObject(synth, &_ttsDelegateKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                    continuation.resume(throwing: LingoDexServiceError.recognitionFailed)
                }
            }

            let delegate = Delegate(continuation: continuation, synthesizer: synthesizer)
            synthesizer.delegate = delegate
            objc_setAssociatedObject(synthesizer, &_ttsDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
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

@Observable final class LocalAuthClient: AuthClient {
    private(set) var currentUser: AuthUser? = nil
    var accessToken: String? { nil }

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

