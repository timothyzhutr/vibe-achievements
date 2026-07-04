import SwiftUI
import VibeAchievementsCore

struct AchievementShelfView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                LogoMarkView(size: 34)
                Text("Vibe Achievements")
                    .font(.title2)
            }
            Text(state.sourceSummary)
                .foregroundStyle(.secondary)
            Text(state.lastScanSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let lastError = state.lastError {
                Text(lastError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if state.recentUnlocks.isEmpty {
                ContentUnavailableView("No achievements yet", systemImage: "sparkles", description: Text("New unlocks will appear after the first scan."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(state.recentUnlocks, id: \.unlockKey) { unlock in
                    AchievementUnlockRow(unlock: unlock)
                }
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
        .onAppear { state.refresh(sendNotifications: false) }
    }
}

private struct AchievementUnlockRow: View {
    let unlock: AchievementUnlock

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(unlock.name)
                .font(.headline)
            Text(unlock.triggerSummary)
                .foregroundStyle(.secondary)
            Text(metadataText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
    }

    private var metadataText: String {
        [
            projectLabel,
            toolLabel,
            threadLabel,
            unlock.unlockedAt.formatted(date: .abbreviated, time: .shortened)
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private var projectLabel: String? {
        guard let projectKey = unlock.projectKey, !projectKey.isEmpty else { return nil }
        let name = URL(fileURLWithPath: projectKey).lastPathComponent
        return name.isEmpty ? projectKey : name
    }

    private var toolLabel: String? {
        guard let threadID = unlock.threadID else { return nil }
        if threadID.hasPrefix("codex:") { return "Codex" }
        if threadID.hasPrefix("claude_code:") { return "Claude Code" }
        return nil
    }

    private var threadLabel: String? {
        guard let threadID = unlock.threadID, !threadID.isEmpty else { return nil }
        let stripped = threadID
            .replacingOccurrences(of: "claude_code:", with: "")
            .replacingOccurrences(of: "codex:", with: "")
        return "Thread " + shortID(stripped)
    }

    private func shortID(_ value: String) -> String {
        guard value.count > 10 else { return value }
        return String(value.prefix(10)) + "..."
    }
}
