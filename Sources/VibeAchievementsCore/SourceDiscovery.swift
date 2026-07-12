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

public struct SourceConfiguration: Equatable, Sendable {
    public var claudeEnabled: Bool
    public var codexEnabled: Bool
    public var cursorEnabled: Bool
    public var openCodeEnabled: Bool
    public var antigravityEnabled: Bool
    public var claudeProjectsOverride: URL?
    public var codexHomeOverride: URL?
    public var cursorHomeOverride: URL?
    public var openCodeDataOverride: URL?
    public var antigravityHomeOverride: URL?

    public init(
        claudeEnabled: Bool = true,
        codexEnabled: Bool = true,
        cursorEnabled: Bool = true,
        openCodeEnabled: Bool = true,
        antigravityEnabled: Bool = true,
        claudeProjectsOverride: URL? = nil,
        codexHomeOverride: URL? = nil,
        cursorHomeOverride: URL? = nil,
        openCodeDataOverride: URL? = nil,
        antigravityHomeOverride: URL? = nil
    ) {
        self.claudeEnabled = claudeEnabled
        self.codexEnabled = codexEnabled
        self.cursorEnabled = cursorEnabled
        self.openCodeEnabled = openCodeEnabled
        self.antigravityEnabled = antigravityEnabled
        self.claudeProjectsOverride = claudeProjectsOverride
        self.codexHomeOverride = codexHomeOverride
        self.cursorHomeOverride = cursorHomeOverride
        self.openCodeDataOverride = openCodeDataOverride
        self.antigravityHomeOverride = antigravityHomeOverride
    }
}

public enum SourceDiscoveryError: Error, Equatable, Sendable {
    case unavailable(path: String)
    case enumerationFailed(path: String, message: String)
}

public enum SourceDiscovery {
    public static func discover(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        configuration: SourceConfiguration = SourceConfiguration(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SourceLocations {
        let claude = configuration.claudeProjectsOverride ?? home.appendingPathComponent(".claude/projects")
        let codexHome = configuration.codexHomeOverride
            ?? environment["CODEX_HOME"].map(URL.init(fileURLWithPath:))
            ?? home.appendingPathComponent(".codex")
        let sessions = codexHome.appendingPathComponent("sessions")
        let archived = codexHome.appendingPathComponent("archived_sessions")
        return SourceLocations(
            claudeProjects: configuration.claudeEnabled && exists(claude) ? claude : nil,
            codexSessions: configuration.codexEnabled && exists(sessions) ? sessions : nil,
            codexArchivedSessions: configuration.codexEnabled && exists(archived) ? archived : nil
        )
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func jsonlFiles(in root: URL) throws -> [URL] {
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw SourceDiscoveryError.unavailable(path: root.path)
        }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            do {
                if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                    files.append(url)
                }
            } catch {
                throw SourceDiscoveryError.enumerationFailed(path: url.path, message: String(describing: error))
            }
        }
        if let enumerationError {
            throw SourceDiscoveryError.enumerationFailed(
                path: root.path,
                message: String(describing: enumerationError)
            )
        }
        return files.sorted { $0.path < $1.path }
    }
}

public enum SourceFileFingerprint {
    public static func make(detectorVersion: String, components: [String]) -> String {
        "\(detectorVersion)-\(components.joined(separator: "|"))"
    }

    public static func make(for url: URL, detectorVersion: String) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values?.fileSize ?? 0
        return "\(detectorVersion)-\(modified)-\(size)"
    }
}
