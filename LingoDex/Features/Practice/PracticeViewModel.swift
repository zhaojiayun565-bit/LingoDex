import Foundation
import Observation

@MainActor
@Observable final class PracticeViewModel {
    private let deps: Dependencies
    var sessions: [CaptureSession] = []
    private var lastLoadedAt: Date? = nil
    private var pendingThumbnailBackfillIDs: Set<UUID> = []
    private var thumbnailBackfillTask: Task<Void, Never>?

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
            sessions = try await deps.captureStore.loadSessionsAsync()
            lastLoadedAt = Date()
        } catch {
            sessions = []
            lastLoadedAt = nil
        }
    }

    func rate(wordId: UUID, rating: SRSRating) {
        let now = Date()

        var updatedSrs: SRSCardState?
        for sessionIndex in sessions.indices {
            guard let wordIndex = sessions[sessionIndex].words.firstIndex(where: { $0.id == wordId }) else { continue }
            let current = sessions[sessionIndex].words[wordIndex]
            let updated = current.withUpdatedSRS(rating: rating, now: now)
            sessions[sessionIndex].words[wordIndex] = updated
            updatedSrs = updated.srs
            break
        }

        guard let srs = updatedSrs else { return }

        Task {
            do {
                try deps.captureStore.updateWordSRS(id: wordId, srs: srs)
            } catch {
                // For MVP: ignore persistence failures.
            }
        }
    }

    func scheduleThumbnailBackfill(for ids: [UUID]) {
        let missing = Set(ids)
        guard !missing.isEmpty else { return }
        pendingThumbnailBackfillIDs.formUnion(missing)
        guard thumbnailBackfillTask == nil else { return }

        thumbnailBackfillTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self else { return }
            let batch = Array(self.pendingThumbnailBackfillIDs)
            self.pendingThumbnailBackfillIDs.removeAll()
            self.thumbnailBackfillTask = nil

            do {
                let changed = try await deps.captureStore.backfillMissingThumbnails(for: batch)
                if changed {
                    await load()
                }
            } catch {
                // Keep placeholder images when backfill fails.
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

