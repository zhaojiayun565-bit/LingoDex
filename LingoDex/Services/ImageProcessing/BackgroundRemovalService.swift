import Foundation
import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Extracts foreground objects from an image using Vision, removing the background.
/// Uses VNGenerateForegroundInstanceMaskRequest (iOS 17+). Works on device only; Simulator unsupported.
/// CIContext is lazy to avoid blocking app launch with GPU setup.
final class BackgroundRemovalService: Sendable {
    private lazy var ciContext: CIContext = { CIContext(options: [.useSoftwareRenderer: false]) }()

    /// Returns the input image with background removed (transparent). Preserves orientation.
    func removeBackground(from image: UIImage) async throws -> UIImage {
        guard let ciImage = CIImage(image: image) else {
            throw LingoDexServiceError.invalidImage
        }
        let orientation = image.imageOrientation
        let ciContext = ciContext

        return try await Task.detached(priority: .userInitiated) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])

            try handler.perform([request])
            guard let result = request.results?.first else {
                throw LingoDexServiceError.backgroundRemovalFailed
            }
            let maskBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
            let mask = CIImage(cvPixelBuffer: maskBuffer)

            let filter = CIFilter.blendWithMask()
            filter.inputImage = ciImage
            filter.maskImage = mask
            filter.backgroundImage = CIImage.empty()
            let masked = filter.outputImage ?? ciImage

            guard let cgImage = ciContext.createCGImage(masked, from: masked.extent) else {
                throw LingoDexServiceError.backgroundRemovalFailed
            }
            return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
        }.value
    }
}
