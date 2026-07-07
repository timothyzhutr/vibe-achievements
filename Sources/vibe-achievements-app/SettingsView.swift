import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Conversation Sources")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                ForEach(SourceDirectorySetting.rows(for: state.sourceSettings)) { source in
                    SourceDirectoryRow(
                        source: source,
                        isEnabled: enabledBinding(for: source.platform),
                        chooseDirectory: {
                            chooseDirectory(title: "Choose \(source.platformName) \(source.folderRole)") { path in
                                updatePath(for: source.platform, path: path)
                            }
                        },
                        resetDirectory: {
                            resetPath(for: source.platform)
                        }
                    )
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Text("Scan Status")
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

            Button {
                state.scanNow()
            } label: {
                Label("Scan Now", systemImage: "arrow.clockwise")
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 680, idealWidth: 720, minHeight: 460, idealHeight: 500, alignment: .topLeading)
        .onAppear { state.scanNow() }
    }

    private func enabledBinding(for platform: SourceDirectorySetting.Platform) -> Binding<Bool> {
        Binding(
            get: {
                switch platform {
                case .claude:
                    return state.sourceSettings.claudeEnabled
                case .codex:
                    return state.sourceSettings.codexEnabled
                }
            },
            set: { value in
                state.updateSourceSettings { settings in
                    switch platform {
                    case .claude:
                        settings.claudeEnabled = value
                    case .codex:
                        settings.codexEnabled = value
                    }
                }
            }
        )
    }

    private func updatePath(for platform: SourceDirectorySetting.Platform, path: String) {
        state.updateSourceSettings { settings in
            switch platform {
            case .claude:
                settings.claudeProjectsPath = path
            case .codex:
                settings.codexHomePath = path
            }
        }
    }

    private func resetPath(for platform: SourceDirectorySetting.Platform) {
        state.updateSourceSettings { settings in
            switch platform {
            case .claude:
                settings.resetClaudePath()
            case .codex:
                settings.resetCodexPath()
            }
        }
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
    let source: SourceDirectorySetting
    @Binding var isEnabled: Bool
    let chooseDirectory: () -> Void
    let resetDirectory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isEnabled ? .primary : .tertiary)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(source.platformName)
                        .font(.headline)
                    Text(source.folderRole)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Scan", isOn: $isEnabled)
                    .toggleStyle(.switch)
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.selectionMode == .manual ? "Selected folder" : "Automatic folder")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(source.displayPath)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(isEnabled ? .primary : .tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    chooseDirectory()
                } label: {
                    Label("Choose Folder", systemImage: "folder")
                }

                Button {
                    resetDirectory()
                } label: {
                    Label("Use Default", systemImage: "arrow.uturn.backward")
                }
                .disabled(source.selectionMode == .automatic)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        )
    }

    private var iconName: String {
        switch source.platform {
        case .claude:
            return "text.bubble"
        case .codex:
            return "terminal"
        }
    }
}
