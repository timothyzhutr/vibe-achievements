import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sources")
                    .font(.headline)
                Text(state.sourceSummary)
                    .foregroundStyle(.secondary)
                Text(state.lastScanSummary)
                    .foregroundStyle(.secondary)
                if let lastError = state.lastError {
                    Text(lastError)
                        .foregroundStyle(.red)
                }
            }

            Divider()

            SourceDirectoryRow(
                title: "Claude Code",
                subtitle: "Conversation projects folder",
                isEnabled: Binding(
                    get: { state.sourceSettings.claudeEnabled },
                    set: { value in state.updateSourceSettings { $0.claudeEnabled = value } }
                ),
                pathText: state.sourceSettings.claudeProjectsPath ?? "Auto: ~/.claude/projects",
                isManualPath: state.sourceSettings.claudeProjectsPath != nil,
                chooseDirectory: {
                    chooseDirectory(title: "Choose Claude Code Projects Folder") { path in
                        state.updateSourceSettings { $0.claudeProjectsPath = path }
                    }
                },
                resetDirectory: {
                    state.updateSourceSettings { $0.resetClaudePath() }
                }
            )

            SourceDirectoryRow(
                title: "Codex",
                subtitle: "Codex home folder",
                isEnabled: Binding(
                    get: { state.sourceSettings.codexEnabled },
                    set: { value in state.updateSourceSettings { $0.codexEnabled = value } }
                ),
                pathText: state.sourceSettings.codexHomePath ?? "Auto: $CODEX_HOME or ~/.codex",
                isManualPath: state.sourceSettings.codexHomePath != nil,
                chooseDirectory: {
                    chooseDirectory(title: "Choose Codex Home Folder") { path in
                        state.updateSourceSettings { $0.codexHomePath = path }
                    }
                },
                resetDirectory: {
                    state.updateSourceSettings { $0.resetCodexPath() }
                }
            )

            SourceDirectoryRow(
                title: "Cursor",
                subtitle: "Cursor application support folder",
                isEnabled: Binding(
                    get: { state.sourceSettings.cursorEnabled },
                    set: { value in state.updateSourceSettings { $0.cursorEnabled = value } }
                ),
                pathText: state.sourceSettings.cursorHomePath ?? "Auto: ~/Library/Application Support/Cursor",
                isManualPath: state.sourceSettings.cursorHomePath != nil,
                chooseDirectory: {
                    chooseDirectory(title: "Choose Cursor Application Support Folder") { path in
                        state.updateSourceSettings { $0.cursorHomePath = path }
                    }
                },
                resetDirectory: {
                    state.updateSourceSettings { $0.resetCursorPath() }
                }
            )

            SourceDirectoryRow(
                title: "OpenCode",
                subtitle: "OpenCode data folder",
                isEnabled: Binding(
                    get: { state.sourceSettings.openCodeEnabled },
                    set: { value in state.updateSourceSettings { $0.openCodeEnabled = value } }
                ),
                pathText: state.sourceSettings.openCodeDataPath ?? "Auto: $XDG_DATA_HOME/opencode or ~/.local/share/opencode",
                isManualPath: state.sourceSettings.openCodeDataPath != nil,
                chooseDirectory: {
                    chooseDirectory(title: "Choose OpenCode Data Folder") { path in
                        state.updateSourceSettings { $0.openCodeDataPath = path }
                    }
                },
                resetDirectory: {
                    state.updateSourceSettings { $0.resetOpenCodePath() }
                }
            )

            SourceDirectoryRow(
                title: "Antigravity",
                subtitle: "Antigravity Gemini home folder · Experimental",
                isEnabled: Binding(
                    get: { state.sourceSettings.antigravityEnabled },
                    set: { value in state.updateSourceSettings { $0.antigravityEnabled = value } }
                ),
                pathText: state.sourceSettings.antigravityHomePath ?? "Auto: ~/.gemini",
                isManualPath: state.sourceSettings.antigravityHomePath != nil,
                chooseDirectory: {
                    chooseDirectory(title: "Choose Antigravity Gemini Home Folder") { path in
                        state.updateSourceSettings { $0.antigravityHomePath = path }
                    }
                },
                resetDirectory: {
                    state.updateSourceSettings { $0.resetAntigravityPath() }
                }
            )
        }
        .padding()
        .frame(width: 560)
        .onAppear { state.scanNow() }
    }

    private func chooseDirectory(title: String, onSelection: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            onSelection(url.path)
        }
    }
}

private struct SourceDirectoryRow: View {
    let title: String
    let subtitle: String
    @Binding var isEnabled: Bool
    let pathText: String
    let isManualPath: Bool
    let chooseDirectory: () -> Void
    let resetDirectory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Enabled", isOn: $isEnabled)
                    .toggleStyle(.switch)
            }

            HStack(spacing: 8) {
                Text(pathText)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(isEnabled ? .secondary : .tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    chooseDirectory()
                } label: {
                    Label("Choose...", systemImage: "folder")
                }

                Button {
                    resetDirectory()
                } label: {
                    Label("Reset", systemImage: "arrow.uturn.backward")
                }
                .disabled(!isManualPath)
            }
        }
    }
}
