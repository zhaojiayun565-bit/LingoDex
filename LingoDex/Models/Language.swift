import Foundation

enum Language: String, CaseIterable, Identifiable, Codable, Hashable {
    case english
    case french
    case spanish
    case mandarinChinese
    case japanese
    case korean

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .french: "French"
        case .spanish: "Spanish"
        case .mandarinChinese: "Mandarin Chinese"
        case .japanese: "Japanese"
        case .korean: "Korean"
        }
    }

    /// Best-effort BCP-47 language tags for Apple Translation / Speech usage.
    var localeTag: String {
        switch self {
        case .english: "en"
        case .french: "fr"
        case .spanish: "es"
        case .mandarinChinese: "zh-Hans"
        case .japanese: "ja"
        case .korean: "ko"
        }
    }

    /// Current learning language from persisted user preference.
    static var currentLearning: Language {
        let raw = UserDefaults.standard.string(forKey: "lingodex_learning_language")
        return (raw.flatMap { Language(rawValue: $0) }) ?? .english
    }
}

