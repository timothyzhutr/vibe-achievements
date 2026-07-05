import Foundation
import Combine
import VibeAchievementsCore

@MainActor
final class AppState: ObservableObject {
    @Published var sourceSummary: String = "Not indexed yet"
    @Published var recentUnlocks: [AchievementUnlock] = []
    @Published var achievementContracts: [AchievementContract] = []
    @Published var lastScanSummary: String = "No scan yet"
    @Published var lastError: String?

    private let storePath: String
    private var isScanning = false
    private var pendingScan = false
    /// Set once the notification-permission prompt has been answered. Scans
    /// before this index but do not notify — a banner posted without permission
    /// is dropped by the OS, and the unlock would be marked notified, losing it.
    private var notificationsReady = false

    init(storePath: String = AppState.defaultStorePath()) {
        self.storePath = storePath
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
            // scan may arrive during an earlier (non-notifying) scan.
            pendingScan = true
            return
        }
        isScanning = true
        let storePath = self.storePath
        let notify = notificationsReady
        Task {
            let result = await Self.performScan(storePath: storePath, notify: notify)
            self.apply(result)
            self.isScanning = false
            if self.pendingScan {
                self.pendingScan = false
                self.scanNow()
            }
        }
    }

    private func apply(_ result: ScanResult) {
        sourceSummary = result.sourceSummary
        lastScanSummary = result.lastScanSummary
        lastError = result.error
        achievementContracts = result.achievementContracts
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
}

/// Result of a background scan, carried back to the main actor. All fields are
/// `Sendable` so it can cross the actor boundary safely.
private struct ScanResult: Sendable {
    var sourceSummary: String
    var lastScanSummary: String
    var achievementContracts: [AchievementContract]
    var recentUnlocks: [AchievementUnlock]?
    var newUnlocks: [AchievementUnlock]
    var error: String?
    var hardError: String?
}

extension AppState {
    nonisolated static let detectorFingerprintVersion = "detectors-v2"

    nonisolated private static func performScan(storePath: String, notify: Bool) async -> ScanResult {
        let locations = SourceDiscovery.discover()
        var parts: [String] = []
        if locations.claudeProjects != nil { parts.append("Claude Code") }
        if locations.codexSessions != nil || locations.codexArchivedSessions != nil { parts.append("Codex") }
        let sourceLabel = parts.isEmpty ? "No sources detected" : "Detected: " + parts.joined(separator: ", ")

        let transcriptPaths = SourceDiscovery.transcriptPaths(in: locations)
        let sourceSummary = transcriptPaths.isEmpty
            ? sourceLabel
            : "\(sourceLabel) · \(transcriptPaths.count) transcript files"

        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: storePath).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let store = try SQLiteStore(path: storePath)
            let contracts = try AchievementContractLoader.loadBundledV1()
            let knownFingerprints = try store.knownFileFingerprints()

            var changed: [(url: URL, fingerprint: String)] = []
            for path in transcriptPaths {
                let fingerprint = fingerprint(for: path)
                if knownFingerprints[path.path] != fingerprint {
                    changed.append((path, fingerprint))
                }
            }

            var newUnlocks: [AchievementUnlock] = []
            var warnings: [IndexWarning] = []
            if !changed.isEmpty {
                let result = try Indexer.index(paths: changed.map(\.url), contracts: contracts, store: store)
                newUnlocks = result.unlocks
                warnings = result.warnings
                // Record fingerprints even for files that produced no unlocks so
                // they are not re-parsed until they actually change again. Files
                // that failed to parse are deliberately retried on later scans.
                for entry in changed {
                    if shouldRecordFingerprint(for: entry.url.path, warnings: warnings) {
                        try store.recordFileFingerprint(path: entry.url.path, fingerprint: entry.fingerprint)
                    }
                }
            }

            // One banner per achievement, exactly once. Every unlock not yet
            // notified gets a banner here (oldest first), then is marked so it is
            // never notified again — across scans or app restarts.
            if notify {
                let pending = try store.unnotifiedUnlocks()
                for unlock in pending {
                    NotificationController.notify(unlockName: unlock.name, summary: unlock.triggerSummary)
                }
                try store.markNotified(pending.map(\.achievementID))
            }

            let recent = try store.allUnlocks()
            return ScanResult(
                sourceSummary: sourceSummary,
                lastScanSummary: scanSummary(changedFileCount: changed.count, newUnlockCount: newUnlocks.count),
                achievementContracts: contracts,
                recentUnlocks: recent,
                newUnlocks: newUnlocks,
                error: warningSummary(for: warnings),
                hardError: nil
            )
        } catch {
            let message = String(describing: error)
            return ScanResult(
                sourceSummary: sourceSummary,
                lastScanSummary: "Scan failed",
                achievementContracts: [],
                recentUnlocks: nil,
                newUnlocks: [],
                error: message,
                hardError: message
            )
        }
    }

    /// Cheap change-detection fingerprint: modification time plus size.
    nonisolated static func fingerprint(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values?.fileSize ?? 0
        return "\(detectorFingerprintVersion)-\(modified)-\(size)"
    }

    nonisolated static func shouldRecordFingerprint(for path: String, warnings: [IndexWarning]) -> Bool {
        !warnings.contains { $0.path == path }
    }

    /// A concise, user-facing note about skipped files, surfaced through the
    /// same channel as hard errors. `nil` when everything parsed cleanly.
    nonisolated private static func warningSummary(for warnings: [IndexWarning]) -> String? {
        guard !warnings.isEmpty else { return nil }
        let names = warnings.prefix(3).map { URL(fileURLWithPath: $0.path).lastPathComponent }
        let suffix = warnings.count > 3 ? ", …" : ""
        return "Skipped \(warnings.count) unreadable file\(warnings.count == 1 ? "" : "s"): \(names.joined(separator: ", "))\(suffix)"
    }

    nonisolated private static func scanSummary(changedFileCount: Int, newUnlockCount: Int) -> String {
        if changedFileCount == 0 {
            return "No transcript changes"
        }
        let files = "\(changedFileCount) changed file\(changedFileCount == 1 ? "" : "s")"
        if newUnlockCount == 0 {
            return "Scanned \(files) · no new achievements"
        }
        return "Scanned \(files) · \(newUnlockCount) new achievement\(newUnlockCount == 1 ? "" : "s")"
    }
}
