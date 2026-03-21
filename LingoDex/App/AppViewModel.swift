import Foundation
import Observation

@MainActor
@Observable final class AppViewModel {
    var selectedTab: MainTab = .captures
    var authUser: AuthUser? = nil
}

enum MainTab: Hashable {
    case captures
    case practice
    case world
    case me
}

