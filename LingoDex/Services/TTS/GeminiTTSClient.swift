import Foundation
import AVFoundation

/// TTS via Supabase `gemini-tts` Edge Function (Gemini audio); expects WAV or MP3 bytes from the server.
actor GeminiTTSClient: TTSClient {
    private let supabaseURL: URL
    private let anonKey: String
    private let authTokenProvider: @Sendable () -> String?

    private var activePlayer: AVAudioPlayer?
    private var activeDelegate: TTSPlaybackDelegate?

    init(supabaseURL: URL, anonKey: String, authTokenProvider: @escaping @Sendable () -> String?) {
        self.supabaseURL = supabaseURL
        self.anonKey = anonKey
        self.authTokenProvider = authTokenProvider
    }

    func speak(_ text: String, language: Language) async throws {
        guard let token = authTokenProvider() else { throw LingoDexServiceError.supabaseNotConfigured }

        var request = URLRequest(url: supabaseURL.appendingPathComponent("/functions/v1/gemini-tts"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["text": text, "language": language.rawValue])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown server error"
            print("🚨 Supabase Error: \(errorMsg)")
            throw LingoDexServiceError.ttsFailed
        }

        let mime = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        try await play(audioData: data, contentType: mime)
    }

    private func play(audioData: Data, contentType: String) async throws {
        let ext: String
        if contentType.contains("mpeg") || contentType.contains("mp3") {
            ext = "mp3"
        } else {
            ext = "wav"
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".\(ext)")
        try audioData.write(to: tempURL, options: .atomic)

        activeDelegate?.cancel()
        activePlayer?.stop()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try session.setActive(true)

        let player = try AVAudioPlayer(contentsOf: tempURL)
        player.prepareToPlay()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = TTSPlaybackDelegate(continuation: continuation, fileURL: tempURL)
            player.delegate = delegate

            self.activePlayer = player
            self.activeDelegate = delegate

            _ = player.play()
        }
    }
}

private final class TTSPlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private let fileURL: URL

    init(continuation: CheckedContinuation<Void, Error>, fileURL: URL) {
        self.continuation = continuation
        self.fileURL = fileURL
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        cleanup()
        continuation?.resume(returning: ())
        continuation = nil
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        cleanup()
        continuation?.resume(throwing: error ?? LingoDexServiceError.ttsFailed)
        continuation = nil
    }

    func cancel() {
        cleanup()
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    private func cleanup() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
