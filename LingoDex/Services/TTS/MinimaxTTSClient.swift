import Foundation
import AVFoundation

private var minimaxPlaybackDelegateKey: UInt8 = 0

/// Calls the Supabase minimax-tts Edge Function and plays the returned audio.
struct MinimaxTTSClient: TTSClient {
    private let supabaseURL: URL
    private let anonKey: String
    private let authTokenProvider: @Sendable () -> String?

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
        guard let token = authTokenProvider() else {
            throw LingoDexServiceError.supabaseNotConfigured
        }

        var components = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false)
        components?.path = "/functions/v1/minimax-tts"
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(text: text, language: language.rawValue))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw LingoDexServiceError.recognitionFailed
        }

        let payload = try JSONDecoder().decode(EdgeResponse.self, from: data)
        guard let audioData = Data(base64Encoded: payload.audioBase64) else {
            throw LingoDexServiceError.recognitionFailed
        }
        try await playAudio(audioData)
    }

    private func playAudio(_ audioData: Data) async throws {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? AVAudioSession.sharedInstance().setActive(true)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let player = try AVAudioPlayer(data: audioData)
                player.prepareToPlay()
                let delegate = MinimaxPlaybackDelegate(continuation: continuation, player: player)
                player.delegate = delegate
                objc_setAssociatedObject(player, &minimaxPlaybackDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                _ = player.play()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private extension MinimaxTTSClient {
    struct RequestBody: Encodable {
        let text: String
        let language: String
    }

    struct EdgeResponse: Decodable {
        let audioBase64: String

        enum CodingKeys: String, CodingKey {
            case audioBase64 = "audio_base64"
        }
    }
}

private final class MinimaxPlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    private let continuation: CheckedContinuation<Void, Error>
    private var player: AVAudioPlayer?
    private var hasResumed = false

    init(continuation: CheckedContinuation<Void, Error>, player: AVAudioPlayer) {
        self.continuation = continuation
        self.player = player
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard !hasResumed else { return }
        hasResumed = true
        self.player = nil
        objc_setAssociatedObject(player, &minimaxPlaybackDelegateKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        continuation.resume(returning: ())
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard !hasResumed else { return }
        hasResumed = true
        self.player = nil
        objc_setAssociatedObject(player, &minimaxPlaybackDelegateKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        continuation.resume(throwing: error ?? LingoDexServiceError.recognitionFailed)
    }
}
