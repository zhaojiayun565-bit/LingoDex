import Foundation
import AVFoundation

/// Calls the Supabase minimax-tts Edge Function and plays the returned audio.
actor MinimaxTTSClient: TTSClient {
    private let supabaseURL: URL
    private let anonKey: String
    private let authTokenProvider: @Sendable () -> String?
    private var activePlayer: AVAudioPlayer?
    private var playbackDelegate: AudioCompletionDelegate?

    init(
        supabaseURL: URL,
        anonKey: String,
        authTokenProvider: @escaping @Sendable () -> String?
    ) {
        self.supabaseURL = supabaseURL
        self.anonKey = anonKey
        self.authTokenProvider = authTokenProvider
    }

    /// Requests speech audio for text + language, then plays it through AVAudioPlayer.
    func speak(_ text: String, language: Language) async throws {
        let audioData = try await fetchAudioData(text: text, language: language)
        try await play(audioData)
    }

    private func fetchAudioData(text: String, language: Language) async throws -> Data {
        guard let token = authTokenProvider() else { throw LingoDexServiceError.supabaseNotConfigured }

        var components = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false)
        components?.path = "/functions/v1/minimax-tts"
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = RequestBody(text: text, language: language.rawValue)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw LingoDexServiceError.recognitionFailed
        }
        return data
    }

    private func play(_ audioData: Data) async throws {
        activePlayer?.stop()

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let player = try AVAudioPlayer(data: audioData)
        player.prepareToPlay()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = AudioCompletionDelegate(continuation: continuation)
            player.delegate = delegate
            self.activePlayer = player
            self.playbackDelegate = delegate
            _ = player.play()
        }

        activePlayer = nil
        playbackDelegate = nil
    }
}

private extension MinimaxTTSClient {
    struct RequestBody: Encodable {
        let text: String
        let language: String
    }
}

private final class AudioCompletionDelegate: NSObject, AVAudioPlayerDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        continuation?.resume(returning: ())
        continuation = nil
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        continuation?.resume(throwing: error ?? LingoDexServiceError.recognitionFailed)
        continuation = nil
    }
}
