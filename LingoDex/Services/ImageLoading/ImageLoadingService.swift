import Foundation
import UIKit

/// Loads full-resolution images from disk for detail screens.
final class ImageLoadingService {
    private let imagesDirectoryURL: URL
    private let cache = NSCache<NSString, UIImage>()

    private let maxCacheCost = 50 * 1024 * 1024 // ~50 MB in pixels (approximate)

    init(imagesDirectoryURL: URL) {
        self.imagesDirectoryURL = imagesDirectoryURL
        cache.totalCostLimit = maxCacheCost
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
