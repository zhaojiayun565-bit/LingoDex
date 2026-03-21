import Foundation
import AVFoundation
import FluidAudio

/// TTS client using Kokoro-82M CoreML for supported languages, with AVSpeech fallback for Korean.
struct KokoroTTSClient: TTSClient {
    private let avSpeechFallback: AppleTTSClient
    private let kokoroActor = KokoroActor()

    init(avSpeechFallback: AppleTTSClient = AppleTTSClient()) {
        self.avSpeechFallback = avSpeechFallback
    }

    func speak(_ text: String, language: Language) async throws {
        #if os(iOS)
        // Kokoro-82M uses ~1.5 GB peak RAM; causes OOM on typical iPhones (4–6 GB). Use AVSpeech on iOS.
        try await avSpeechFallback.speak(text, language: language)
        return
        #else
        guard KokoroTTSClient.kokoroSupports(language) else {
            try await avSpeechFallback.speak(text, language: language)
            return
        }
        do {
            try await kokoroActor.speak(text: text, voice: Self.voiceForLanguage(language))
        } catch {
            try await avSpeechFallback.speak(text, language: language)
        }
        #endif
    }

    private static func kokoroSupports(_ language: Language) -> Bool {
        switch language {
        case .english, .french, .spanish, .japanese, .mandarinChinese: return true
        case .korean: return false
        }
    }

    private static func voiceForLanguage(_ language: Language) -> String {
        switch language {
        case .english: return TtsConstants.recommendedVoice
        case .french: return "ff_siwis"
        case .spanish: return "ef_dora"
        case .japanese: return "jf_alpha"
        case .mandarinChinese: return "zf_xiaobei"
        case .korean: return TtsConstants.recommendedVoice
        }
    }
}

/// Actor that serializes Kokoro synthesis and playback to avoid concurrent access.
private actor KokoroActor {
    private var manager: KokoroTtsManager?
    private var isInitializing = false

    func speak(text: String, voice: String) async throws {
        let mgr = try await getOrCreateManager(voice: voice)
        let detailed = try await mgr.synthesizeDetailed(
            text: text,
            voice: voice,
            variantPreference: .fifteenSecond,
            deEss: true
        )
        try await playWAV(detailed.audio)
    }

    private func getOrCreateManager(voice: String) async throws -> KokoroTtsManager {
        if let mgr = manager { return mgr }
        if isInitializing {
            while manager == nil {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            return manager!
        }
        isInitializing = true
        defer { isInitializing = false }
        let mgr = KokoroTtsManager(customLexicon: nil)
        try await mgr.initialize(preloadVoices: [voice])
        manager = mgr
        return mgr
    }

    private func playWAV(_ wavData: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let player = try AVAudioPlayer(data: wavData)
                player.prepareToPlay()
                let delegate = PlaybackDelegate(continuation: continuation, player: player)
                player.delegate = delegate
                player.play()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    private let continuation: CheckedContinuation<Void, Error>
    private var player: AVAudioPlayer?

    init(continuation: CheckedContinuation<Void, Error>, player: AVAudioPlayer) {
        self.continuation = continuation
        self.player = player
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
        continuation.resume(returning: ())
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        self.player = nil
        continuation.resume(throwing: error ?? LingoDexServiceError.recognitionFailed)
    }
}
