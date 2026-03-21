import Foundation
import Observation

@MainActor
@Observable final class WorldViewModel {
    private let deps: Dependencies

    init(deps: Dependencies) {
        self.deps = deps
    }
}

