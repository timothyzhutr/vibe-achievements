import SwiftUI
import VibeAchievementsCore

struct AchievementShelfView: View {
    @ObservedObject var state: AppState
    @State private var filter: AchievementFilter = .all

    var body: some View {
        let progress = AchievementCatalog.progress(contracts: state.achievementContracts, unlocks: state.recentUnlocks)
        let items = AchievementCatalog.items(contracts: state.achievementContracts, unlocks: state.recentUnlocks, filter: filter)

        VStack(alignment: .leading, spacing: 14) {
            ShelfHeaderView(progress: progress)

            VStack(alignment: .leading, spacing: 4) {
                Text(state.sourceSummary)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(state.lastScanSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let lastError = state.lastError {
                    Text(lastError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Picker("", selection: $filter) {
                ForEach(AchievementFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if items.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptySystemImage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { item in
                            AchievementCatalogRow(item: item)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 520)
        .onAppear { state.refresh(sendNotifications: false) }
    }

    private var emptyTitle: String {
        switch filter {
        case .all: "No achievements loaded"
        case .unlocked: "No unlocked achievements"
        case .locked: "No locked achievements"
        }
    }

    private var emptySystemImage: String {
        switch filter {
        case .all: "sparkles"
        case .unlocked: "lock"
        case .locked: "checkmark.seal"
        }
    }
}

private struct ShelfHeaderView: View {
    let progress: AchievementProgress

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            LogoMarkView(size: 36)
            Text("Vibe Achievements")
                .font(.title)
                .fontWeight(.semibold)

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text("\(progress.unlocked)/\(progress.total)")
                    .font(.headline.monospacedDigit())
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 142)
            }
            .foregroundStyle(.secondary)
        }
    }
}

private struct AchievementCatalogRow: View {
    let item: AchievementCatalogItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AchievementIconPlaceholder(achievementID: item.contract.id, isUnlocked: item.isUnlocked)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.contract.name)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundStyle(item.isUnlocked ? .primary : .secondary)
                    Spacer(minLength: 8)
                    Image(systemName: item.isUnlocked ? "checkmark.seal.fill" : "lock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(item.isUnlocked ? Color.green : Color.secondary.opacity(0.55))
                        .accessibilityLabel(item.isUnlocked ? "Unlocked" : "Locked")
                }

                Text(item.contract.definition)
                    .font(.subheadline)
                    .foregroundStyle(item.isUnlocked ? .secondary : .tertiary)
                    .lineLimit(2)

                if let unlock = item.unlock {
                    Text(unlock.triggerSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(metadataText(for: unlock))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    Text(item.contract.difficulty.capitalized)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(item.isUnlocked ? 0.72 : 0.32), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator.opacity(item.isUnlocked ? 0.48 : 0.24), lineWidth: 1)
        }
        .opacity(item.isUnlocked ? 1 : 0.64)
    }

    private func metadataText(for unlock: AchievementUnlock) -> String {
        [
            projectLabel(for: unlock.projectKey),
            toolLabel(for: unlock.threadID),
            threadLabel(for: unlock.threadID),
            unlock.unlockedAt.formatted(date: .abbreviated, time: .shortened)
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private func projectLabel(for projectKey: String?) -> String? {
        guard let projectKey, !projectKey.isEmpty else { return nil }
        let name = URL(fileURLWithPath: projectKey).lastPathComponent
        return name.isEmpty ? projectKey : name
    }

    private func toolLabel(for threadID: String?) -> String? {
        guard let threadID else { return nil }
        if threadID.hasPrefix("codex:") { return "Codex" }
        if threadID.hasPrefix("claude_code:") { return "Claude Code" }
        return nil
    }

    private func threadLabel(for threadID: String?) -> String? {
        guard let threadID, !threadID.isEmpty else { return nil }
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

private struct AchievementIconPlaceholder: View {
    let achievementID: String
    let isUnlocked: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isUnlocked ? Color.primary.opacity(0.12) : Color.secondary.opacity(0.08))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isUnlocked ? Color.primary.opacity(0.18) : Color.secondary.opacity(0.12), lineWidth: 1)
            Image(systemName: AchievementIconCatalog.symbolName(for: achievementID))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isUnlocked ? Color.primary : Color.secondary.opacity(0.55))
        }
        .frame(width: 54, height: 54)
        .accessibilityHidden(true)
    }
}
