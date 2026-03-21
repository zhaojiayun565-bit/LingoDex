import Foundation
import Observation

@MainActor
@Observable final class MeViewModel {
    private let deps: Dependencies

    var user: AuthUser?
    var nativeLanguage: Language = .english
    var learningLanguage: Language = .english

    private let learningLanguageKey = "lingodex_learning_language"

    init(deps: Dependencies) {
        self.deps = deps
        self.user = deps.auth.currentUser
        if let systemLang = Locale.current.languageCode {
            nativeLanguage = Self.languageFromSystemCode(systemLang)
        }

        if let saved = UserDefaults.standard.string(forKey: learningLanguageKey),
           let lang = Language(rawValue: saved) {
            learningLanguage = lang
        }
    }

    func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws {
        // #region agent log
        agentDebugLog(
            hypothesisId: "H5_supabase_signin_inputs",
            location: "MeViewModel.swift:signInWithApple.entry",
            message: "about to exchange Apple token with auth client",
            data: [
                // Do not log the token contents.
                "idTokenLen": String(idToken.count),
                "hasNonce": nonce != nil ? "true" : "false",
                "hasFullName": fullName != nil ? "true" : "false",
            ],
            runId: "signin_runtime_debug_pre"
        )
        // #endregion

        user = try await deps.auth.signInWithAppleIdToken(idToken, nonce: nonce, fullName: fullName)
    }

    func signOut() async {
        do {
            try await deps.auth.signOut()
            user = nil
        } catch {
            // No-op for MVP.
        }
    }

    private static func languageFromSystemCode(_ code: String) -> Language {
        switch code.lowercased() {
        case "fr": return .french
        case "es": return .spanish
        case "ja": return .japanese
        case "ko": return .korean
        case "zh": return .mandarinChinese
        default: return .english
        }
    }
}

private func agentDebugLog(
    hypothesisId: String,
    location: String,
    message: String,
    data: [String: String],
    runId: String = "signin_runtime_debug_pre"
) {
    let logPath = "/Users/jiayunzhao/Documents/LingoDex/.cursor/debug-7aeddd.log"
    let sessionId = "7aeddd"

    let payload: [String: Any] = [
        "sessionId": sessionId,
        "runId": runId,
        "hypothesisId": hypothesisId,
        "location": location,
        "message": message,
        "data": data,
        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
    ]

    guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []),
          let line = String(data: jsonData, encoding: .utf8),
          let lineData = (line + "\n").data(using: .utf8)
    else { return }

    if !FileManager.default.fileExists(atPath: logPath) {
        FileManager.default.createFile(atPath: logPath, contents: nil)
    }

    guard let handle = FileHandle(forWritingAtPath: logPath) else { return }
    handle.seekToEndOfFile()
    handle.write(lineData)
    try? handle.close()
}

