import VibeAchievementsCore
import XCTest
@testable import VibeAchievementsApp

final class SourceStatusPresentationTests: XCTestCase {
    func testDisabledOverridesEveryStatus() {
        let statuses: [ConversationSourceStatus?] = [
            nil,
            status(state: .connected, recordCount: 2),
            status(state: .empty),
            status(state: .needsAttention, warningCount: 2),
            status(state: .unavailable)
        ]
        let expected = SourceStatusPresentation(
            label: "Disabled",
            detail: nil,
            systemImage: "nosign",
            tone: .neutral
        )

        for sourceStatus in statuses {
            XCTAssertEqual(
                SourceStatusPresentation.make(isEnabled: false, status: sourceStatus),
                expected
            )
        }
    }

    func testEnabledStatusesProduceExpectedPresentation() {
        let cases: [(ConversationSourceStatus?, SourceStatusPresentation)] = [
            (
                nil,
                SourceStatusPresentation(
                    label: "Refreshing",
                    detail: nil,
                    systemImage: "arrow.triangle.2.circlepath",
                    tone: .neutral
                )
            ),
            (
                status(state: .connected, recordCount: 1),
                SourceStatusPresentation(
                    label: "Connected",
                    detail: "1 conversation",
                    systemImage: "checkmark.circle.fill",
                    tone: .positive
                )
            ),
            (
                status(state: .connected, recordCount: 2),
                SourceStatusPresentation(
                    label: "Connected",
                    detail: "2 conversations",
                    systemImage: "checkmark.circle.fill",
                    tone: .positive
                )
            ),
            (
                status(state: .empty),
                SourceStatusPresentation(
                    label: "No conversations",
                    detail: nil,
                    systemImage: "tray",
                    tone: .neutral
                )
            ),
            (
                status(state: .needsAttention),
                SourceStatusPresentation(
                    label: "Needs attention",
                    detail: nil,
                    systemImage: "exclamationmark.triangle.fill",
                    tone: .caution
                )
            ),
            (
                status(state: .needsAttention, warningCount: 1),
                SourceStatusPresentation(
                    label: "Needs attention",
                    detail: "1 warning",
                    systemImage: "exclamationmark.triangle.fill",
                    tone: .caution
                )
            ),
            (
                status(state: .needsAttention, warningCount: 2),
                SourceStatusPresentation(
                    label: "Needs attention",
                    detail: "2 warnings",
                    systemImage: "exclamationmark.triangle.fill",
                    tone: .caution
                )
            ),
            (
                status(state: .unavailable),
                SourceStatusPresentation(
                    label: "Unavailable",
                    detail: nil,
                    systemImage: "xmark.circle.fill",
                    tone: .negative
                )
            )
        ]

        for (sourceStatus, expected) in cases {
            XCTAssertEqual(
                SourceStatusPresentation.make(isEnabled: true, status: sourceStatus),
                expected
            )
        }
    }

    private func status(
        state: ConversationSourceConnectionState,
        recordCount: Int = 0,
        warningCount: Int = 0
    ) -> ConversationSourceStatus {
        ConversationSourceStatus(
            sourceTool: .claudeCode,
            displayName: "Claude Code",
            state: state,
            recordCount: recordCount,
            warningCount: warningCount
        )
    }
}
