import Foundation
import Combine
import VibeAchievementsCore

@MainActor
final class AppState: ObservableObject {
    @Published var sourceSummary: String = "Not indexed yet"
    @Published var recentUnlocks: [AchievementUnlock] = []
    @Published var lastScanSummary: String = "No scan yet"
    @Published var lastError: String?

    private let storePath: String
    private var isScanning = false

    init(storePath: String = AppState.defaultStorePath()) {
        self.storePath = storePath
    }

    func refresh(sendNotifications: Bool = false) {
        scanNow(sendNotifications: sendNotifications)
    }

    /// Kicks off a scan without blocking the main thread. The heavy work
    /// (filesystem enumeration, parsing, SQLite writes) runs off the main actor;
    /// only the published-state update and notifications run back on main.
    func scanNow(sendNotifications: Bool = true) {
        guard !isScanning else { return }
        isScanning = true
        let storePath = self.storePath
        Task {
            let result = await Self.performScan(storePath: storePath)
            self.apply(result, sendNotifications: sendNotifications)
            self.isScanning = false
        }
    }

    private func apply(_ result: ScanResult, sendNotifications: Bool) {
        sourceSummary = result.sourceSummary
        lastScanSummary = result.lastScanSummary
        lastError = result.error
        if let recent = result.recentUnlocks {
            recentUnlocks = recent
        }

        guard sendNotifications, result.error == nil, !result.newUnlocks.isEmpty else { return }
        if result.wasBackfill {
            // First index of existing history: one summary instead of a burst.
            let count = result.newUnlocks.count
            NotificationController.notify(
                unlockName: "Achievements unlocked",
                summary: "Found \(count) achievement\(count == 1 ? "" : "s") in your coding history."
            )
        } else {
            for unlock in result.newUnlocks {
                NotificationController.notify(unlockName: unlock.name, summary: unlock.triggerSummary)
            }
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
    var recentUnlocks: [AchievementUnlock]?
    var newUnlocks: [AchievementUnlock]
    var wasBackfill: Bool
    var error: String?
}

extension AppState {
    nonisolated private static func performScan(storePath: String) async -> ScanResult {
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
            let knownFingerprints = try store.knownFileFingerprints()
            // A store with no recorded fingerprints is a fresh install: its first
            // productive scan is a historical backfill, which must not spam.
            let wasBackfill = knownFingerprints.isEmpty

            var changed: [(url: URL, fingerprint: String)] = []
            for path in transcriptPaths {
                let fingerprint = fingerprint(for: path)
                if knownFingerprints[path.path] != fingerprint {
                    changed.append((path, fingerprint))
                }
            }

            var newUnlocks: [AchievementUnlock] = []
            if !changed.isEmpty {
                let contracts = try AchievementContractLoader.loadBundledV1()
                newUnlocks = try Indexer.index(paths: changed.map(\.url), contracts: contracts, store: store)
                // Record fingerprints even for files that produced no unlocks so
                // they are not re-parsed until they actually change again.
                for entry in changed {
                    try store.recordFileFingerprint(path: entry.url.path, fingerprint: entry.fingerprint)
                }
            }

            let recent = try store.allUnlocks()
            return ScanResult(
                sourceSummary: sourceSummary,
                lastScanSummary: scanSummary(changedFileCount: changed.count, newUnlockCount: newUnlocks.count),
                recentUnlocks: recent,
                newUnlocks: newUnlocks,
                wasBackfill: wasBackfill,
                error: nil
            )
        } catch {
            return ScanResult(
                sourceSummary: sourceSummary,
                lastScanSummary: "Scan failed",
                recentUnlocks: nil,
                newUnlocks: [],
                wasBackfill: false,
                error: String(describing: error)
            )
        }
    }

    /// Cheap change-detection fingerprint: modification time plus size.
    nonisolated private static func fingerprint(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values?.fileSize ?? 0
        return "\(modified)-\(size)"
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
