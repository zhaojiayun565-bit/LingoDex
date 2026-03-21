import Foundation
import Observation

@MainActor
@Observable final class PracticeViewModel {
    private let deps: Dependencies
    var sessions: [CaptureSession] = []
    private var lastLoadedAt: Date? = nil

    var dueWords: [WordEntry] {
        let now = Date()
        let allWords = sessions.flatMap { $0.words }
        let due = allWords.filter { word in
            (word.srs.nextDueDate ?? Date.distantPast) <= now
        }
        return due.sorted {
            ($0.srs.nextDueDate ?? Date.distantPast) < ($1.srs.nextDueDate ?? Date.distantPast)
        }
    }

    init(deps: Dependencies) {
        self.deps = deps
        Task { await load() }
    }

    func load() async {
        do {
            sessions = try await deps.localStore.loadSessions()
            lastLoadedAt = Date()
        } catch {
            sessions = []
            lastLoadedAt = nil
        }
    }

    func rate(wordId: UUID, rating: SRSRating) {
        let now = Date()

        var didUpdate = false
        for sessionIndex in sessions.indices {
            guard let wordIndex = sessions[sessionIndex].words.firstIndex(where: { $0.id == wordId }) else { continue }
            let current = sessions[sessionIndex].words[wordIndex]
            let updated = current.withUpdatedSRS(rating: rating, now: now)
            sessions[sessionIndex].words[wordIndex] = updated
            didUpdate = true
            break
        }

        guard didUpdate else { return }

        Task {
            do {
                try await deps.localStore.saveSessions(sessions)
            } catch {
                // For MVP: ignore persistence failures.
            }
        }
    }
}

private extension WordEntry {
    func withUpdatedSRS(rating: SRSRating, now: Date) -> WordEntry {
        var copy = self
        copy.srs = SRSLogic.nextState(current: srs, rating: rating, now: now)
        return copy
    }
}

