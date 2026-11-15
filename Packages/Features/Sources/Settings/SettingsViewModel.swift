import Foundation
import Observation
import PlayerKit
import StremioKit

/// Settings: default subtitle language, preferred quality, streaming server, clear data.
@MainActor
@Observable
final class SettingsViewModel {
    struct Option<Value: Hashable>: Hashable, Identifiable {
        let label: String
        let value: Value
        var id: String { label }
    }

    static let resolutionOptions: [Option<Int?>] = [
        .init(label: "Best available", value: nil), .init(label: "4K (2160p)", value: 2160), .init(label: "1080p", value: 1080),
        .init(label: "720p", value: 720), .init(label: "480p", value: 480),
    ]

    static var languageOptions: [Option<String?>] {
        [.init(label: "Off", value: nil)] + LanguageCodes.all.map { .init(label: $0.name, value: $0.code) }
    }

    static let continueWatchingRefreshOptions: [Option<Int>] = [
        .init(label: "Manually", value: 0), .init(label: "Every minute", value: 60),
        .init(label: "Every 5 minutes", value: 300), .init(label: "Every 15 minutes", value: 900),
        .init(label: "Every 30 minutes", value: 1800),
    ]

    private(set) var settings = PlaybackSettings()
    var serverURLText = ""
    var openSubtitlesAPIKeyText = ""
    var openSubtitlesUsernameText = ""
    var openSubtitlesPasswordText = ""
    /// Every installed addon, disabled ones included.
    private(set) var installedAddonCount = 0
    /// Each installed addon's name, for the Addon Speed row's summary.
    private(set) var addonNames: [UUID: String] = [:]
    private(set) var lastMessage: String?
    private(set) var isClearingData = false
    private(set) var isSigningInToOpenSubtitles = false
    private var verifiedOpenSubtitlesCredentials: OpenSubtitlesCredentials?
    /// OMDb requests this device has sent today (UTC). `refreshOMDbUsage()` updates it.
    private(set) var omdbRequestsToday = 0
    static let omdbDailyLimit = OMDbUsage.dailyLimit

    private let services: AppServices
    private let reset: DataResetService
    private var mutationRevision = 0

    private func update(_ change: @escaping SettingsMutation) async {
        mutationRevision += 1
        let revision = mutationRevision
        let saved = await services.settings.update(change)
        if revision == mutationRevision { settings = saved }
    }

    init(services: AppServices) {
        self.services = services
        self.reset = DataResetService(services: services)
    }

    var fallbackEngineLinked: Bool { services.fallbackEngineLinked }
    var serverURLMessage: String? { PlaybackSettings.validationMessage(forServerURL: serverURLText) }

    var subtitleSummary: String {
        SubtitleDefaults.summary(language: settings.subtitleLanguage, mode: settings.player.subtitleMode)
    }

    private var openSubtitlesCredentials: OpenSubtitlesCredentials? {
        guard let key = settings.openSubtitlesAPIKey, !key.isEmpty else { return nil }
        return OpenSubtitlesCredentials(apiKey: key, username: settings.openSubtitlesUsername, password: settings.openSubtitlesPassword)
    }

    var openSubtitlesSummary: String {
        guard let credentials = openSubtitlesCredentials else { return "Not set up" }
        guard credentials.hasLogin else { return "Key saved" }
        return credentials == verifiedOpenSubtitlesCredentials ? "Signed in" : "Credentials saved"
    }

