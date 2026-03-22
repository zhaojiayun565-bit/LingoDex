import Foundation
import Observation

@Observable final class SupabaseAuthClient: AuthClient, @unchecked Sendable {
    private(set) var currentUser: AuthUser? = nil
    var accessToken: String? { UserDefaults.standard.string(forKey: accessTokenKey) }

    // MVP persistence: we only need enough to keep the UI gated behind auth.
    private let accessTokenKey = "lingodex_supabase_access_token"
    private let refreshTokenKey = "lingodex_supabase_refresh_token"
    private let userIdKey = "lingodex_supabase_user_id"
    private let displayNameKey = "lingodex_supabase_display_name"

    init() {
        Task { await restoreSessionIfPossible() }
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let token_type: String?
        let expires_in: Int?
        let user: SupabaseUser
    }

    private struct SupabaseUser: Decodable {
        let id: String
        let user_metadata: [String: String]?
    }

    func signInWithAppleIdToken(
        _ idToken: String,
        nonce: String?,
        fullName: String?
    ) async throws -> AuthUser {
        guard let supabaseURL = Self.config.supabaseURL,
              let anonKey = Self.config.anonKey
        else {
            throw LingoDexServiceError.supabaseNotConfigured
        }

        var urlComponents = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false)
        // Expected base: https://<project>.supabase.co
        urlComponents?.path = "/auth/v1/token"
        urlComponents?.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]

        guard let url = urlComponents?.url else {
            throw URLError(.badURL)
        }

        var body: [String: Any] = [
            "provider": "apple",
            "id_token": idToken
        ]
        if let nonce {
            body["nonce"] = nonce
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)

        let metadata = token.user.user_metadata
        let displayName =
            metadata?["full_name"]
            ?? {
                if let given = metadata?["given_name"] {
                    let family = metadata?["family_name"] ?? ""
                    return (given + " " + family).trimmingCharacters(in: .whitespaces)
                }
                return fullName ?? "Learner"
            }()

        let user = AuthUser(id: token.user.id, displayName: displayName)
        currentUser = user
        storeSession(accessToken: token.access_token, refreshToken: token.refresh_token, user: user)

        return user
    }

    func signOut() async throws {
        currentUser = nil
        UserDefaults.standard.removeObject(forKey: accessTokenKey)
        UserDefaults.standard.removeObject(forKey: refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: displayNameKey)
    }

    private func storeSession(accessToken: String, refreshToken: String?, user: AuthUser) {
        UserDefaults.standard.set(accessToken, forKey: accessTokenKey)
        UserDefaults.standard.set(refreshToken, forKey: refreshTokenKey)
        UserDefaults.standard.set(user.id, forKey: userIdKey)
        UserDefaults.standard.set(user.displayName, forKey: displayNameKey)
    }

    private func restoreSessionIfPossible() async {
        let storedUserId = UserDefaults.standard.string(forKey: userIdKey)
        let storedDisplay = UserDefaults.standard.string(forKey: displayNameKey)
        let storedAccess = UserDefaults.standard.string(forKey: accessTokenKey)

        guard
            let storedUserId,
            !storedUserId.isEmpty,
            let storedAccess,
            !storedAccess.isEmpty
        else { return }

        currentUser = AuthUser(id: storedUserId, displayName: storedDisplay ?? "Learner")
    }

    private static var config: Config {
        Config()
    }

    private struct Config {
        var supabaseURL: URL? {
            if let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String {
                return URL(string: value)
            }
            if let value = ProcessInfo.processInfo.environment["SUPABASE_URL"] {
                return URL(string: value)
            }
            return nil
        }

        var anonKey: String? {
            if let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String {
                return value
            }
            if let value = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] {
                return value
            }
            return nil
        }
    }
}

