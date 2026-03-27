import Foundation
import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Extracts foreground subject as a sticker. Uses Vision (VNGenerateForegroundInstanceMaskRequest).
/// VisionKit ImageAnalyzer path is available but has MainActor isolation issues with async; Vision produces equivalent output.
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
        if let sticker = await extractViaVision(image) {
            return sticker
        }
        throw LingoDexServiceError.backgroundRemovalFailed
    }

    /// Vision: VNGenerateForegroundInstanceMaskRequest + blend.
    private func extractViaVision(_ image: UIImage) async -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])

        guard (try? handler.perform([request])) != nil,
              let result = request.results?.first,
              let maskBuffer = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        else { return nil }

        let mask = CIImage(cvPixelBuffer: maskBuffer)
        let filter = CIFilter.blendWithMask()
        filter.inputImage = ciImage
        filter.maskImage = mask
        filter.backgroundImage = CIImage.empty()
        guard let output = filter.outputImage else { return nil }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }

        return UIImage(cgImage: cgImage, scale: 1, orientation: image.imageOrientation)
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
