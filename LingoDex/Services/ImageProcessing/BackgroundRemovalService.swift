import Foundation
import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Extracts foreground objects from an image using Vision, removing the background.
/// Uses VNGenerateForegroundInstanceMaskRequest (iOS 17+). Works on device only; Simulator unsupported.
struct BackgroundRemovalService: Sendable {
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Returns the input image with background removed (transparent). Preserves orientation.
    func removeBackground(from image: UIImage) async throws -> UIImage {
        guard let ciImage = CIImage(image: image) else {
            throw LingoDexServiceError.invalidImage
        }

        guard let mask = createMask(from: ciImage) else {
            throw LingoDexServiceError.backgroundRemovalFailed
        }

        let maskedImage = applyMask(mask: mask, to: ciImage)
        return try convertToUIImage(maskedImage, orientation: image.imageOrientation)
    }

    /// Generates a foreground mask using Vision.
    private func createMask(from inputImage: CIImage) -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: inputImage, options: [:])

        do {
            try handler.perform([request])
            guard let result = request.results?.first else { return nil }
            let maskBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
            return CIImage(cvPixelBuffer: maskBuffer)
        } catch {
            return nil
        }
    }

    /// Applies mask to input image; background becomes transparent.
    private func applyMask(mask: CIImage, to image: CIImage) -> CIImage {
        let filter = CIFilter.blendWithMask()
        filter.inputImage = image
        filter.maskImage = mask
        filter.backgroundImage = CIImage.empty()
        return filter.outputImage ?? image
    }

    /// Converts CIImage to UIImage, preserving orientation.
    private func convertToUIImage(_ ciImage: CIImage, orientation: UIImage.Orientation = .up) throws -> UIImage {
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw LingoDexServiceError.backgroundRemovalFailed
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }
}
