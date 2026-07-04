import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Text("Sources")
            Text(state.sourceSummary)
                .foregroundStyle(.secondary)
            Text(state.lastScanSummary)
                .foregroundStyle(.secondary)
            if let lastError = state.lastError {
                Text(lastError)
                    .foregroundStyle(.red)
            }
            Button("Scan Now") {
                state.scanNow(sendNotifications: true)
            }
        }
        .padding()
        .frame(width: 460)
        .onAppear { state.refresh(sendNotifications: false) }
    }
}
