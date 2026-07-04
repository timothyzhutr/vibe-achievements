import Foundation
import VibeAchievementsCore

final class AppState: ObservableObject {
    @Published var sourceSummary: String = "Not indexed yet"
    @Published var recentUnlocks: [AchievementUnlock] = []

    func refresh() {
        let locations = SourceDiscovery.discover()
        var parts: [String] = []
        if locations.claudeProjects != nil { parts.append("Claude Code") }
        if locations.codexSessions != nil { parts.append("Codex") }
        sourceSummary = parts.isEmpty ? "No sources detected" : "Detected: " + parts.joined(separator: ", ")
    }
}
