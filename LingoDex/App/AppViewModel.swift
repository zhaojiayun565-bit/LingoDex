import Foundation
import Observation

@MainActor
@Observable final class AppViewModel {
    var selectedTab: MainTab = .captures
    private let auth: SupabaseAuthClient

    /// Derived from auth client; single source of truth for signed-in state.
    var authUser: AuthUser? { auth.currentUser }

    init(auth: SupabaseAuthClient) {
        self.auth = auth
    }
}

enum MainTab: Hashable {
    case captures
    case practice
    case world
    case me
}