    var canSignInToOpenSubtitles: Bool {
        guard let credentials = openSubtitlesCredentials else { return false }
        return credentials.hasLogin
            && credentials.apiKey == openSubtitlesAPIKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
            && credentials.username == openSubtitlesUsernameText.trimmingCharacters(in: .whitespacesAndNewlines)
            && credentials.password == openSubtitlesPasswordText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func signInToOpenSubtitles() async {
        guard canSignInToOpenSubtitles, !isSigningInToOpenSubtitles, let credentials = openSubtitlesCredentials else { return }
        isSigningInToOpenSubtitles = true
        verifiedOpenSubtitlesCredentials = nil
        lastMessage = nil
        defer { isSigningInToOpenSubtitles = false }
        do {
            try await OpenSubtitlesClient(client: services.client, credentials: credentials).signIn()
            // A save or reset during the request must not verify different credentials.
            guard credentials == openSubtitlesCredentials else { return }
            verifiedOpenSubtitlesCredentials = credentials
            lastMessage = "Signed in to OpenSubtitles."
        } catch {
            lastMessage = "Couldn’t sign in to OpenSubtitles. Check the saved key and credentials, then try again."
        }
    }

    func load() async {
        settings = await services.settings.load()
        #if canImport(UIKit)
        Haptics.apply(settings.haptics)
        #endif
        serverURLText = settings.streamingServerURL ?? ""
        openSubtitlesAPIKeyText = settings.openSubtitlesAPIKey ?? ""
        openSubtitlesUsernameText = settings.openSubtitlesUsername ?? ""
        openSubtitlesPasswordText = settings.openSubtitlesPassword ?? ""
        services.posterRatings.apply(AppearancePreferences.saved())
        let addons = await services.registry.addons
        installedAddonCount = addons.count
        addonNames = Dictionary(addons.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        refreshOMDbUsage()
    }

    func refreshOMDbUsage() {
        omdbRequestsToday = OMDbUsage.shared.today()
    }

    func setPreferredResolution(_ value: Int?) async {
        await update { $0.preferredResolution = value }
    }

    func setDataSaverLevel(_ level: DataSaverLevel) async {
        await update { $0.dataSaverLevel = level }
    }

    func setSubtitleLanguage(_ code: String?) async {
        await update { $0.subtitleLanguage = code }
    }

    /// Player preferences (subtitle, audio, picture and gesture defaults). The player saves changes made during playback the same way.
    func updatePlayer(_ change: @escaping @MainActor @Sendable (inout PlayerPreferences) -> Void) async {
        await update { change(&$0.player) }
    }

    /// The Haptics page's tuning. Saved as it changes and applied at once, so the next tap is the one being tuned.
    func updateHaptics(_ change: @escaping @MainActor @Sendable (inout HapticPreferences) -> Void) async {
        await update { change(&$0.haptics) }
        #if canImport(UIKit)
        Haptics.apply(settings.haptics)
        #endif
    }

    /// Saves the OpenSubtitles API key and login as typed; blank fields remove them.
    func commitOpenSubtitles() async {
        func trimmed(_ text: String) -> String? {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        let key = trimmed(openSubtitlesAPIKeyText)
        let username = trimmed(openSubtitlesUsernameText)
        let password = trimmed(openSubtitlesPasswordText)
        await update {
            $0.openSubtitlesAPIKey = key
            $0.openSubtitlesUsername = username
            $0.openSubtitlesPassword = password
        }
        let saved = await services.settings.load()
        settings = saved
        if openSubtitlesCredentials != verifiedOpenSubtitlesCredentials { verifiedOpenSubtitlesCredentials = nil }
        lastMessage = saved.openSubtitlesAPIKey == key && saved.openSubtitlesUsername == username && saved.openSubtitlesPassword == password
            ? "OpenSubtitles saved." : "Some OpenSubtitles credentials could not be saved to secure storage. Try again."
    }

    /// No "file's default": the player picks English when nothing else is chosen (`PlayerPreferences.defaultAudioLanguage`).
    static var audioLanguageOptions: [Option<String?>] {
        LanguageCodes.all.map { .init(label: $0.name, value: $0.code) }
    }

    func setFallbackEngineEnabled(_ enabled: Bool) async {
        await update { $0.fallbackEngineEnabled = enabled }
    }

    func setPlayerPreference(_ value: PlayerPreference) async {
        await update { $0.playerPreference = value }
    }

    func setAutoPlayBestStream(_ value: Bool) async {
        await update { $0.autoPlayBestStream = value }
    }

    func setAutoPickSource(_ value: StreamSourcePreference) async {
        await update { $0.autoPickSource = value }
    }

    func setContinueWatchingRefreshSeconds(_ value: Int) async {
        await update { $0.continueWatchingRefreshSeconds = value }
    }

    func refreshRatings() async {
        await services.posterRatings.refresh()
        lastMessage = "Ratings will refresh as you browse."
    }

    /// Saves the streaming server field if it is empty or valid; otherwise leaves the stored value alone.
    func commitServerURL() async {
        guard serverURLMessage == nil else { return }
        let trimmed = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        await update { $0.streamingServerURL = trimmed.isEmpty ? nil : trimmed }
    }

    /// Clears the last confirmation, so a page opened later does not show another page's message.
    func clearMessage() {
        lastMessage = nil
    }

    func clear(_ scope: DataResetService.Scope) async {
        guard !isClearingData else { return }
        isClearingData = true
        defer { isClearingData = false }
        lastMessage = await reset.clear(scope)
        await load()
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let count = info?["BlusionCommitCount"] as? String ?? "0"
        return "v.\(count)"
    }
}
