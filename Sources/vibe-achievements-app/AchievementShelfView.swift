import SwiftUI

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
                    VStack(alignment: .leading) {
                        Text(unlock.name).font(.headline)
                        Text(unlock.triggerSummary).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
        .onAppear { state.refresh(sendNotifications: false) }
    }
}
