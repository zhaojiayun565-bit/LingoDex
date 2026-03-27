import Foundation
import Observation
import Supabase

@Observable final class SupabaseAuthClient: AuthClient, @unchecked Sendable {
    private(set) var currentUser: AuthUser? = nil
    var accessToken: String? { UserDefaults.standard.string(forKey: accessTokenKey) }

    private let supabase: SupabaseClient
    private let accessTokenKey = "lingodex_supabase_access_token"
    private let refreshTokenKey = "lingodex_supabase_refresh_token"
    private let userIdKey = "lingodex_supabase_user_id"
    private let displayNameKey = "lingodex_supabase_display_name"

    init(supabase: SupabaseClient) {
        self.supabase = supabase
        if let cachedId = UserDefaults.standard.string(forKey: userIdKey) {
            let cachedName = UserDefaults.standard.string(forKey: displayNameKey) ?? "Learner"
            self.currentUser = AuthUser(id: cachedId, displayName: cachedName)
        }
        Task { await restoreSessionAndListenForChanges() }
    }

    func signInWithAppleIdToken(
        _ idToken: String,
        nonce: String?,
        fullName: String?
    ) async throws -> AuthUser {
        if !Self.isSupabaseConfigured {
            throw LingoDexServiceError.supabaseNotConfigured
        }
        let credentials = OpenIDConnectCredentials(
            provider: .apple,
            idToken: idToken,
            nonce: nonce
        )
        let session = try await supabase.auth.signInWithIdToken(credentials: credentials)
        var user = mapToAuthUser(session: session, fallbackFullName: fullName)
        if let fullName, !fullName.isEmpty {
            try? await supabase.auth.update(user: UserAttributes(data: ["full_name": .string(fullName)]))
            user = AuthUser(id: user.id, displayName: fullName)
        }
        currentUser = user
        storeSession(accessToken: session.accessToken, refreshToken: session.refreshToken, user: user)
        return user
    }

    func signOut() async throws {
        try await supabase.auth.signOut()
        currentUser = nil
        UserDefaults.standard.removeObject(forKey: accessTokenKey)
        UserDefaults.standard.removeObject(forKey: refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: displayNameKey)
    }

    private static var isSupabaseConfigured: Bool {
        let urlString = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String)
            ?? ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? ""
        let key = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String)
            ?? ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? ""
        return !urlString.isEmpty && !key.isEmpty && !urlString.contains("placeholder")
    }

    private func storeSession(accessToken: String, refreshToken: String?, user: AuthUser) {
        UserDefaults.standard.set(accessToken, forKey: accessTokenKey)
        UserDefaults.standard.set(refreshToken, forKey: refreshTokenKey)
        UserDefaults.standard.set(user.id, forKey: userIdKey)
        UserDefaults.standard.set(user.displayName, forKey: displayNameKey)
    }

    private func mapToAuthUser(session: Session, fallbackFullName: String?) -> AuthUser {
        let u = session.user
        let displayName: String = {
            if let full = u.userMetadata["full_name"]?.stringValue, !full.isEmpty { return full }
            if let given = u.userMetadata["given_name"]?.stringValue {
                let family = u.userMetadata["family_name"]?.stringValue ?? ""
                return (given + " " + family).trimmingCharacters(in: .whitespaces)
            }
            return fallbackFullName ?? "Learner"
        }()
        return AuthUser(id: u.id.uuidString, displayName: displayName)
    }

    private func restoreSessionAndListenForChanges() async {
        do {
            let session = try await supabase.auth.session
            let user = mapToAuthUser(session: session, fallbackFullName: nil)
            currentUser = user
            storeSession(accessToken: session.accessToken, refreshToken: session.refreshToken, user: user)
        } catch {
            currentUser = nil
        }

        for await (event, session) in await supabase.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .tokenRefreshed:
                let resolvedSession: Session? = {
                    if event == .initialSession {
                        return nil // resolved below via async check
                    }
                    return session
                }()

                if let resolvedSession {
                    let user = mapToAuthUser(session: resolvedSession, fallbackFullName: nil)
                    currentUser = user
                    storeSession(accessToken: resolvedSession.accessToken, refreshToken: resolvedSession.refreshToken, user: user)
                } else if event == .initialSession {
                    // Local session is now emitted immediately; verify it isn't expired before treating as signed-in.
                    do {
                        let valid = try await supabase.auth.session
                        let user = mapToAuthUser(session: valid, fallbackFullName: nil)
                        currentUser = user
                        storeSession(accessToken: valid.accessToken, refreshToken: valid.refreshToken, user: user)
                    } catch {
                        currentUser = nil
                        UserDefaults.standard.removeObject(forKey: accessTokenKey)
                        UserDefaults.standard.removeObject(forKey: refreshTokenKey)
                        UserDefaults.standard.removeObject(forKey: userIdKey)
                        UserDefaults.standard.removeObject(forKey: displayNameKey)
                    }
                }
            case .signedOut, .userUpdated:
                if event == .signedOut {
                    currentUser = nil
                    UserDefaults.standard.removeObject(forKey: accessTokenKey)
                    UserDefaults.standard.removeObject(forKey: refreshTokenKey)
                    UserDefaults.standard.removeObject(forKey: userIdKey)
                    UserDefaults.standard.removeObject(forKey: displayNameKey)
                } else if let session {
                    let user = mapToAuthUser(session: session, fallbackFullName: nil)
                    currentUser = user
                    storeSession(accessToken: session.accessToken, refreshToken: session.refreshToken, user: user)
                }
            default:
                break
            }
        }
    }
}
