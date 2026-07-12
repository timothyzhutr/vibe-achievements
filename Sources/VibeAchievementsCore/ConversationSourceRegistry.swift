import Foundation

public enum ConversationSourceConnectionState: String, Equatable, Sendable {
    case connected
    case empty
    case unavailable
    case needsAttention
}

public struct ConversationSourceStatus: Equatable, Sendable {
    public let sourceTool: SourceTool
    public let displayName: String
    public let state: ConversationSourceConnectionState
    public let recordCount: Int
    public let warningCount: Int

    public init(
        sourceTool: SourceTool,
        displayName: String,
        state: ConversationSourceConnectionState,
        recordCount: Int,
        warningCount: Int
    ) {
        self.sourceTool = sourceTool
        self.displayName = displayName
        self.state = state
        self.recordCount = recordCount
        self.warningCount = warningCount
    }

    public var summary: String {
        switch state {
        case .connected:
            return "\(displayName): \(recordCount) conversation\(recordCount == 1 ? "" : "s")"
        case .empty:
            return "\(displayName): no conversations"
        case .unavailable:
            return "\(displayName): unavailable"
        case .needsAttention:
            return "\(displayName): needs attention"
        }
    }
}

public struct ConversationSourceRegistration: Sendable {
    public let sourceTool: SourceTool
    public let displayName: String
    public let adapter: (any ConversationSourceAdapter)?

    public var unavailableStatus: ConversationSourceStatus? {
        guard adapter == nil else { return nil }
        return ConversationSourceStatus(
            sourceTool: sourceTool,
            displayName: displayName,
            state: .unavailable,
            recordCount: 0,
            warningCount: 0
        )
    }

    public var failureStatus: ConversationSourceStatus {
        unavailableStatus ?? ConversationSourceStatus(
            sourceTool: sourceTool,
            displayName: displayName,
            state: .needsAttention,
            recordCount: 0,
            warningCount: 1
        )
    }
}

public enum ConversationSourceRegistry {
    public static func registrations(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        configuration: SourceConfiguration,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        detectorVersion: String
    ) -> [ConversationSourceRegistration] {
        let locations = SourceDiscovery.discover(
            home: home,
            configuration: configuration,
            environment: environment
        )
        var registrations: [ConversationSourceRegistration] = []

        if configuration.claudeEnabled {
            registrations.append(ConversationSourceRegistration(
                sourceTool: .claudeCode,
                displayName: "Claude Code",
                adapter: locations.claudeProjects.map {
                    ClaudeCodeSourceAdapter(projectsRoot: $0, detectorVersion: detectorVersion)
                }
            ))
        }
        if configuration.codexEnabled {
            let adapter: (any ConversationSourceAdapter)?
            if locations.codexSessions != nil || locations.codexArchivedSessions != nil {
                adapter = CodexSourceAdapter(
                    sessionsRoot: locations.codexSessions,
                    archivedSessionsRoot: locations.codexArchivedSessions,
                    detectorVersion: detectorVersion
                )
            } else {
                adapter = nil
            }
            registrations.append(ConversationSourceRegistration(
                sourceTool: .codex,
                displayName: "Codex",
                adapter: adapter
            ))
        }
        if configuration.cursorEnabled {
            let defaultRoots = CursorSourceAdapter.defaultRoots(home: home)
            let applicationSupport = configuration.cursorHomeOverride ?? defaultRoots.applicationSupport
            let roots = CursorRoots(applicationSupport: applicationSupport, projects: defaultRoots.projects)
            let hasRoot = FileManager.default.fileExists(atPath: roots.applicationSupport.path)
                || FileManager.default.fileExists(atPath: roots.projects.path)
            registrations.append(ConversationSourceRegistration(
                sourceTool: .cursor,
                displayName: "Cursor",
                adapter: hasRoot
                    ? CursorSourceAdapter(roots: roots, detectorVersion: detectorVersion)
                    : nil
            ))
        }
        if configuration.openCodeEnabled {
            let dataRoot = configuration.openCodeDataOverride
                ?? environment["XDG_DATA_HOME"]
                    .map { URL(fileURLWithPath: $0).appendingPathComponent("opencode", isDirectory: true) }
                ?? home.appendingPathComponent(".local/share/opencode", isDirectory: true)
            let hasRoot = FileManager.default.fileExists(atPath: dataRoot.path)
            registrations.append(ConversationSourceRegistration(
                sourceTool: .openCode,
                displayName: "OpenCode",
                adapter: hasRoot
                    ? OpenCodeSourceAdapter(
                        dataRoot: dataRoot,
                        environment: environment,
                        detectorVersion: detectorVersion
                    )
                    : nil
            ))
        }
        if configuration.antigravityEnabled {
            let roots = AntigravitySourceAdapter.defaultRoots(
                home: home,
                homeOverride: configuration.antigravityHomeOverride
            )
            let hasRoot = FileManager.default.fileExists(atPath: roots.ideBrain.path)
                || FileManager.default.fileExists(atPath: roots.cliBrain.path)
            registrations.append(ConversationSourceRegistration(
                sourceTool: .antigravity,
                displayName: "Antigravity",
                adapter: hasRoot
                    ? AntigravitySourceAdapter(roots: roots, detectorVersion: detectorVersion)
                    : nil
            ))
        }
        return registrations
    }
}
