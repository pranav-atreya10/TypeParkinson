import AuthenticationServices
import Foundation
import Observation

enum Phrases {
    static let exercise = "meet me at the library at noon"
    static let standardRound = "the dog ran past the old mill"
    static let personalRound = "a cup of tea sits by the door"
}

struct TypingOutcome: Equatable {
    var phrase: PhraseResult
    /// Taps the offset moved onto the expected key, and off it.
    var corrected = 0
    var hurt = 0
    var blockedRepeats = 0
    var ignoredBrushes = 0
    /// Words smart correction fixed.
    var autoCorrected = 0
    var taps = 0
}

struct CheckResult: Equatable {
    var standard: TypingOutcome
    var personal: TypingOutcome
}

@Observable
final class AppModel {
    enum Screen: String {
        case onboarding
        case account
        case welcome
        case exercises
        case recalibration
        case profile
        case proposal
        case check
        case compare
        case enable
        case home
        case recalResult
        case settings
    }

    var screen: Screen
    var hand: Hand = .right
    private(set) var profile: TouchProfile?
    /// The working copy being proposed or edited; the keyboard only sees it once approved.
    var settings: KeyboardSettings
    private(set) var checkResult: CheckResult?
    private(set) var todayTaps: [TapSample] = []
    private(set) var isSetupComplete: Bool
    /// The profile screen was opened from home rather than straight after the exercises.
    private(set) var isViewingSavedProfile = false
    /// Signed in with Apple; their profile and keyboard follow them through iCloud.
    private(set) var account: AppleAccount?
    /// A one-off message to show, e.g. after restoring from iCloud.
    var notice: String?
    /// When the profile or approved settings last changed, to pick the newer copy when syncing.
    private var modified: Date

    var simulateTremor: Bool
    var simulator: TremorSimulator { TremorSimulator(strength: simulateTremor ? 1 : 0) }

    /// Buttons render with the Liquid Glass material instead of the solid look.
    var liquidGlassEnabled: Bool {
        didSet { defaults.set(liquidGlassEnabled, forKey: Keys.liquidGlassEnabled) }
    }

    // MARK: Everyday features

