import UIKit

/// Metadata for a captured image, used to compute viewfinder bbox for recognition.
struct CapturedImageInfo {
    let image: UIImage
    /// Preview layer size at capture time; nil for photo library (use full image).
    let previewSize: CGSize?

    /// Normalized bbox string for Gemini prompt.
    var normalizedBBoxString: String {
        guard let size = previewSize, size.width > 0, size.height > 0 else {
            return "[0, 0, 1, 1]"
        }
        let imgSize = CGSize(
            width: CGFloat(image.cgImage?.width ?? Int(image.size.width * image.scale)),
            height: CGFloat(image.cgImage?.height ?? Int(image.size.height * image.scale))
        )
        return ViewfinderToImageMapper.normalizedBBoxString(
            previewSize: size,
            imageSize: imgSize,
            imageOrientation: image.imageOrientation
        )
    }
}
