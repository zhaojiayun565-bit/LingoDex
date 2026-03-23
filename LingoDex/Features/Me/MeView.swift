import SwiftUI
import AuthenticationServices
import CryptoKit
import Security
import Foundation
import LocalAuthentication
import UIKit
import UserNotifications

struct MeView: View {
    private let deps: Dependencies
    private let appViewModel: AppViewModel
    @State private var viewModel: MeViewModel
    @State private var rawNonce: String?
    @State private var signInErrorMessage: String?
    @State private var isShowingPhotoPicker = false
    @State private var activeModal: MeModalType?
    @State private var draftName: String = ""
    @State private var draftNativeLanguage: Language = .english
    @State private var draftLearningLanguage: Language = .english
    @State private var draftReminderTime: Date = Date()
    @State private var draftReminderFrequency: ReminderFrequency = .daily
    @FocusState private var isNameFieldFocused: Bool
    @FocusState private var keyboardWarmUpFocused: Bool

    init(deps: Dependencies, appViewModel: AppViewModel) {
        self.deps = deps
        self.appViewModel = appViewModel
        _viewModel = State(initialValue: MeViewModel(deps: deps))
    }

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Me")
                        .font(.system(size: 32, weight: .regular, design: .monospaced))
                        .foregroundStyle(DesignTokens.colors.capturesTextPrimary)
                        .padding(.bottom, 4)

                    if viewModel.user != nil {
                        profileSummaryCard
                        infoCardsRow
                        actionRows
                    } else {
                        signedOutCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 100)
            }
            if viewModel.user != nil {
                modalContent(for: .editName)
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if let activeModal {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture {
                        self.activeModal = nil
                        isNameFieldFocused = false
                    }
                modalContent(for: activeModal)
                    .padding(.horizontal, 34)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(2)
            }
            TextField("", text: .constant(""))
                .frame(width: 0, height: 0)
                .opacity(0)
                .focused($keyboardWarmUpFocused)
        }
        .sheet(isPresented: $isShowingPhotoPicker) {
            CapturePhotoPicker(
                isPresented: $isShowingPhotoPicker,
                onImagePicked: { image in
                    viewModel.saveProfileImage(image)
                }
            )
        }
        .onChange(of: viewModel.user) { _, _ in
            draftName = viewModel.profileName
        }
        .task {
            draftName = viewModel.profileName
            draftNativeLanguage = viewModel.nativeLanguage
            draftLearningLanguage = viewModel.learningLanguage
            draftReminderTime = viewModel.remindersTime
            draftReminderFrequency = viewModel.reminderFrequency
            await viewModel.refreshStats()
            await viewModel.refreshNotificationPermission()
            if viewModel.user != nil {
                try? await Task.sleep(for: .seconds(0.5))
                keyboardWarmUpFocused = true
                try? await Task.sleep(for: .milliseconds(100))
                keyboardWarmUpFocused = false
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.88), value: activeModal)
    }
}

