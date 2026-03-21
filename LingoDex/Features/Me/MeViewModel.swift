import Foundation
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable final class MeViewModel {
    private let deps: Dependencies

    var user: AuthUser?
    var nativeLanguage: Language = .english
    var learningLanguage: Language = .english
    var profileName: String = "Learner"
    var profileImage: UIImage?
    var remindersTime: Date = Date()
    var reminderFrequency: ReminderFrequency = .daily
    var notificationPermission: UNAuthorizationStatus = .notDetermined
    var totalObjectsCaptured: Int = 0
    var totalStoriesLearned: Int = 0
    var memberSinceYear: Int = Calendar.current.component(.year, from: Date())

    private let learningLanguageKey = "lingodex_learning_language"
    private let nativeLanguageKey = "lingodex_native_language"
    private let profileNameKey = "lingodex_profile_name"
    private let profileImageKey = "lingodex_profile_image_data"
    private let reminderHourKey = "lingodex_reminder_hour"
    private let reminderMinuteKey = "lingodex_reminder_minute"
    private let reminderFrequencyKey = "lingodex_reminder_frequency"
    private let memberSinceYearKey = "lingodex_member_since_year"
    private let reminderRequestPrefix = "lingodex_reminder_"
    // Replace with the real App Store app id when available.
    private let appStoreAppId = "0000000000"

    init(deps: Dependencies) {
        self.deps = deps
        self.user = deps.auth.currentUser
        if let systemLang = Locale.current.languageCode {
            nativeLanguage = Self.languageFromSystemCode(systemLang)
        }
        Task { await hydratePersistedStateAsync() }
    }

    /// Loads dynamic profile counts from local persisted capture sessions.
    func refreshStats() async {
        do {
            let sessions = try await deps.localStore.loadSessions()
            totalObjectsCaptured = sessions.reduce(0) { $0 + $1.words.count }
            // Stories persistence is not implemented yet in the store.
            totalStoriesLearned = 0
        } catch {
            totalObjectsCaptured = 0
        }
    }

    /// Refreshes the currently resolved notification permission status.
    func refreshNotificationPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationPermission = settings.authorizationStatus
    }

    /// Requests push notification authorization and returns the latest status.
    func requestNotificationPermissionIfNeeded() async -> UNAuthorizationStatus {
        if notificationPermission == .notDetermined {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                // No-op: we still return the latest status below.
            }
        }
        await refreshNotificationPermission()
        return notificationPermission
    }

    /// Saves reminder values and schedules local notifications accordingly.
    func saveReminders(time: Date, frequency: ReminderFrequency) async {
        remindersTime = time
        reminderFrequency = frequency
        persistReminderSettings()
        await scheduleReminderNotifications()
    }

    /// Persists selected profile image for future launches.
    func saveProfileImage(_ image: UIImage) {
        profileImage = image
        if let data = image.jpegData(compressionQuality: 0.82) {
            UserDefaults.standard.set(data, forKey: profileImageKey)
        }
    }

    /// Persists profile name and updates visible user name.
    func saveProfileName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profileName = trimmed
        if user != nil {
            user?.displayName = trimmed
        }
        UserDefaults.standard.set(trimmed, forKey: profileNameKey)
    }

    /// Persists native and learning language selections.
    func saveLanguages(native: Language, learning: Language) {
        nativeLanguage = native
        learningLanguage = learning
        UserDefaults.standard.set(native.rawValue, forKey: nativeLanguageKey)
        UserDefaults.standard.set(learning.rawValue, forKey: learningLanguageKey)
    }

    /// Opens App Store review page for this app.
    func openRateAppPage() {
        guard let url = URL(string: "itms-apps://itunes.apple.com/app/id\(appStoreAppId)?action=write-review") else { return }
        Task { @MainActor in
            UIApplication.shared.open(url)
        }
    }

    /// Returns a flag emoji for a language card preview.
    func flag(for language: Language) -> String {
        switch language {
        case .english: return "🇺🇸"
        case .french: return "🇫🇷"
        case .spanish: return "🇪🇸"
        case .mandarinChinese: return "🇨🇳"
        case .japanese: return "🇯🇵"
        case .korean: return "🇰🇷"
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
        refreshProfileName()
    }

    func signOut() async {
        do {
            try await deps.auth.signOut()
            user = nil
            refreshProfileName()
        } catch {
            // No-op for MVP.
        }
    }

    /// Loads persisted state asynchronously; profile image is decoded off main thread.
    private func hydratePersistedStateAsync() async {
        let savedName = UserDefaults.standard.string(forKey: profileNameKey)
        let savedNative = UserDefaults.standard.string(forKey: nativeLanguageKey)
        let savedLearning = UserDefaults.standard.string(forKey: learningLanguageKey)
        let imageData = UserDefaults.standard.data(forKey: profileImageKey)
        let savedHour = UserDefaults.standard.integer(forKey: reminderHourKey)
        let savedMinute = UserDefaults.standard.integer(forKey: reminderMinuteKey)
        let savedFrequency = UserDefaults.standard.string(forKey: reminderFrequencyKey)
        let savedMemberYear = UserDefaults.standard.integer(forKey: memberSinceYearKey)

        let decodedImage: UIImage? = await Task.detached(priority: .userInitiated) {
            guard let imageData, let img = UIImage(data: imageData) else { return nil }
            return img
        }.value

        if let savedName, !savedName.isEmpty { profileName = savedName }
        else { profileName = user?.displayName ?? "Learner" }

        if let savedNative, let lang = Language(rawValue: savedNative) { nativeLanguage = lang }
        if let savedLearning, let lang = Language(rawValue: savedLearning) { learningLanguage = lang }
        if let decodedImage { profileImage = decodedImage }

        if savedHour >= 0, savedHour < 24, savedMinute >= 0, savedMinute < 60 {
            remindersTime = Calendar.current.date(
                bySettingHour: savedHour,
                minute: savedMinute,
                second: 0,
                of: Date()
            ) ?? remindersTime
        }
        if let savedFrequency, let parsed = ReminderFrequency(rawValue: savedFrequency) {
            reminderFrequency = parsed
        }
        if savedMemberYear > 1900 {
            memberSinceYear = savedMemberYear
        } else {
            UserDefaults.standard.set(memberSinceYear, forKey: memberSinceYearKey)
        }
    }

    private func refreshProfileName() {
        if let savedName = UserDefaults.standard.string(forKey: profileNameKey), !savedName.isEmpty {
            profileName = savedName
            return
        }
        profileName = user?.displayName ?? "Learner"
    }

    private func persistReminderSettings() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: remindersTime)
        UserDefaults.standard.set(comps.hour ?? 20, forKey: reminderHourKey)
        UserDefaults.standard.set(comps.minute ?? 0, forKey: reminderMinuteKey)
        UserDefaults.standard.set(reminderFrequency.rawValue, forKey: reminderFrequencyKey)
    }

    private func scheduleReminderNotifications() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: reminderIdentifiers)

        guard notificationPermission == .authorized || notificationPermission == .provisional else { return }

        let comps = Calendar.current.dateComponents([.hour, .minute], from: remindersTime)
        let hour = comps.hour ?? 20
        let minute = comps.minute ?? 0

        let title = "Time to practice"
        let body = "Review your learned vocabulary in LingoDex."

        switch reminderFrequency {
        case .daily:
            var triggerComponents = DateComponents()
            triggerComponents.hour = hour
            triggerComponents.minute = minute
            await addReminderRequest(id: "\(reminderRequestPrefix)daily", title: title, body: body, components: triggerComponents)
        case .weekdays:
            for weekday in 2...6 {
                var triggerComponents = DateComponents()
                triggerComponents.weekday = weekday
                triggerComponents.hour = hour
                triggerComponents.minute = minute
                await addReminderRequest(
                    id: "\(reminderRequestPrefix)weekday_\(weekday)",
                    title: title,
                    body: body,
                    components: triggerComponents
                )
            }
        case .mondayWednesdayFriday:
            for weekday in [2, 4, 6] {
                var triggerComponents = DateComponents()
                triggerComponents.weekday = weekday
                triggerComponents.hour = hour
                triggerComponents.minute = minute
                await addReminderRequest(
                    id: "\(reminderRequestPrefix)mwf_\(weekday)",
                    title: title,
                    body: body,
                    components: triggerComponents
                )
            }
        }
    }

    private var reminderIdentifiers: [String] {
        [
            "\(reminderRequestPrefix)daily",
            "\(reminderRequestPrefix)weekday_2",
            "\(reminderRequestPrefix)weekday_3",
            "\(reminderRequestPrefix)weekday_4",
            "\(reminderRequestPrefix)weekday_5",
            "\(reminderRequestPrefix)weekday_6",
            "\(reminderRequestPrefix)mwf_2",
            "\(reminderRequestPrefix)mwf_4",
            "\(reminderRequestPrefix)mwf_6",
        ]
    }

    private func addReminderRequest(id: String, title: String, body: String, components: DateComponents) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
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

enum ReminderFrequency: String, CaseIterable, Identifiable {
    case daily
    case weekdays
    case mondayWednesdayFriday

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .mondayWednesdayFriday: return "Mon / Wed / Fri"
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

