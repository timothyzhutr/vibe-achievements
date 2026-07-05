import Foundation

public struct AchievementUnlock: Codable, Equatable, Sendable {
    public var achievementID: String
    public var name: String
    /// Where the unlock first happened. Achievements are global (once per user,
    /// ever), so these are kept for display/diagnostics only.
    public var projectKey: String?
    public var threadID: String?
    public var unlockedAt: Date
    public var triggerSummary: String

    public init(achievementID: String, name: String, projectKey: String?, threadID: String?, unlockedAt: Date, triggerSummary: String) {
        self.achievementID = achievementID
        self.name = name
        self.projectKey = projectKey
        self.threadID = threadID
        self.unlockedAt = unlockedAt
        self.triggerSummary = triggerSummary
    }
}

public enum AchievementEngine {
    public static var ruleIDs: [String] {
        rules.map(\.id)
    }

    /// Evaluates a single transcript. `existingUnlockedIDs` are the achievement
    /// ids already unlocked (globally); they are never re-emitted.
    public static func evaluate(contracts: [AchievementContract], parsed: ParsedTranscript, events: [ExtractedEvent], existingUnlockedIDs: Set<String> = []) -> [AchievementUnlock] {
        var unlocks: [AchievementUnlock] = []
        let activeContracts = contracts.filter { $0.active && $0.status == "keep" && !existingUnlockedIDs.contains($0.id) }
        let summary = EventSummary(events: events)

        for rule in rules where rule.matches(parsed, summary) {
            unlock(rule.id, activeContracts: activeContracts, parsed: parsed, unlocks: &unlocks, summary: rule.summary)
        }
        unlockFirstAchievementIfNeeded(activeContracts: activeContracts, existingUnlockedIDs: existingUnlockedIDs, unlocks: &unlocks)

        return unlocks
    }

    private struct AchievementRule: Sendable {
        var id: String
        var summary: String
        var matches: @Sendable (ParsedTranscript, EventSummary) -> Bool
    }

