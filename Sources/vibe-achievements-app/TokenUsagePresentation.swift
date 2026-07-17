import Foundation
import VibeAchievementsCore

enum TokenUsagePresentation {
    static func valueText(for usage: TokenUsageSummary) -> String {
        let prefix = usage.includesEstimates ? "≈" : ""
        return prefix + compactCount(usage.totalTokens)
    }

    static func detailText(for usage: TokenUsageSummary) -> String {
        let qualifier = usage.includesEstimates ? " (includes estimates)" : ""
        return "\(usage.totalTokens.formatted()) total tokens\(qualifier)"
    }

    private static func compactCount(_ count: Int) -> String {
        let units: [(threshold: Int, suffix: String)] = [
            (1_000_000_000, "B"),
            (1_000_000, "M"),
            (1_000, "K")
        ]
        guard let unit = units.first(where: { count >= $0.threshold }) else {
            return String(count)
        }

        let value = Double(count) / Double(unit.threshold)
        let roundedValue = (value * 10).rounded(.toNearestOrAwayFromZero) / 10
        let formatted = String(
            format: "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            roundedValue
        ).replacingOccurrences(of: ".0", with: "")
        return formatted + unit.suffix
    }
}
