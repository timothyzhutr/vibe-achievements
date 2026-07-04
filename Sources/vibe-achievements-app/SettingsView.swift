import SwiftUI

struct SettingsView: View {
    @StateObject private var state = AppState()

    var body: some View {
        Form {
            Text("Sources")
            Text(state.sourceSummary)
                .foregroundStyle(.secondary)
            Button("Refresh Sources") {
                state.refresh()
            }
        }
        .padding()
        .frame(width: 460)
        .onAppear { state.refresh() }
    }
}
