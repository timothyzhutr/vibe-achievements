import Foundation
import Combine
import VibeAchievementsCore

@MainActor
final class AppState: ObservableObject {
    @Published var sourceSummary: String = "Refreshing sources"
    @Published var sourceStatuses: [SourceTool: ConversationSourceStatus] = [:]
    @Published var recentUnlocks: [AchievementUnlock] = []
    @Published var achievementContracts: [AchievementContract] = []
    @Published var lastScanSummary: String = "Loading indexed history"
    @Published var lastError: String?
    @Published var tokenUsage: TokenUsageSummary = .zero
    @Published var sourceSettings: AppSourceSettings

    private let storePath: String
    private let sourceSettingsDefaults: UserDefaults
    private var isScanning = false
    private var pendingScan = false
    private(set) var sourceConfigurationRevision: UInt = 0
    /// Set once the notification-permission prompt has been answered. Scans
    /// before this index but do not notify — a banner posted without permission
    /// is dropped by the OS, and the unlock would be marked notified, losing it.
    private var notificationsReady = false

    init(storePath: String = AppState.defaultStorePath(), sourceSettingsDefaults: UserDefaults = .standard) {
        self.storePath = storePath
        self.sourceSettingsDefaults = sourceSettingsDefaults
        self.sourceSettings = AppSourceSettings.load(from: sourceSettingsDefaults)
        loadCachedShelf()
    }

    /// Called once the notification-permission prompt is answered. Enables
    /// notifications and runs the first authorized scan, which posts a banner for
    /// every not-yet-notified achievement (including the initial backfill).
    func notificationsBecameAvailable() {
        notificationsReady = true
        scanNow()
    }

    /// Kicks off a scan without blocking the main thread. Enumeration, parsing,
    /// SQLite writes, and posting notifications all run off the main actor; only
    /// the published-state update runs back on main.
    func scanNow() {
        guard !isScanning else {
            // Don't drop a scan behind an in-flight one — the post-permission
            // scan, or a source-settings change, may arrive during an earlier scan.
            pendingScan = true
            return
        }
        isScanning = true
        let configurationRevision = sourceConfigurationRevision
        let storePath = self.storePath
        let sourceConfiguration = sourceSettings.discoveryConfiguration
        let notify = notificationsReady
        Task {
            let result = await Self.performScan(storePath: storePath, sourceConfiguration: sourceConfiguration, notify: notify)
            self.apply(result, fromSourceConfigurationRevision: configurationRevision)
            self.isScanning = false
            if self.pendingScan {
                self.pendingScan = false
                self.scanNow()
            }
        }
    }

    /// Applies an edit to the watched-source settings, persists it, and rescans
    /// so the shelf reflects the new sources immediately.
    func updateSourceSettings(_ update: (inout AppSourceSettings) -> Void) {
        var copy = sourceSettings
        update(&copy)
        sourceSettings = copy
        copy.save(to: sourceSettingsDefaults)
        sourceConfigurationRevision &+= 1
        sourceStatuses = [:]
        scanNow()
    }

    func applySourceStatuses(_ statuses: [ConversationSourceStatus]) {
        sourceStatuses = statuses.reduce(into: [:]) { statusesByTool, status in
            statusesByTool[status.sourceTool] = status
        }
    }

    @discardableResult
    func applySourceStatuses(_ statuses: [ConversationSourceStatus], fromSourceConfigurationRevision revision: UInt) -> Bool {
        guard revision == sourceConfigurationRevision else { return false }
        applySourceStatuses(statuses)
        return true
    }

    private func apply(_ result: ScanResult, fromSourceConfigurationRevision revision: UInt) {
        guard applySourceStatuses(result.sourceStatuses, fromSourceConfigurationRevision: revision) else { return }
        sourceSummary = result.sourceSummary
        lastScanSummary = result.lastScanSummary
        lastError = result.error
        achievementContracts = result.achievementContracts
        if let tokenUsage = result.tokenUsage {
            self.tokenUsage = tokenUsage
        }
        if let recent = result.recentUnlocks {
            recentUnlocks = recent
        }
    }

    private static func defaultStorePath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("VibeAchievements", isDirectory: true)
            .appendingPathComponent("vibe-achievements.sqlite")
            .path
    }

    private func loadCachedShelf() {
        do {
            achievementContracts = try AchievementContractLoader.loadBundledV1()
            guard FileManager.default.fileExists(atPath: storePath) else { return }
            let store = try SQLiteStore(path: storePath)
            tokenUsage = try store.totalTokenUsage()
            recentUnlocks = try store.allUnlocks()
            guard !recentUnlocks.isEmpty else { return }
            lastScanSummary = "Loaded \(recentUnlocks.count) cached achievement\(recentUnlocks.count == 1 ? "" : "s")"
        } catch {
            lastError = "Could not load cached achievements: \(error)"
        }
    }
}

