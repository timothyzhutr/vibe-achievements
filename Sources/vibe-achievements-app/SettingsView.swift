import AppKit
import SwiftUI
import VibeAchievementsCore

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
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
                    sourceTool: .claudeCode,
                    status: state.sourceStatuses[.claudeCode],
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
                    sourceTool: .codex,
                    status: state.sourceStatuses[.codex],
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
                    sourceTool: .cursor,
                    status: state.sourceStatuses[.cursor],
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
                    sourceTool: .openCode,
                    status: state.sourceStatuses[.openCode],
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
                    sourceTool: .antigravity,
                    status: state.sourceStatuses[.antigravity],
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
            .frame(maxWidth: 580, alignment: .leading)
            .padding(20)
        }
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
    let sourceTool: SourceTool
    let status: ConversationSourceStatus?
    @Binding var isEnabled: Bool
    let pathText: String
    let isManualPath: Bool
    let chooseDirectory: () -> Void
    let resetDirectory: () -> Void

    private var presentation: SourceStatusPresentation {
        SourceStatusPresentation.make(isEnabled: isEnabled, status: status)
    }

    private var connectionAccessibilityLabel: String {
        var components = ["\(title) connection", presentation.label]
        if let detail = presentation.detail {
            components.append(detail)
        }
        return components.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Enabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(isEnabled ? "On" : "Off")
                            .frame(width: 24, alignment: .leading)
                            .accessibilityHidden(true)

                        Toggle("", isOn: $isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel(Text("\(title) enabled"))
                            .accessibilityValue(Text(isEnabled ? "On" : "Off"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Connection")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: presentation.systemImage)
                            .foregroundStyle(presentation.tone.color)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(presentation.label)
                            if let detail = presentation.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(connectionAccessibilityLabel))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
        .id(sourceTool)
    }
}

private extension SourceStatusTone {
    var color: Color {
        switch self {
        case .positive:
            .green
        case .caution:
            .orange
        case .negative:
            .red
        case .neutral:
            .secondary
        }
    }
}
