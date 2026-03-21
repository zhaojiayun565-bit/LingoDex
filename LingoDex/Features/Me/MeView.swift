import SwiftUI
import AuthenticationServices
import CryptoKit
import Security
import Foundation
import LocalAuthentication

struct MeView: View {
    private let deps: Dependencies
    private let appViewModel: AppViewModel
    @State private var viewModel: MeViewModel
    @State private var rawNonce: String?
    @State private var signInErrorMessage: String?

    init(deps: Dependencies, appViewModel: AppViewModel) {
        self.deps = deps
        self.appViewModel = appViewModel
        _viewModel = State(initialValue: MeViewModel(deps: deps))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Me")
                .font(.system(size: 28, weight: .bold, design: .monospaced))

            if let user = viewModel.user {
                HStack(spacing: 12) {
                    Circle().fill(Color.gray.opacity(0.15)).frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName)
                            .font(.system(size: 18, weight: .semibold))
                        Text("Signed in")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Button(role: .destructive) {
                    Task { await viewModel.signOut() }
                } label: {
                    Text("Sign out")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Sign in to save your captures and practice progress.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

#if DEBUG
                Button {
                    // Debug-only auth bypass for local feature testing.
                    viewModel.user = AuthUser(id: "debug-test-user", displayName: "Tester")
                    signInErrorMessage = nil
                } label: {
                    Text("Continue in Test Mode")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(DesignTokens.colors.primary)
#endif

                SignInWithAppleButton { request in
                    let nonce = randomNonceString()
                    rawNonce = nonce
                    request.requestedScopes = [.email, .fullName]
                    request.nonce = sha256(nonce)

                    let laContext = LAContext()
                    var laError: NSError?
                    let canEvaluate = laContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &laError)

                    // #region agent log
                    agentDebugLog(
                        hypothesisId: "H1_passcode_or_secure_auth_prereq",
                        location: "MeView.swift:request.canEvaluatePolicy",
                        message: "deviceOwnerAuthentication canEvaluatePolicy result",
                        data: [
                            "canEvaluate": canEvaluate ? "true" : "false",
                            "laErrorCode": String(laError?.code ?? -1),
                        ]
                    )
                    // #endregion

                    #if targetEnvironment(simulator)
                    let isSimulator = "true"
                    #else
                    let isSimulator = "false"
                    #endif

                    // #region agent log
                    agentDebugLog(
                        hypothesisId: "H2_bundle_id_or_simulator_environment",
                        location: "MeView.swift:request.bundleInfo",
                        message: "bundle id + simulator environment",
                        data: [
                            "bundleId": Bundle.main.bundleIdentifier ?? "nil",
                            "isSimulator": isSimulator,
                        ]
                    )
                    // #endregion

                    let nonceHashPrefix = request.nonce.map { String($0.prefix(8)) } ?? "nil"
                    let requestedScopes = request.requestedScopes ?? []

                    // #region agent log
                    agentDebugLog(
                        hypothesisId: "H3_request_configuration_scopes_nonce",
                        location: "MeView.swift:request.scopesAndNonce",
                        message: "scopes and nonce hash presence",
                        data: [
                            "hasEmailScope": requestedScopes.contains(.email) ? "true" : "false",
                            "hasFullNameScope": requestedScopes.contains(.fullName) ? "true" : "false",
                            "nonceHashPrefix": nonceHashPrefix,
                        ]
                    )
                    // #endregion
                } onCompletion: { result in
                    switch result {
                    case .success(let authResults):
                        guard let credential = authResults.credential as? ASAuthorizationAppleIDCredential else {
                            // #region agent log
                            agentDebugLog(
                                hypothesisId: "H4_apple_credential_type_mismatch",
                                location: "MeView.swift:onCompletion.success.cast",
                                message: "credential not ASAuthorizationAppleIDCredential",
                                data: [:]
                            )
                            // #endregion
                            return
                        }

                        guard let idTokenData = credential.identityToken else {
                            // #region agent log
                            agentDebugLog(
                                hypothesisId: "H4_apple_identity_token_missing",
                                location: "MeView.swift:onCompletion.success.identityToken",
                                message: "identityToken was nil",
                                data: [:]
                            )
                            // #endregion
                            return
                        }

                        guard let idToken = String(data: idTokenData, encoding: .utf8) else {
                            // #region agent log
                            agentDebugLog(
                                hypothesisId: "H4_apple_identity_token_encoding_failed",
                                location: "MeView.swift:onCompletion.success.identityTokenString",
                                message: "identityToken could not be decoded as UTF-8 string",
                                data: [:]
                            )
                            // #endregion
                            return
                        }

                        let fullName: String? = {
                            guard let full = credential.fullName else { return nil }
                            let parts = [full.givenName, full.middleName, full.familyName].compactMap { $0 }
                            return parts.isEmpty ? nil : parts.joined(separator: " ")
                        }()

                        Task {
                            do {
                                try await viewModel.signInWithApple(
                                    idToken: idToken,
                                    nonce: rawNonce,
                                    fullName: fullName
                                )
                                signInErrorMessage = nil
                            } catch {
                                signInErrorMessage = error.localizedDescription
                                await MainActor.run { viewModel.user = nil }
                            }
                        }
                    case .failure(let error):
                        // #region agent log
                        agentDebugLog(
                            hypothesisId: "H2_bundle_id_or_simulator_environment",
                            location: "MeView.swift:onCompletion.failure",
                            message: "Sign in with Apple credential request failed",
                            data: [
                                "error": String(describing: error),
                            ]
                        )
                        // #endregion
                        Task { @MainActor in
                            #if targetEnvironment(simulator)
                            signInErrorMessage =
                                "Sign in with Apple failed on Simulator (AuthorizationError 1000). Try on a physical iPhone/iPad signed into Apple ID, or add an iCloud account to this Simulator."
                            #else
                            signInErrorMessage = error.localizedDescription
                            #endif
                            viewModel.user = nil
                        }
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 44)

                if let signInErrorMessage {
                    Text(signInErrorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 8)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Learning language")
                    .font(.system(size: 14, weight: .semibold))
                Picker("Learning language", selection: $viewModel.learningLanguage) {
                    ForEach(Language.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 92)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: viewModel.user) { _, newValue in
            appViewModel.authUser = newValue
        }
        .onChange(of: viewModel.learningLanguage) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: "lingodex_learning_language")
        }
    }
}

private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    let charset: [Character] =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var randomBytes = [UInt8](repeating: 0, count: length)
    let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
    if status != errSecSuccess {
        // Fallback for MVP if entropy fails.
        return UUID().uuidString
    }
    return randomBytes.map { byte in charset[Int(byte) % charset.count] }.map(String.init).joined()
}

private func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashedData = SHA256.hash(data: inputData)
    return hashedData.map { String(format: "%02x", $0) }.joined()
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

