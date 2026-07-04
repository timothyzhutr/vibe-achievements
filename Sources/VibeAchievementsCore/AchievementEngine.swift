import Foundation

public struct AchievementUnlock: Codable, Equatable, Sendable {
    public var achievementID: String
    public var name: String
    public var projectKey: String?
    public var threadID: String?
    /// Context from the contract's cooldown, kept for diagnostics/display only.
    /// Achievement identity is always global by `achievementID`.
    public var scopeKey: String
    public var unlockedAt: Date
    public var triggerSummary: String

    public init(achievementID: String, name: String, projectKey: String?, threadID: String?, scopeKey: String = "", unlockedAt: Date, triggerSummary: String) {
        self.achievementID = achievementID
        self.name = name
        self.projectKey = projectKey
        self.threadID = threadID
        self.scopeKey = scopeKey
        self.unlockedAt = unlockedAt
        self.triggerSummary = triggerSummary
    }

    /// Stable identity for an unlock. Achievements unlock once globally; project
    /// and thread only describe where the first unlock happened.
    public var unlockKey: String {
        makeUnlockKey(achievementID: achievementID, scopeKey: scopeKey)
    }
}

/// Single source of truth for unlock identity, shared by the engine and store.
public func makeUnlockKey(achievementID: String, scopeKey: String) -> String {
    achievementID
}

public enum AchievementEngine {
    public static func evaluate(contracts: [AchievementContract], parsed: ParsedTranscript, events: [ExtractedEvent], existingUnlockKeys: Set<String> = []) -> [AchievementUnlock] {
        var unlocks: [AchievementUnlock] = []
        let activeContracts = contracts.filter { $0.active && $0.status == "keep" && !existingUnlockKeys.contains($0.id) }

        unlock("actually_wait", if: events.contains { $0.type == .correctionLanguageSeen }, activeContracts: activeContracts, parsed: parsed, unlocks: &unlocks, summary: "Changed direction mid-thread.")
        unlock("one_more_prompt", if: events.contains { $0.type == .oneMorePromptSeen }, activeContracts: activeContracts, parsed: parsed, unlocks: &unlocks, summary: "Continued a thread for 10 or more user turns.")
        unlock("rm_rf", if: hasSequence([.destructiveCleanupSeen, .recoverySeen], events) || hasSequence([.destructiveCleanupSeen, .successSeen], events), activeContracts: activeContracts, parsed: parsed, unlocks: &unlocks, summary: "Destructive cleanup was followed by recovery.")
        unlock("it_works_therefore_it_is", if: hasSequence([.implementationOrFixSeen, .successSeen], events), activeContracts: activeContracts, parsed: parsed, unlocks: &unlocks, summary: "Implementation or fix work was followed by success.")
        unlockFirstAchievementIfNeeded(activeContracts: activeContracts, existingUnlockKeys: existingUnlockKeys, unlocks: &unlocks)

        return unlocks.filter { !existingUnlockKeys.contains($0.unlockKey) }
    }

    private static func unlockFirstAchievementIfNeeded(activeContracts: [AchievementContract], existingUnlockKeys: Set<String>, unlocks: inout [AchievementUnlock]) {
        guard existingUnlockKeys.isEmpty,
              !unlocks.isEmpty,
              let contract = activeContracts.first(where: { $0.id == "achievement_unlocked_unlocking_achievement" })
        else { return }
        unlocks.append(AchievementUnlock(achievementID: contract.id, name: contract.name, projectKey: nil, threadID: nil, unlockedAt: Date(), triggerSummary: "Unlocked the first achievement."))
    }

    private static func unlock(_ id: String, if condition: Bool, activeContracts: [AchievementContract], parsed: ParsedTranscript, unlocks: inout [AchievementUnlock], summary: String) {
        guard condition, let contract = activeContracts.first(where: { $0.id == id }) else { return }
        unlocks.append(AchievementUnlock(
            achievementID: contract.id,
            name: contract.name,
            projectKey: parsed.thread.projectKey,
            threadID: parsed.thread.id,
            scopeKey: scopeKey(forCooldown: contract.cooldown, parsed: parsed),
            unlockedAt: Date(),
            triggerSummary: summary
        ))
    }

    /// Maps a contract's cooldown to the value that makes an unlock unique.
    /// `once_per_thread` -> thread id, `once_per_project*` -> project key,
    /// everything else (once_per_user / all_time) -> global.
    ///
    /// Note: time-windowed cooldowns like `once_per_project_per_7_days` are
    /// treated as once-per-project; the rolling window is not yet enforced.
    private static func scopeKey(forCooldown cooldown: String, parsed: ParsedTranscript) -> String {
        let lowered = cooldown.lowercased()
        if lowered.contains("thread") { return parsed.thread.id }
        if lowered.contains("project") { return parsed.thread.projectKey }
        return ""
    }

    private static func hasSequence(_ sequence: [EventType], _ events: [ExtractedEvent]) -> Bool {
        // Swift's sort is not stable, so tie-break equal (or missing) timestamps
        // by extraction order — events are extracted in transcript order.
        let ordered = events.enumerated()
            .sorted { ($0.element.timestamp ?? .distantPast, $0.offset) < ($1.element.timestamp ?? .distantPast, $1.offset) }
            .map(\.element)

        var index = 0
        for event in ordered {
            if event.type == sequence[index] {
                index += 1
                if index == sequence.count { return true }
            }
        }
        return false
    }
}
