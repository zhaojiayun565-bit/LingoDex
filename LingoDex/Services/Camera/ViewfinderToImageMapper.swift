import CoreGraphics
import UIKit

/// Maps viewfinder rect (in preview layer coordinates) to normalized [x, y, width, height] 0-1 for the captured image.
enum ViewfinderToImageMapper {
    /// Viewfinder frame size (points) - must match ViewfinderFrame in FullScreenCameraView.
    static let viewfinderWidth: CGFloat = 280
    static let viewfinderHeight: CGFloat = 360

    /// Returns normalized bbox string "[x, y, width, height]" for Gemini prompt.
    /// - Parameters:
    ///   - previewSize: The preview layer / view size at capture time.
    ///   - imageSize: Captured image pixel size (before orientation).
    ///   - imageOrientation: UIImage orientation of the captured photo.
    static func normalizedBBoxString(
        previewSize: CGSize,
        imageSize: CGSize,
        imageOrientation: UIImage.Orientation = .up
    ) -> String {
        let rect = normalizedBBox(previewSize: previewSize, imageSize: imageSize, imageOrientation: imageOrientation)
        return "[\(rect.origin.x), \(rect.origin.y), \(rect.size.width), \(rect.size.height)]"
    }

    /// Returns normalized rect (x, y, width, height) in 0-1 for the viewfinder region.
    static func normalizedBBox(
        previewSize: CGSize,
        imageSize: CGSize,
        imageOrientation: UIImage.Orientation = .up
    ) -> CGRect {
        // Viewfinder is centered; rect in preview coordinates.
        let vfX = (previewSize.width - viewfinderWidth) / 2
        let vfY = (previewSize.height - viewfinderHeight) / 2
        let viewfinderRect = CGRect(x: vfX, y: vfY, width: viewfinderWidth, height: viewfinderHeight)

        // With resizeAspectFill, preview shows a cropped region of the image.
        // Compute visible image region in image coordinates.
        let imageW = imageSize.width
        let imageH = imageSize.height
        guard imageW > 0, imageH > 0 else { return CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5) }

        let previewAspect = previewSize.width / previewSize.height
        let imageAspect = imageW / imageH

        let visibleImageRect: CGRect
        if imageAspect > previewAspect {
            // Image wider: visible height = full image height, visible width is cropped.
            let visibleWidth = imageH * previewAspect
            let offsetX = (imageW - visibleWidth) / 2
            visibleImageRect = CGRect(x: offsetX, y: 0, width: visibleWidth, height: imageH)
        } else {
            // Image taller: visible width = full image width, visible height is cropped.
            let visibleHeight = imageW / previewAspect
            let offsetY = (imageH - visibleHeight) / 2
            visibleImageRect = CGRect(x: 0, y: offsetY, width: imageW, height: visibleHeight)
        }

        // Map viewfinder rect (in preview coords) to visible image rect.
        let scaleX = visibleImageRect.width / previewSize.width
        let scaleY = visibleImageRect.height / previewSize.height
        let imageRect = CGRect(
            x: visibleImageRect.minX + viewfinderRect.minX * scaleX,
            y: visibleImageRect.minY + viewfinderRect.minY * scaleY,
            width: viewfinderRect.width * scaleX,
            height: viewfinderRect.height * scaleY
        )

        // Normalize to 0-1 and apply orientation.
        var norm = CGRect(
            x: imageRect.minX / imageW,
            y: imageRect.minY / imageH,
            width: imageRect.width / imageW,
            height: imageRect.height / imageH
        )

        // AVCapture back camera typically returns .right for portrait; adjust if needed.
        norm = orientNormalizedRect(norm, orientation: imageOrientation)
        return clampToUnitRect(norm)
    }

    private static func orientNormalizedRect(_ r: CGRect, orientation: UIImage.Orientation) -> CGRect {
        switch orientation {
        case .up:
            return r
        case .down:
            return CGRect(x: 1 - r.maxX, y: 1 - r.maxY, width: r.width, height: r.height)
        case .left:
            return CGRect(x: 1 - r.maxY, y: r.minX, width: r.height, height: r.width)
        case .right:
            return CGRect(x: r.minY, y: 1 - r.maxX, width: r.height, height: r.width)
        case .upMirrored, .downMirrored, .leftMirrored, .rightMirrored:
            // Simplified: treat as up for now.
            return r
        @unknown default:
            return r
        }
    }

    private static func clampToUnitRect(_ r: CGRect) -> CGRect {
        let x = max(0, min(1, r.origin.x))
        let y = max(0, min(1, r.origin.y))
        let w = max(0.01, min(1 - x, r.width))
        let h = max(0.01, min(1 - y, r.height))
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
