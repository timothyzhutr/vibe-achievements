import SwiftUI

struct AchievementShelfView: View {
    @StateObject private var state = AppState()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vibe Achievements")
                .font(.title2)
            Text(state.sourceSummary)
                .foregroundStyle(.secondary)
            List(state.recentUnlocks, id: \.achievementID) { unlock in
                VStack(alignment: .leading) {
                    Text(unlock.name).font(.headline)
                    Text(unlock.triggerSummary).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
        .onAppear { state.refresh() }
    }
}
