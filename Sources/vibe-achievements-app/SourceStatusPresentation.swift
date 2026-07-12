import VibeAchievementsCore

enum SourceStatusTone: Equatable {
    case positive
    case caution
    case negative
    case neutral
}

struct SourceStatusPresentation: Equatable {
    let label: String
    let detail: String?
    let systemImage: String
    let tone: SourceStatusTone

    static func make(
        isEnabled: Bool,
        status: ConversationSourceStatus?
    ) -> SourceStatusPresentation {
        guard isEnabled else {
            return SourceStatusPresentation(
                label: "Disabled",
                detail: nil,
                systemImage: "nosign",
                tone: .neutral
            )
        }

        guard let status else {
            return SourceStatusPresentation(
                label: "Refreshing",
                detail: nil,
                systemImage: "arrow.triangle.2.circlepath",
                tone: .neutral
            )
        }

        switch status.state {
        case .connected:
            return SourceStatusPresentation(
                label: "Connected",
                detail: "\(status.recordCount) conversation\(status.recordCount == 1 ? "" : "s")",
                systemImage: "checkmark.circle.fill",
                tone: .positive
            )
        case .empty:
            return SourceStatusPresentation(
                label: "No conversations",
                detail: nil,
                systemImage: "tray",
                tone: .neutral
            )
        case .needsAttention:
            let detail = status.warningCount > 0
                ? "\(status.warningCount) warning\(status.warningCount == 1 ? "" : "s")"
                : nil
            return SourceStatusPresentation(
                label: "Needs attention",
                detail: detail,
                systemImage: "exclamationmark.triangle.fill",
                tone: .caution
            )
        case .unavailable:
            return SourceStatusPresentation(
                label: "Unavailable",
                detail: nil,
                systemImage: "xmark.circle.fill",
                tone: .negative
            )
        }
    }
}
