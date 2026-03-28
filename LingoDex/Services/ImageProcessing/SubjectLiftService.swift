import Foundation
import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Sticker + mask from Vision lift. The mask is rasterized from the pipeline `CIImage` for UI and concurrency safety.
struct SubjectLiftResult: Sendable {
    let sticker: UIImage
    /// Grayscale mask aligned with the sticker (same orientation).
    let mask: UIImage
}

/// Extracts foreground subject as a sticker. Uses Vision (`VNGenerateForegroundInstanceMaskRequest`).
final class SubjectLiftService: Sendable {
    private lazy var ciContext: CIContext = { CIContext(options: [.useSoftwareRenderer: false]) }()

    /// Warms Vision framework and CIContext so first real capture is fast. Call in background.
    func warmUp() async {
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        _ = try? await extractSticker(from: image)
    }

    /// Returns sticker image with transparent background.
    func extractSticker(from image: UIImage) async throws -> UIImage {
        try await extractStickerAndMask(from: image).sticker
    }

    /// Returns sticker and Vision mask (rasterized from internal `CIImage`) for edge effects.
    func extractStickerAndMask(from image: UIImage) async throws -> SubjectLiftResult {
        guard let pair = await extractViaVision(image) else {
            throw LingoDexServiceError.backgroundRemovalFailed
        }
        return SubjectLiftResult(sticker: pair.sticker, mask: pair.mask)
    }

    /// Vision: `VNGenerateForegroundInstanceMaskRequest` + blend; mask is built as `CIImage` then rasterized.
    private func extractViaVision(_ image: UIImage) async -> (sticker: UIImage, mask: UIImage)? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let orientation = image.imageOrientation
        let ciContext = self.ciContext

        return await Task.detached(priority: .userInitiated) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])

            guard (try? handler.perform([request])) != nil,
                  let result = request.results?.first,
                  let maskBuffer = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
            else { return nil }

            let maskCI = CIImage(cvPixelBuffer: maskBuffer)
            let filter = CIFilter.blendWithMask()
            filter.inputImage = ciImage
            filter.maskImage = maskCI
            filter.backgroundImage = CIImage.empty()
            guard let output = filter.outputImage else { return nil }

            guard let cgSticker = ciContext.createCGImage(output, from: output.extent) else { return nil }
            let sticker = UIImage(cgImage: cgSticker, scale: 1, orientation: orientation)

            guard let cgMask = ciContext.createCGImage(maskCI, from: maskCI.extent) else { return nil }
            let mask = UIImage(cgImage: cgMask, scale: 1, orientation: orientation)

            return (sticker, mask)
        }.value
    }
}

private extension UIImage.Orientation {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