/// Result of a background scan, carried back to the main actor. All fields are
/// `Sendable` so it can cross the actor boundary safely.
private struct ScanResult: Sendable {
    var sourceSummary: String
    var sourceStatuses: [ConversationSourceStatus]
    var lastScanSummary: String
    var achievementContracts: [AchievementContract]
    var tokenUsage: TokenUsageSummary?
    var recentUnlocks: [AchievementUnlock]?
    var error: String?
}

extension AppState {
    nonisolated static let detectorFingerprintVersion = "detectors-v4"

    nonisolated private static func performScan(storePath: String, sourceConfiguration: SourceConfiguration, notify: Bool) async -> ScanResult {
        let registrations = ConversationSourceRegistry.registrations(
            configuration: sourceConfiguration,
            detectorVersion: detectorFingerprintVersion
        )
        let unavailableStatuses = registrations.compactMap(\.unavailableStatus)
        let failureStatuses = registrations.map(\.failureStatus)
        let adapters = registrations.compactMap(\.adapter)

        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: storePath).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let store = try SQLiteStore(path: storePath)
            let contracts = try AchievementContractLoader.loadBundledV1()
            let indexResult = try Indexer.index(
                adapters: adapters,
                contracts: contracts,
                store: store,
                scanID: UUID().uuidString
            )
            let statusByTool = Dictionary(
                uniqueKeysWithValues: (unavailableStatuses + indexResult.sourceStatuses).map { ($0.sourceTool, $0) }
            )
            let statuses = registrations.compactMap { statusByTool[$0.sourceTool] }

            // One banner per achievement, exactly once. Every unlock not yet
            // notified gets a banner here (oldest first), then is marked so it is
            // never notified again — across scans or app restarts.
            if notify {
                let pending = try store.unnotifiedUnlocks()
                if shouldMarkNotificationsDelivered(
                    notify: notify,
                    notificationsAvailable: NotificationController.notificationsAvailable,
                    pendingCount: pending.count
                ) {
                    for unlock in pending {
                        NotificationController.notify(unlockName: unlock.name, summary: unlock.triggerSummary)
                    }
                    try store.markNotified(pending.map(\.achievementID))
                }
            }

            let recent = try store.allUnlocks()
            return ScanResult(
                sourceSummary: sourceSummary(for: statuses),
                sourceStatuses: statuses,
                lastScanSummary: scanSummary(
                    changedFileCount: indexResult.changedRecordCount,
                    newUnlockCount: indexResult.unlocks.count
                ),
                achievementContracts: contracts,
                tokenUsage: try store.totalTokenUsage(),
                recentUnlocks: recent,
                error: warningSummary(for: indexResult.warnings)
            )
        } catch {
            let message = String(describing: error)
            return ScanResult(
                sourceSummary: sourceSummary(for: failureStatuses),
                sourceStatuses: failureStatuses,
                lastScanSummary: "Scan failed",
                achievementContracts: [],
                tokenUsage: nil,
                recentUnlocks: nil,
                error: message
            )
        }
    }

    nonisolated static func sourceSummary(for statuses: [ConversationSourceStatus]) -> String {
        guard !statuses.isEmpty else { return "No sources enabled" }
        return statuses.map(\.summary).joined(separator: " · ")
    }

    nonisolated static func shouldMarkNotificationsDelivered(notify: Bool, notificationsAvailable: Bool, pendingCount: Int) -> Bool {
        notify && notificationsAvailable && pendingCount > 0
    }

    /// A concise, user-facing note about skipped files, surfaced through the
    /// same channel as hard errors. `nil` when everything parsed cleanly.
    nonisolated private static func warningSummary(for warnings: [IndexWarning]) -> String? {
        guard !warnings.isEmpty else { return nil }
        let names = warnings.prefix(3).map { URL(fileURLWithPath: $0.path).lastPathComponent }
        let suffix = warnings.count > 3 ? ", …" : ""
        return "\(warnings.count) source warning\(warnings.count == 1 ? "" : "s"): \(names.joined(separator: ", "))\(suffix)"
    }

    nonisolated private static func scanSummary(changedFileCount: Int, newUnlockCount: Int) -> String {
        if changedFileCount == 0 {
            return "No transcript changes"
        }
        let files = "\(changedFileCount) changed conversation\(changedFileCount == 1 ? "" : "s")"
        if newUnlockCount == 0 {
            return "Scanned \(files) · no new achievements"
        }
        return "Scanned \(files) · \(newUnlockCount) new achievement\(newUnlockCount == 1 ? "" : "s")"
    }
}
