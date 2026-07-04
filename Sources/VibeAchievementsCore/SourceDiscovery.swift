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

    public static func transcriptPaths(in locations: SourceLocations) -> [URL] {
        let roots = [
            locations.claudeProjects,
            locations.codexSessions,
            locations.codexArchivedSessions
        ].compactMap { $0 }

        return roots
            .flatMap(jsonlFiles(in:))
            .sorted { $0.path < $1.path }
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private static func jsonlFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.pathExtension == "jsonl",
                  ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false)
            else {
                return nil
            }
            return url
        }
    }
}
