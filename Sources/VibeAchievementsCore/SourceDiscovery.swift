import Foundation

public struct SourceLocations: Equatable, Sendable {
    public var claudeProjects: URL?
    public var codexSessions: URL?
    public var codexArchivedSessions: URL?

    public init(claudeProjects: URL?, codexSessions: URL?, codexArchivedSessions: URL?) {
        self.claudeProjects = claudeProjects
        self.codexSessions = codexSessions
        self.codexArchivedSessions = codexArchivedSessions
    }
}

public enum SourceDiscovery {
    public static func discover(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> SourceLocations {
        let claude = home.appendingPathComponent(".claude/projects")
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map(URL.init(fileURLWithPath:)) ?? home.appendingPathComponent(".codex")
        let sessions = codexHome.appendingPathComponent("sessions")
        let archived = codexHome.appendingPathComponent("archived_sessions")
        return SourceLocations(
            claudeProjects: exists(claude) ? claude : nil,
            codexSessions: exists(sessions) ? sessions : nil,
            codexArchivedSessions: exists(archived) ? archived : nil
        )
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
