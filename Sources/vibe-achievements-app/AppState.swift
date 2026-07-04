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
    private var fileModificationDates: [String: Date] = [:]

    init(storePath: String = AppState.defaultStorePath()) {
        self.storePath = storePath
    }

    func refresh(sendNotifications: Bool = false) {
        scanNow(sendNotifications: sendNotifications)
    }

    func scanNow(sendNotifications: Bool = true) {
        let locations = SourceDiscovery.discover()
        var parts: [String] = []
        if locations.claudeProjects != nil { parts.append("Claude Code") }
        if locations.codexSessions != nil { parts.append("Codex") }
        if locations.codexArchivedSessions != nil, !parts.contains("Codex") { parts.append("Codex") }

        let sourceLabel = parts.isEmpty ? "No sources detected" : "Detected: " + parts.joined(separator: ", ")
        let transcriptPaths = SourceDiscovery.transcriptPaths(in: locations)
        let changedPaths = changedTranscriptPaths(from: transcriptPaths)
        sourceSummary = transcriptPaths.isEmpty ? sourceLabel : "\(sourceLabel) · \(transcriptPaths.count) transcript files"

        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: storePath).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let newUnlocks: [AchievementUnlock]
            if changedPaths.isEmpty {
                newUnlocks = []
            } else {
                let contracts = try AchievementContractLoader.loadBundledV1()
                newUnlocks = try Indexer.index(paths: changedPaths, contracts: contracts, storePath: storePath)
            }
            let store = try SQLiteStore(path: storePath)
            recentUnlocks = try store.allUnlocks()
            lastScanSummary = scanSummary(changedFileCount: changedPaths.count, newUnlockCount: newUnlocks.count)
            lastError = nil

            if sendNotifications {
                for unlock in newUnlocks {
                    NotificationController.notify(unlockName: unlock.name, summary: unlock.triggerSummary)
                }
            }
        } catch {
            lastError = String(describing: error)
            lastScanSummary = "Scan failed"
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

    private func changedTranscriptPaths(from paths: [URL]) -> [URL] {
        paths.filter { path in
            let modifiedAt = modificationDate(for: path)
            defer { fileModificationDates[path.path] = modifiedAt }
            return fileModificationDates[path.path] != modifiedAt
        }
    }

    private func modificationDate(for url: URL) -> Date {
        ((try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
    }

    private func scanSummary(changedFileCount: Int, newUnlockCount: Int) -> String {
        if changedFileCount == 0 {
            return "No transcript changes"
        }
        if newUnlockCount == 0 {
            return "Scanned \(changedFileCount) changed file\(changedFileCount == 1 ? "" : "s") · no new achievements"
        }
        return "Scanned \(changedFileCount) changed file\(changedFileCount == 1 ? "" : "s") · \(newUnlockCount) new achievement\(newUnlockCount == 1 ? "" : "s")"
    }
}
