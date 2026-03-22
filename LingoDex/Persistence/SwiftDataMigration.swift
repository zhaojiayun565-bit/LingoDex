import Foundation
import SwiftData

/// One-time migration from JSON LocalLingoDexStore to SwiftData.
final class SwiftDataMigration {
    private static let migrationDoneKey = "lingodex_swiftdata_migration_done"
    private let stateFileName = "lingodex_store.json"

    private var stateFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent(stateFileName)
    }

    /// Runs migration if JSON exists and migration has not run.
    static func runIfNeeded(modelContext: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migrationDoneKey) else { return }
        let migrator = SwiftDataMigration()
        guard migrator.stateFileExists else { return }

        migrator.migrate(into: modelContext)
        UserDefaults.standard.set(true, forKey: migrationDoneKey)
    }

    private var stateFileExists: Bool {
        FileManager.default.fileExists(atPath: stateFileURL.path)
    }

    private func migrate(into modelContext: ModelContext) {
        struct PersistedState: Codable {
            var sessions: [LegacySession]
        }
        struct LegacySession: Codable {
            var id: UUID
            var date: Date
            var words: [LegacyWord]
        }
        struct LegacyWord: Codable {
            var id: UUID
            var imageFileName: String
            var recognizedEnglish: String
            var learnWord: String
            var nativeWord: String
            var createdAt: Date
            var srs: LegacySRS
        }
        struct LegacySRS: Codable {
            var rating: String?
            var nextDueDate: Date?
            var lastReviewedAt: Date?
        }

        guard let data = try? Data(contentsOf: stateFileURL),
              let decoded = try? JSONDecoder().decode(PersistedState.self, from: data)
        else { return }

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
                modelContext.insert(entity)
            }
        }

        try? modelContext.save()
    }
}