    /// Which tab is showing once setup is done.
    var tab: AppTab = .today
    /// An activity Practice should open as soon as it appears (from Today, Siri or a shortcut).
    var practiceRequest: PracticeActivity?
    /// Check-ins and practice results, kept on this device.
    let activity: ActivityStore
    let speaker = Speaker()
    /// Saved phrases for Speak and the keyboard's Phrases button.
    private(set) var phrases: [QuickPhrase]
    /// Things said aloud recently in Speak, newest first.
    private(set) var recentlySpoken: [String]
    private(set) var reminderEnabled: Bool
    private(set) var reminderTime: DateComponents
    /// The person's medication schedule, for reminders and timing insights.
    private(set) var medications: [Medication]
    /// The medication sheet is open (from Today, or a reminder).
    var showingMedications = false

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let profile = "touchProfile"
        static let setupComplete = "setupComplete"
        static let accountStepComplete = "accountStepComplete"
        static let account = "appleAccount"
        static let modified = "modified"
        static let liquidGlassEnabled = "liquidGlassEnabled"
        static let reminderEnabled = "reminderEnabled"
        static let reminderHour = "reminderHour"
        static let reminderMinute = "reminderMinute"
        static let recentlySpoken = "recentlySpoken"
        static let medications = "medications"
    }

    init(activity: ActivityStore = .shared) {
        self.activity = activity
        self.phrases = SharedStore.loadPhrases() ?? QuickPhrase.starters
        self.recentlySpoken = UserDefaults.standard.stringArray(forKey: Keys.recentlySpoken) ?? []
        self.reminderEnabled = UserDefaults.standard.bool(forKey: Keys.reminderEnabled)
        var time = DateComponents()
        time.hour = UserDefaults.standard.object(forKey: Keys.reminderHour) as? Int ?? 9
        time.minute = UserDefaults.standard.object(forKey: Keys.reminderMinute) as? Int ?? 0
        self.reminderTime = time
        self.medications = UserDefaults.standard.data(forKey: Keys.medications)
            .flatMap { try? JSONDecoder().decode([Medication].self, from: $0) } ?? []
        let profile = defaults.data(forKey: Keys.profile)
            .flatMap { try? JSONDecoder().decode(TouchProfile.self, from: $0) }
        let complete = defaults.bool(forKey: Keys.setupComplete) && profile != nil
        self.profile = profile
        self.hand = profile?.hand ?? .right
        self.isSetupComplete = complete
        self.account = defaults.data(forKey: Keys.account)
            .flatMap { try? JSONDecoder().decode(AppleAccount.self, from: $0) }
        self.modified = defaults.object(forKey: Keys.modified) as? Date ?? .distantPast
        var settings = SharedStore.loadSettings() ?? profile?.proposedSettings() ?? KeyboardSettings()
        if settings.touchModel == nil, let profile, complete {
            // Approved before smart correction existed: give the keyboard this person's touch model.
            let estimate = PatternClassifier.classify(PatternClassifier.features(profile: profile, log: activity.log))
            settings.pattern = estimate.evidence >= 2 ? estimate.primary : nil
            settings.touchModel = TouchModel(taps: profile.taps, pattern: settings.pattern)
            SharedStore.save(settings)
        }
        self.settings = settings
        self.liquidGlassEnabled = defaults.bool(forKey: Keys.liquidGlassEnabled)
        if !defaults.bool(forKey: Keys.accountStepComplete) {
            self.screen = .onboarding
        } else {
            self.screen = complete ? .home : .welcome
        }
        #if DEBUG && targetEnvironment(simulator)
        self.simulateTremor = true
        #else
        self.simulateTremor = false
        #endif
        #if DEBUG
        // e.g. `-demoScreen proposal` opens that screen with sample data.
        if let name = defaults.string(forKey: "demoScreen"), let demo = Screen(rawValue: name) {
            loadDemo(demo)
        }
        #endif
    }

    // MARK: Onboarding and account

    func finishOnboarding() {
        screen = .account
    }

    func continueWithoutAccount() {
        finishAccountStep()
    }

    /// After Sign in with Apple succeeds: restores this person's keyboard from
    /// iCloud if they set it up on another device, otherwise saves this one there.
    func signedIn(with credential: ASAuthorizationAppleIDCredential) {
        let name = credential.fullName.flatMap {
            PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
        }.flatMap { $0.isEmpty ? nil : $0 }
        // Apple only shares the name the first time; keep the one we have after that.
        let account = AppleAccount(userID: credential.user,
                                   name: name ?? (self.account?.userID == credential.user ? self.account?.name : nil))
        self.account = account
        if let data = try? JSONEncoder().encode(account) {
            defaults.set(data, forKey: Keys.account)
        }

        if let remote = CloudStore.load(for: account),
           remote.isSetupComplete, remote.modified > modified || !isSetupComplete {
            apply(remote)
            notice = "Welcome back. Your keyboard was restored from iCloud."
        } else {
            pushToCloud()
        }
        if screen == .account { finishAccountStep() }
    }

    /// Stops syncing. Everything stays on this device.
    func signOut() {
        account = nil
        defaults.removeObject(forKey: Keys.account)
    }

    /// Deletes the account's iCloud copy and everything on this device, then starts over.
    func deleteAccountAndData() {
        if let account { CloudStore.remove(for: account) }
        deleteLocalData()
    }

    /// Deletes everything on this device and starts over.
    func deleteLocalData() {
        for key in [Keys.profile, Keys.setupComplete, Keys.accountStepComplete, Keys.account, Keys.modified,
                    Keys.reminderEnabled, Keys.reminderHour, Keys.reminderMinute, Keys.recentlySpoken, Keys.medications] {
            defaults.removeObject(forKey: key)
        }
        SharedStore.clear()
        activity.clear()
        Reminders.cancel()
        speaker.stop()
        phrases = QuickPhrase.starters
        recentlySpoken = []
        reminderEnabled = false
        medications = []
        Task { _ = await MedicationReminders.schedule([]) }
        tab = .today
        practiceRequest = nil
        account = nil
        profile = nil
        hand = .right
        settings = KeyboardSettings()
        checkResult = nil
        todayTaps = []
        isSetupComplete = false
        isViewingSavedProfile = false
        modified = .distantPast
        notice = nil
        screen = .onboarding
    }

    private func finishAccountStep() {
        defaults.set(true, forKey: Keys.accountStepComplete)
        screen = isSetupComplete ? .home : .welcome
    }

    // MARK: Sync

    /// Signs out if this Apple Account stopped allowing TypeParkinson
    /// (Settings › Apple Account › Sign in with Apple).
    func verifyAppleCredential() async {
        guard let account else { return }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: account.userID)
        if state == .revoked || state == .notFound, self.account == account {
            signOut()
            notice = "Sign in with Apple was turned off for TypeParkinson, so syncing has stopped. Your keyboard still works on this device."
        }
    }

    /// Applies changes made on the person's other devices for as long as the app runs.
    func observeCloudChanges() async {
        CloudStore.refresh()
        pullFromCloud()
        for await _ in NotificationCenter.default.notifications(named: NSUbiquitousKeyValueStore.didChangeExternallyNotification) {
            pullFromCloud()
        }
    }

    func observeCredentialRevocation() async {
        for await _ in NotificationCenter.default.notifications(named: ASAuthorizationAppleIDProvider.credentialRevokedNotification) {
            await verifyAppleCredential()
        }
    }

    func pullFromCloud() {
        guard let account, let remote = CloudStore.load(for: account),
              remote.isSetupComplete, remote.modified > modified else { return }
        // Don't swap the keyboard out from under someone part-way through setup or editing.
        guard [.home, .settings, .welcome].contains(screen) else { return }
        apply(remote)
    }

    private func apply(_ remote: CloudSnapshot) {
        profile = remote.profile
        hand = remote.profile?.hand ?? hand
        if let profile = remote.profile, let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Keys.profile)
        }
        if let approved = remote.settings {
            settings = approved
            SharedStore.save(approved)
        }
        isSetupComplete = remote.isSetupComplete
        defaults.set(remote.isSetupComplete, forKey: Keys.setupComplete)
        modified = remote.modified
        defaults.set(modified, forKey: Keys.modified)
        if isSetupComplete, screen == .welcome { screen = .home }
    }

    /// Records that the profile or approved keyboard changed, and syncs it.
    private func changed() {
        modified = .now
        defaults.set(modified, forKey: Keys.modified)
        pushToCloud()
    }

    private func pushToCloud() {
        guard let account, profile != nil else { return }
        CloudStore.save(CloudSnapshot(profile: profile, settings: SharedStore.loadSettings(),
                                      isSetupComplete: isSetupComplete, modified: modified),
                        for: account)
    }

    // MARK: Setup

    func startExercises() {
        screen = .exercises
    }

    /// The touch pattern from the exercises plus recent practice.
    var patternEstimate: TouchPatternEstimate? {
        guard let profile else { return nil }
        return PatternClassifier.classify(PatternClassifier.features(profile: profile, log: activity.log))
    }

    func finishExercises(_ newProfile: TouchProfile) {
        isViewingSavedProfile = false
        profile = newProfile
        let estimate = PatternClassifier.classify(PatternClassifier.features(profile: newProfile, log: activity.log))
        settings = newProfile.proposedSettings(pattern: estimate.evidence >= 2 ? estimate.primary : nil)
        checkResult = nil
        save(profile: newProfile)
        if newProfile.taps.count >= 3 {
            activity.add(CheckInRecord(taps: newProfile.taps, feeling: nil, adjustedKeyboard: false, isSetup: true))
        }
        changed()
        screen = .profile
    }

    func startCheck() {
        screen = .check
    }

    func finishCheck(_ result: CheckResult) {
        checkResult = result
        screen = .compare
    }

    /// Saves the working settings for the keyboard to use.
    func approve() {
        settings.todayOffset = nil
        SharedStore.save(settings)
        changed()
        screen = isSetupComplete ? .home : .enable
    }

    func finishSetup() {
        isSetupComplete = true
        defaults.set(true, forKey: Keys.setupComplete)
        changed()
        screen = .home
    }

    /// Drops unapproved edits and returns home.
    func cancelEditing() {
        settings = SharedStore.loadSettings() ?? settings
        screen = .home
    }

    func leaveSetup() {
        if isSetupComplete { cancelEditing() } else { screen = .welcome }
    }

    // MARK: Everyday use

    func viewProfile() {
        isViewingSavedProfile = true
        screen = .profile
    }

    func startRecalibration() {
        screen = .recalibration
    }

    func finishRecalibration(_ taps: [TapSample]) {
        todayTaps = taps
        screen = .recalResult
    }

    func applyToday(feeling: Feeling?) {
        let offset = todayTaps.meanOffset
        updateKeyboard { $0.todayOffset = .init(x: offset.dx, y: offset.dy, date: .now) }
        activity.add(CheckInRecord(taps: todayTaps, feeling: feeling, adjustedKeyboard: true))
        tab = .today
        screen = .home
    }

    func keepUsual(feeling: Feeling?) {
        activity.add(CheckInRecord(taps: todayTaps, feeling: feeling, adjustedKeyboard: false))
        tab = .today
        screen = .home
    }

    func clearToday() {
        updateKeyboard { $0.todayOffset = nil }
    }

    func open(_ tab: AppTab) {
        self.tab = tab
        screen = .home
    }

    func startPractice(_ activity: PracticeActivity) {
        practiceRequest = activity
        open(.practice)
    }

    /// Siri, Shortcuts and the reminder land here. Before setup is done, there's nothing to open.
    func follow(_ route: AppRouter.Route) {
        guard isSetupComplete, [.home, .settings, .profile, .recalResult].contains(screen) else { return }
        switch route {
        case .dailyCheck: startRecalibration()
        case .speak: open(.speak)
        case .practice(let activity): startPractice(activity)
        case .progress: open(.progress)
        case .medications:
            showingMedications = true
            open(.today)
        }
    }

    // MARK: Phrases and speech

    func savePhrases(_ phrases: [QuickPhrase]) {
        self.phrases = phrases
        SharedStore.save(phrases: phrases)
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        speaker.speak(trimmed)
        recentlySpoken.removeAll { $0 == trimmed }
        recentlySpoken.insert(trimmed, at: 0)
        recentlySpoken = Array(recentlySpoken.prefix(8))
        defaults.set(recentlySpoken, forKey: Keys.recentlySpoken)
    }

    func clearRecentlySpoken() {
        recentlySpoken = []
        defaults.removeObject(forKey: Keys.recentlySpoken)
    }

    // MARK: Medication

    /// Saves the schedule locally and reports whether its reminders were set.
    @discardableResult
    func saveMedications(_ medications: [Medication]) async -> MedicationReminders.ScheduleResult {
        self.medications = medications
        defaults.set(try? JSONEncoder().encode(medications), forKey: Keys.medications)
        return await MedicationReminders.schedule(medications)
    }

    func logDose(_ medication: Medication, at date: Date = .now) {
        activity.add(DoseRecord(date: date, medicationID: medication.id, name: medication.name))
    }

    /// Doses logged today, for each medication.
    func dosesToday(_ medication: Medication) -> [DoseRecord] {
        activity.log.doses.filter { $0.medicationID == medication.id && Calendar.current.isDateInToday($0.date) }
    }

    // MARK: Reminder

    /// Returns false when notifications are turned off for the app in Settings.
    @discardableResult
    func setReminder(enabled: Bool, time: DateComponents? = nil) async -> Bool {
        if let time {
            reminderTime = time
            defaults.set(time.hour ?? 9, forKey: Keys.reminderHour)
            defaults.set(time.minute ?? 0, forKey: Keys.reminderMinute)
        }
        guard enabled else {
            reminderEnabled = false
            defaults.set(false, forKey: Keys.reminderEnabled)
            Reminders.cancel()
            return true
        }
        let ok = await Reminders.schedule(hour: reminderTime.hour ?? 9, minute: reminderTime.minute ?? 0)
        reminderEnabled = ok
        defaults.set(ok, forKey: Keys.reminderEnabled)
        return ok
    }

    var todayOffset: KeyboardSettings.TodayOffset? {
        settings.todayOffset.flatMap { $0.isCurrent ? $0 : nil }
    }

    /// Changes the approved keyboard directly, for settings that don't need a new check.
    func updateKeyboard(_ change: (inout KeyboardSettings) -> Void) {
        var saved = SharedStore.loadSettings() ?? settings
        change(&saved)
        SharedStore.save(saved)
        settings = saved
        changed()
    }

    private func save(profile: TouchProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Keys.profile)
        }
    }
}

