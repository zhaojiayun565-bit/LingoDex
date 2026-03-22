import Foundation
import UIKit

actor LocalLingoDexStore {
    private struct PersistedState: Codable {
        var sessions: [CaptureSession]
    }

    private let stateFileName = "lingodex_store.json"

    private var baseURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private var stateFileURL: URL {
        baseURL.appendingPathComponent(stateFileName)
    }

    private var imagesDirectoryURL: URL {
        baseURL.appendingPathComponent("lingodex_images", isDirectory: true)
    }

    /// Temp full captures for pending recognition retry.
    private var pendingCapturesDirectoryURL: URL {
        baseURL.appendingPathComponent("lingodex_pending_captures", isDirectory: true)
    }

    func loadSessions() async throws -> [CaptureSession] {
        let url = stateFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
        return decoded.sessions
    }

    func saveSessions(_ sessions: [CaptureSession]) async throws {
        let state = PersistedState(sessions: sessions)
        let data = try JSONEncoder().encode(state)
        try data.write(to: stateFileURL, options: [.atomic])
    }

    func saveImageJpeg(_ image: UIImage, fileName: String) async throws {
        try ensureImagesDirectory()
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try data.write(to: imagesDirectoryURL.appendingPathComponent(fileName), options: [.atomic])
    }

    /// Saves image as PNG to preserve transparency (e.g. background-removed sticker assets).
    func saveImagePng(_ image: UIImage, fileName: String) async throws {
        try ensureImagesDirectory()
        guard let data = image.pngData() else { throw LingoDexServiceError.invalidImage }
        try data.write(to: imagesDirectoryURL.appendingPathComponent(fileName), options: [.atomic])
    }

    func loadImage(fileName: String) async throws -> UIImage? {
        let url = imagesDirectoryURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return UIImage(data: data)
    }

    /// Saves full capture JPEG for pending recognition retry.
    func savePendingCapture(_ image: UIImage, fileName: String) async throws {
        try ensureDirectory(pendingCapturesDirectoryURL)
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try data.write(to: pendingCapturesDirectoryURL.appendingPathComponent(fileName), options: [.atomic])
    }

    func loadPendingCapture(fileName: String) async throws -> UIImage? {
        let url = pendingCapturesDirectoryURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return UIImage(data: data)
    }

    func deletePendingCapture(fileName: String) async throws {
        let url = pendingCapturesDirectoryURL.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Removes image file for a deleted word.
    func deleteImage(fileName: String) async throws {
        let url = imagesDirectoryURL.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func ensureImagesDirectory() throws {
        try ensureDirectory(imagesDirectoryURL)
    }

    private func ensureDirectory(_ url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