private extension MeView {
    var profileSummaryCard: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 10) {
                Button {
                    isShowingPhotoPicker = true
                } label: {
                    avatarView(size: 106)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit profile photo")

                Button {
                    draftName = viewModel.profileName
                    activeModal = .editName
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isNameFieldFocused = true
                    }
                } label: {
                    Text(viewModel.profileName)
                        .font(.system(size: 16, weight: .regular, design: .monospaced))
                        .foregroundStyle(DesignTokens.colors.capturesTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(.plain)

                Text("Tap for\nreferral link")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(DesignTokens.colors.capturesTextSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                profileStat(label: "Objects captured", value: "\(viewModel.totalObjectsCaptured)")
                profileStat(label: "Stories learned", value: "\(viewModel.totalStoriesLearned)")
                profileStat(label: "Member since", value: "\(viewModel.memberSinceYear)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DesignTokens.colors.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    var infoCardsRow: some View {
        HStack(spacing: 16) {
            Button {
                draftNativeLanguage = viewModel.nativeLanguage
                draftLearningLanguage = viewModel.learningLanguage
                activeModal = .languages
            } label: {
                VStack(spacing: 10) {
                    HStack(spacing: -3) {
                        flagBadge(text: viewModel.flag(for: viewModel.nativeLanguage), rotation: -12)
                        flagBadge(text: "↔", rotation: 0)
                        flagBadge(text: viewModel.flag(for: viewModel.learningLanguage), rotation: 12)
                    }
                    .frame(height: 46)
                    Text("Languages")
                        .font(.system(size: 16, weight: .regular, design: .monospaced))
                        .foregroundStyle(DesignTokens.colors.capturesTextPrimary)
                }
                .frame(maxWidth: .infinity, minHeight: 130)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(DesignTokens.colors.cardStroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {} label: {
                VStack(spacing: 10) {
                    HStack(spacing: -8) {
                        miniAvatar(offset: -2)
                        miniAvatar(offset: 0)
                        miniAvatar(offset: 2)
                    }
                    .frame(height: 46)
                    Text("Friends")
                        .font(.system(size: 16, weight: .regular, design: .monospaced))
                        .foregroundStyle(DesignTokens.colors.capturesTextPrimary)
                }
                .frame(maxWidth: .infinity, minHeight: 130)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(DesignTokens.colors.cardStroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    var actionRows: some View {
        VStack(spacing: 18) {
            MeActionRow(title: "Reminders", icon: "bell") {
                Task {
                    _ = await viewModel.requestNotificationPermissionIfNeeded()
                    draftReminderTime = viewModel.remindersTime
                    draftReminderFrequency = viewModel.reminderFrequency
                    activeModal = .reminders
                }
            }
            MeActionRow(title: "Get premium FREE", icon: "diamond") {}

            Divider().padding(.vertical, 2)

            MeActionRow(title: "FAQs", icon: "questionmark.circle") {}
            MeActionRow(title: "Terms & conditions", icon: "newspaper") {}
            MeActionRow(title: "Privacy policy", icon: "lock") {}
            MeActionRow(title: "Contact support", icon: "envelope") {}

            Divider().padding(.vertical, 2)

            MeActionRow(title: "Rate the app", icon: "star") {
                viewModel.openRateAppPage()
            }

            MeActionRow(title: "Log out", icon: "rectangle.portrait.and.arrow.right", showsChevron: false) {
                Task { await viewModel.signOut() }
            }
        }
        .padding(.top, 8)
    }

    var signedOutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign in to save your captures and learning progress.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

#if DEBUG
            Button {
                viewModel.setDebugUser(AuthUser(id: "debug-test-user", displayName: "Tester"))
                signInErrorMessage = nil
            } label: {
                Text("Continue in Test Mode")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(DesignTokens.colors.primary)
#endif

            signInWithAppleButton

            if let signInErrorMessage {
                Text(signInErrorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DesignTokens.colors.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    var signInWithAppleButton: some View {
        SignInWithAppleButton { request in
            let nonce = randomNonceString()
            rawNonce = nonce
            request.requestedScopes = [.email, .fullName]
            request.nonce = sha256(nonce)

            let laContext = LAContext()
            var laError: NSError?
            let canEvaluate = laContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &laError)

            agentDebugLog(
                hypothesisId: "H1_passcode_or_secure_auth_prereq",
                location: "MeView.swift:request.canEvaluatePolicy",
                message: "deviceOwnerAuthentication canEvaluatePolicy result",
                data: [
                    "canEvaluate": canEvaluate ? "true" : "false",
                    "laErrorCode": String(laError?.code ?? -1),
                ]
            )

            #if targetEnvironment(simulator)
            let isSimulator = "true"
            #else
            let isSimulator = "false"
            #endif

            agentDebugLog(
                hypothesisId: "H2_bundle_id_or_simulator_environment",
                location: "MeView.swift:request.bundleInfo",
                message: "bundle id + simulator environment",
                data: [
                    "bundleId": Bundle.main.bundleIdentifier ?? "nil",
                    "isSimulator": isSimulator,
                ]
            )

            let nonceHashPrefix = request.nonce.map { String($0.prefix(8)) } ?? "nil"
            let requestedScopes = request.requestedScopes ?? []

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
        } onCompletion: { result in
            switch result {
            case .success(let authResults):
                guard let credential = authResults.credential as? ASAuthorizationAppleIDCredential else {
                    agentDebugLog(
                        hypothesisId: "H4_apple_credential_type_mismatch",
                        location: "MeView.swift:onCompletion.success.cast",
                        message: "credential not ASAuthorizationAppleIDCredential",
                        data: [:]
                    )
                    return
                }

                guard let idTokenData = credential.identityToken else {
                    agentDebugLog(
                        hypothesisId: "H4_apple_identity_token_missing",
                        location: "MeView.swift:onCompletion.success.identityToken",
                        message: "identityToken was nil",
                        data: [:]
                    )
                    return
                }

                guard let idToken = String(data: idTokenData, encoding: .utf8) else {
                    agentDebugLog(
                        hypothesisId: "H4_apple_identity_token_encoding_failed",
                        location: "MeView.swift:onCompletion.success.identityTokenString",
                        message: "identityToken could not be decoded as UTF-8 string",
                        data: [:]
                    )
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
                    }
                }
            case .failure(let error):
                agentDebugLog(
                    hypothesisId: "H2_bundle_id_or_simulator_environment",
                    location: "MeView.swift:onCompletion.failure",
                    message: "Sign in with Apple credential request failed",
                    data: [
                        "error": String(describing: error),
                    ]
                )
                Task { @MainActor in
                    #if targetEnvironment(simulator)
                    signInErrorMessage =
                        "Sign in with Apple failed on Simulator (AuthorizationError 1000). Try on a physical iPhone/iPad signed into Apple ID, or add an iCloud account to this Simulator."
                    #else
                    signInErrorMessage = error.localizedDescription
                    #endif
                }
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 44)
    }

    @ViewBuilder
    func modalContent(for modalType: MeModalType) -> some View {
        switch modalType {
        case .editName:
            MeModalCardContainer {
                VStack(spacing: 20) {
                    avatarView(size: 96)
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DesignTokens.colors.capturesTextPrimary)
                        .focused($isNameFieldFocused)
                    modalButtons(
                        onSave: {
                            viewModel.saveProfileName(draftName)
                            activeModal = nil
                            isNameFieldFocused = false
                        },
                        onCancel: {
                            draftName = viewModel.profileName
                            activeModal = nil
                            isNameFieldFocused = false
                        }
                    )
                }
            }
        case .languages:
            MeModalCardContainer {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Languages")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .center)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Native language")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Picker("Native language", selection: $draftNativeLanguage) {
                            ForEach(Language.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Learning language")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Picker("Learning language", selection: $draftLearningLanguage) {
                            ForEach(Language.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    modalButtons(
                        onSave: {
                            viewModel.saveLanguages(native: draftNativeLanguage, learning: draftLearningLanguage)
                            activeModal = nil
                        },
                        onCancel: {
                            draftNativeLanguage = viewModel.nativeLanguage
                            draftLearningLanguage = viewModel.learningLanguage
                            activeModal = nil
                        }
                    )
                }
            }
        case .reminders:
            MeModalCardContainer {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Reminders")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .center)

                    if viewModel.notificationPermission == .denied {
                        Text("Notifications are currently disabled in iOS Settings.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    DatePicker("Preferred time", selection: $draftReminderTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)

                    Picker("Frequency", selection: $draftReminderFrequency) {
                        ForEach(ReminderFrequency.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    modalButtons(
                        onSave: {
                            Task {
                                await viewModel.saveReminders(
                                    time: draftReminderTime,
                                    frequency: draftReminderFrequency
                                )
                                activeModal = nil
                            }
                        },
                        onCancel: {
                            draftReminderTime = viewModel.remindersTime
                            draftReminderFrequency = viewModel.reminderFrequency
                            activeModal = nil
                        }
                    )
                }
            }
        }
    }

    func avatarView(size: CGFloat) -> some View {
        Group {
            if let image = viewModel.profileImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.15)
                    .foregroundStyle(Color.gray.opacity(0.55))
                    .background(Color.gray.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    func miniAvatar(offset: CGFloat) -> some View {
        avatarView(size: 34)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .offset(x: offset)
    }

    func profileStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .foregroundStyle(DesignTokens.colors.capturesTextSecondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignTokens.colors.capturesTextPrimary)
        }
    }

    func flagBadge(text: String, rotation: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 32))
            .rotationEffect(.degrees(rotation))
    }

    func modalButtons(onSave: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        SaveCancelButtons(onSave: onSave, onCancel: onCancel)
    }
}

private struct MeActionRow: View {
    let title: String
    let icon: String
    var showsChevron: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .regular))
                        .frame(width: 24, height: 24)
                    Text(title)
                        .font(.system(size: 16, weight: .regular, design: .monospaced))
                }
                .foregroundStyle(DesignTokens.colors.capturesTextPrimary)
                Spacer()
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DesignTokens.colors.capturesTextSecondary.opacity(0.8))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MeModalCardContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack {
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: 340)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(DesignTokens.colors.cardStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 4)
    }
}

private enum MeModalType: Identifiable {
    case editName
    case languages
    case reminders

    var id: String {
        switch self {
        case .editName: return "edit_name"
        case .languages: return "languages"
        case .reminders: return "reminders"
        }
    }
}

private extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        self = Color(red: r, green: g, blue: b)
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

