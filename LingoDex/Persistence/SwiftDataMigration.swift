import Foundation
import SwiftData

/// One-time migration from JSON LocalLingoDexStore to SwiftData.
enum SwiftDataMigration {
    private static let migrationDoneKey = "lingodex_swiftdata_migration_done"
    private static let stateFileName = "lingodex_store.json"

    private static var stateFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent(stateFileName)
    }

    private static var stateFileExists: Bool {
        FileManager.default.fileExists(atPath: stateFileURL.path)
    }

    /// Runs migration off the main thread: file I/O, decode, and SwiftData writes on a dedicated `ModelContext`.
    static func runIfNeeded(modelContainer: ModelContainer) async {
        await MigrationCoordinator.shared.runIfNeeded(modelContainer: modelContainer)
    }

    /// Serializes migration attempts and keeps UserDefaults checks consistent with async work.
    private actor MigrationCoordinator {
        static let shared = MigrationCoordinator()

        func runIfNeeded(modelContainer: ModelContainer) async {
            guard !UserDefaults.standard.bool(forKey: SwiftDataMigration.migrationDoneKey) else { return }
            guard SwiftDataMigration.stateFileExists else { return }

            let fileURL = SwiftDataMigration.stateFileURL
            let decoded: LegacyPersistedState? = await Task.detached {
                guard let data = try? Data(contentsOf: fileURL) else { return nil }
                return try? JSONDecoder().decode(LegacyPersistedState.self, from: data)
            }.value

            guard let decoded else { return }

            let saved = await Task.detached {
                let context = ModelContext(modelContainer)
                for session in decoded.sessions {
                    for word in session.words {
                        let entity = CapturedWordEntity(
                            id: word.id,
                            createdAt: word.createdAt,
                            imageFileName: word.imageFileName,
                            learnWord: word.learnWord,
                            nativeWord: word.nativeWord,
                            recognizedEnglish: word.recognizedEnglish,
                            srsRatingRaw: word.srs.rating ?? SRSRating.good.rawValue,
                            srsNextDueDate: word.srs.nextDueDate,
                            srsLastReviewedAt: word.srs.lastReviewedAt,
                            recognitionStatusRaw: RecognitionStatus.ready.rawValue
                        )
                        context.insert(entity)
                    }
                }
                do {
                    try context.save()
                    return true
                } catch {
                    return false
                }
            }.value

            if saved {
                UserDefaults.standard.set(true, forKey: SwiftDataMigration.migrationDoneKey)
            }
        }
    }
}

// MARK: - Legacy JSON shapes (decode only; not tied to MainActor)

private struct LegacyPersistedState: Codable {
    var sessions: [LegacySession]
}

private struct LegacySession: Codable {
    var id: UUID
    var date: Date
    var words: [LegacyWord]
}

private struct LegacyWord: Codable {
    var id: UUID
    var imageFileName: String
    var recognizedEnglish: String
    var learnWord: String
    var nativeWord: String
    var createdAt: Date
    var srs: LegacySRS
}

private struct LegacySRS: Codable {
    var rating: String?
    var nextDueDate: Date?
    var lastReviewedAt: Date?
}
