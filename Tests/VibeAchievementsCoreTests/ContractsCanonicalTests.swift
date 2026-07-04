import XCTest
@testable import VibeAchievementsCore

final class ContractsCanonicalTests: XCTestCase {
    /// The app loads the contracts bundled into VibeAchievementsCore/Resources,
    /// while docs/ holds the human-facing canonical copy. They must not drift.
    func testBundledContractsMatchDocsCopy() throws {
        // Derive the repo root from this test file's compile-time path:
        // <root>/Tests/VibeAchievementsCoreTests/ContractsCanonicalTests.swift
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let docsURL = repoRoot.appendingPathComponent("docs/achievement-trigger-contracts-v1.jsonl")

        let docsContracts = try AchievementContractLoader.load(jsonlURL: docsURL)
        let bundledContracts = try AchievementContractLoader.loadBundledV1()

        XCTAssertEqual(
            bundledContracts,
            docsContracts,
            "docs/ and Sources/VibeAchievementsCore/Resources/ contract copies have drifted; keep them in sync."
        )
    }
}