// MARK: - Demo data

#if DEBUG
/// Sample data for opening any screen directly from a launch argument, so each
/// screen can be checked without tapping through the whole flow.
extension AppModel {
    func loadDemo(_ demo: Screen) {
        let simulator = TremorSimulator(strength: 1)
        let profile = TouchProfile.sample
        self.profile = profile
        settings = profile.proposedSettings(pattern: PatternClassifier.classify(PatternClassifier.features(profile: profile)).primary)
        SharedStore.save(settings)
        checkResult = CheckResult(
            standard: TypingOutcome(phrase: PhraseResult(errors: 4, corrections: 6, time: 21.3)),
            personal: TypingOutcome(phrase: PhraseResult(errors: 1, corrections: 2, time: 17.8),
                                    corrected: 6, hurt: 1, blockedRepeats: 2, ignoredBrushes: 1, autoCorrected: 2, taps: 34))
        todayTaps = (0..<6).map { _ in
            let d = simulator.tapDisplacement()
            return TapSample(isCluster: false, dx: d.dx + 6, dy: d.dy + 5, hit: false)
        }
        isSetupComplete = [.home, .recalResult, .settings].contains(demo)
        if defaults.bool(forKey: "demoSignedIn") {
            account = AppleAccount(userID: "demo", name: "Alex Morgan")
        }
        if isSetupComplete, activity.log.isEmpty {
            activity.replace(with: .sample())
        }
        if isSetupComplete, medications.isEmpty {
            medications = [Medication(id: UUID(uuidString: "6E0C4F3A-6B1C-4C5B-9C55-7A1A0F6B2D11") ?? UUID(),
                                      name: "Carbidopa-levodopa", times: [MedTime(hour: 8, minute: 0), MedTime(hour: 14, minute: 0)])]
        }
        if let name = defaults.string(forKey: "demoTab"), let demoTab = AppTab(rawValue: name) {
            tab = demoTab
        }
        if demo == .settings {
            tab = .settings
            screen = .home
        } else {
            screen = demo
        }
    }
}
#endif