    private static let rules: [AchievementRule] = [
        AchievementRule(id: "actually_wait", summary: "Changed direction mid-thread.") { _, events in
            events.has(.correctionLanguageSeen)
        },
        AchievementRule(id: "one_more_prompt", summary: "Continued a thread for 10 or more user turns.") { _, events in
            events.has(.oneMorePromptSeen)
        },
        AchievementRule(id: "prompt_it_into_existence", summary: "Asked an AI tool to build something new.") { _, events in
            events.has(.creationRequestSeen)
        },
        AchievementRule(id: "weekend_mvp_energy", summary: "Framed the work as an MVP, prototype, or quick project.") { _, events in
            events.has(.mvpLanguageSeen)
        },
        AchievementRule(id: "the_message_had_mass", summary: "Sent or received an unusually long message.") { _, events in
            events.has(.longMessageSeen)
        },
        AchievementRule(id: "confidence_high_context_low", summary: "Kept going after context limits came up.") { _, events in
            events.has(.longThreadSeen) && events.sequence([.contextLimitSeen, .userTurnSeen])
        },
        AchievementRule(id: "context_window_sunset", summary: "Discussed context limits or compaction.") { _, events in
            events.has(.contextLimitSeen)
        },
        AchievementRule(id: "token_budget_lifestyle", summary: "Discussed token, usage, cost, or context budget.") { _, events in
            events.has(.tokenBudgetSeen)
        },
        AchievementRule(id: "the_app_has_opinions", summary: "The assistant pushed back and the thread continued.") { _, events in
            events.sequence([.assistantPushbackSeen, .userTurnSeen])
        },
        AchievementRule(id: "lore_drop", summary: "Provided background context before asking for implementation.") { _, events in
            events.has(.longMessageSeen) && events.sequence([.backgroundContextSeen, .codeChangeRequestSeen])
        },
        AchievementRule(id: "stack_trace_oracle", summary: "Shared a stack trace or raw error output.") { _, events in
            events.has(.stackTraceSeen)
        },
        AchievementRule(id: "one_more_run", summary: "Iterated fix, run, fail, and retry language repeatedly.") { _, events in
            events.count(.iterationTermSeen) >= 4
        },
        AchievementRule(id: "green_bar_acquired", summary: "A verification failure was followed by a pass.") { _, events in
            events.sequence([.verificationFailureSeen, .verificationSuccessSeen])
        },
        AchievementRule(id: "green_by_coincidence", summary: "Something worked despite uncertainty about why.") { _, events in
            events.has(.uncertainSuccessSeen)
        },
        AchievementRule(id: "understanding_optional", summary: "The thread admitted uncertainty about why it worked.") { _, events in
            events.has(.uncertaintySeen)
        },
        AchievementRule(id: "we_are_so_back", summary: "Failure language was followed by success.") { _, events in
            events.sequence([.failureSeen, .successSeen])
        },
        AchievementRule(id: "rubber_duck_with_a_gpu", summary: "Reasoned to a conclusion without asking for code changes.") { _, events in
            events.sequence([.reasoningSeen, .conclusionSeen]) && !events.has(.codeChangeRequestSeen)
        },
        AchievementRule(id: "it_works_therefore_it_is", summary: "Implementation or fix work was followed by success.") { _, events in
            events.sequence([.implementationOrFixSeen, .successSeen])
        },
        AchievementRule(id: "nobody_touch_it", summary: "Success was followed by leave-it-alone language.") { _, events in
            events.has(.successSeen) && events.has(.doNotTouchSeen)
        },
        AchievementRule(id: "production_is_a_place", summary: "Prototype language met production or launch language.") { _, events in
            events.has(.mvpLanguageSeen) && events.has(.productionLanguageSeen)
        },
        AchievementRule(id: "the_button_exists_now", summary: "Worked on a concrete UI control.") { _, events in
            events.has(.uiControlSeen)
        },
        AchievementRule(id: "css_negotiations", summary: "Iterated on frontend styling and layout details.") { _, events in
            events.has(.frontendContextSeen) && events.count(.styleAdjustmentSeen) >= 3
        },
        AchievementRule(id: "cache_clearing_ritual", summary: "Used cache clearing, restart, reinstall, or clean-build troubleshooting.") { _, events in
            events.has(.cacheRitualSeen)
        },
        AchievementRule(id: "rm_rf", summary: "Destructive cleanup was followed by recovery.") { _, events in
            events.sequence([.destructiveCleanupSeen, .recoverySeen]) || events.sequence([.destructiveCleanupSeen, .successSeen])
        },
        AchievementRule(id: "lgtm_from_the_void", summary: "Review or approval language appeared.") { _, events in
            events.has(.approvalLanguageSeen)
        },
        AchievementRule(id: "shipwright", summary: "Discussed committing, merging, releasing, or shipping work.") { _, events in
            events.has(.shipLanguageSeen)
        }
    ]

    private static func unlockFirstAchievementIfNeeded(activeContracts: [AchievementContract], existingUnlockedIDs: Set<String>, unlocks: inout [AchievementUnlock]) {
        guard existingUnlockedIDs.isEmpty,
              !unlocks.isEmpty,
              let contract = activeContracts.first(where: { $0.id == "achievement_unlocked_unlocking_achievement" })
        else { return }
        unlocks.append(AchievementUnlock(achievementID: contract.id, name: contract.name, projectKey: nil, threadID: nil, unlockedAt: Date(), triggerSummary: "Unlocked the first achievement."))
    }

    private static func unlock(_ id: String, activeContracts: [AchievementContract], parsed: ParsedTranscript, unlocks: inout [AchievementUnlock], summary: String) {
        guard let contract = activeContracts.first(where: { $0.id == id }) else { return }
        unlocks.append(AchievementUnlock(
            achievementID: contract.id,
            name: contract.name,
            projectKey: parsed.thread.projectKey,
            threadID: parsed.thread.id,
            unlockedAt: Date(),
            triggerSummary: summary
        ))
    }
}
