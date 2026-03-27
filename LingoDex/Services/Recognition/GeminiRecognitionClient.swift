import Foundation
import UIKit

/// Calls the Supabase recognize-object Edge Function (Gemini) for object recognition.
struct GeminiRecognitionClient: Sendable {
    private let supabaseURL: URL
    private let anonKey: String
    private let authTokenProvider: @Sendable () -> String?

    init(supabaseURL: URL, anonKey: String, authTokenProvider: @escaping @Sendable () -> String?) {
        self.supabaseURL = supabaseURL
        self.anonKey = anonKey
        self.authTokenProvider = authTokenProvider
    }

    /// Establishes HTTP connection to Supabase host so first recognize call is fast. Skips if not signed in.
    func warmUp() async {
        guard authTokenProvider() != nil else { return }
        var request = URLRequest(url: supabaseURL)
        request.httpMethod = "HEAD"
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Sends downscaled image to Gemini via Edge Function. Returns metadata or throws.
    func recognize(
        image: UIImage,
        boundingBox: String,
        nativeLanguage: String,
        learningLanguage: String
    ) async throws -> GeminiRecognitionResult {
        guard let token = authTokenProvider() else {
            throw LingoDexServiceError.supabaseNotConfigured
        }

        let jpegData = downscaledJpegData(from: image)
        let base64 = jpegData.base64EncodedString()

        var components = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false)
        components?.path = "/functions/v1/recognize-object"
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "image_base64": base64,
            "mime_type": "image/jpeg",
            "native_language": nativeLanguage,
            "learning_language": learningLanguage,
            "bounding_box": boundingBox,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        guard (200..<300).contains(http.statusCode) else {
            if let err = try? JSONDecoder().decode(EdgeFunctionError.self, from: data) {
                throw LingoDexServiceError.recognitionFailed
            }
            throw LingoDexServiceError.recognitionFailed
        }

        let decoder = JSONDecoder()
        return try decoder.decode(GeminiRecognitionResult.self, from: data)
    }

    /// Downscales image to reduce token usage (Edge Function also uses media_resolution LOW).
    private func downscaledJpegData(from image: UIImage) -> Data {
        let maxDimension: CGFloat = 640
        let size = image.size
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.8) ?? Data()
    }
}

private struct EdgeFunctionError: Decodable {
    let error: String?
}
