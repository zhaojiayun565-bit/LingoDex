import Foundation
import UIKit
import ImageIO

/// Loads images from disk with in-memory caching and optional downsampling for grid thumbnails.
final class ImageLoadingService {
    private let imagesDirectoryURL: URL
    private let cache = NSCache<NSString, UIImage>()
    private let thumbCache = NSCache<NSString, UIImage>()

    private let thumbCacheKeyPrefix = "thumb_"
    private let maxCacheCost = 50 * 1024 * 1024 // ~50 MB in pixels (approximate)

    init(imagesDirectoryURL: URL) {
        self.imagesDirectoryURL = imagesDirectoryURL
        cache.totalCostLimit = maxCacheCost
        thumbCache.totalCostLimit = maxCacheCost / 2
    }

    /// Loads a downsampled thumbnail for grid display. Uses ImageIO to decode at target size.
    func loadThumbnail(fileName: String, maxSize: CGFloat) async -> UIImage? {
        let key = "\(thumbCacheKeyPrefix)\(maxSize)_\(fileName)" as NSString
        if let cached = thumbCache.object(forKey: key) { return cached }

        let url = imagesDirectoryURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let image: UIImage? = await Task.detached(priority: .userInitiated) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSize
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil as UIImage?
            }
            return UIImage(cgImage: cgImage)
        }.value

        if let image {
            let cost = Int(image.size.width * image.size.height)
            thumbCache.setObject(image, forKey: key, cost: cost)
            return image
        }
        return nil
    }

    /// Loads full-resolution image for detail view. Checks cache first.
    func loadFullImage(fileName: String) async throws -> UIImage? {
        let key = fileName as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let url = imagesDirectoryURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let image = try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)
            return UIImage(data: data)
        }.value

        if let image {
            let cost = Int(image.size.width * image.size.height)
            cache.setObject(image, forKey: key, cost: cost)
            return image
        }
        return nil
    }
}
