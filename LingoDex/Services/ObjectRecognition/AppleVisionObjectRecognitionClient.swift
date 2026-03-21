import Foundation
import UIKit
import Vision

struct AppleVisionObjectRecognitionClient: ObjectRecognitionClient {
    func recognizeObject(from image: UIImage) async throws -> RecognizedObject {
        guard let cgImage = image.cgImage else {
            throw LingoDexServiceError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let handler = VNImageRequestHandler(cgImage: cgImage)
                    // `VNRecognizeObjectsRequest` isn't available in all iOS SDKs; use image classification instead.
                    let request = VNClassifyImageRequest()
                    try handler.perform([request])

                    let observations = request.results as? [VNClassificationObservation]
                    let topLabel = observations?.first?.identifier
                    guard let label = topLabel, !label.isEmpty else {
                        continuation.resume(throwing: LingoDexServiceError.recognitionFailed)
                        return
                    }

                    let formatted = label.replacingOccurrences(of: "_", with: " ").capitalized
                    continuation.resume(returning: RecognizedObject(englishWord: formatted))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

