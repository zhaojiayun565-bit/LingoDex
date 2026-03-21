import Foundation
import Translation

struct AppleTranslationClient: TranslationClient {
    func translate(_ text: String, to language: Language) async throws -> String {
        guard language != .english else { return text }

        let source = Locale.Language(identifier: Language.english.localeTag)
        let target = Locale.Language(identifier: language.localeTag)

        // TranslationSession is only available starting iOS 18.
        guard #available(iOS 18.0, *) else {
            throw LingoDexServiceError.translationUnavailable
        }

        // The on-device "installedSource:target:" initializer used here is iOS 26+.
        guard #available(iOS 26.0, *) else {
            throw LingoDexServiceError.translationUnavailable
        }

        do {
            let session = try TranslationSession(installedSource: source, target: target)
            let response = try await session.translate(text)
            return response.targetText
        } catch {
            throw LingoDexServiceError.translationUnavailable
        }
    }
}

