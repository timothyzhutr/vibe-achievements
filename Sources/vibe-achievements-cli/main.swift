import Foundation
import VibeAchievementsCore

let args = CommandLine.arguments.dropFirst()
guard args.count >= 2 else {
    print("Usage: vibe-achievements-cli <contracts.jsonl> <store.sqlite> [transcript.jsonl ...]")
    exit(2)
}

let contractsURL = URL(fileURLWithPath: String(args[args.startIndex]))
let storePath = String(args[args.index(after: args.startIndex)])
let transcriptPaths = args.dropFirst(2).map { URL(fileURLWithPath: String($0)) }

do {
    let result = try Indexer.index(paths: transcriptPaths, contractsURL: contractsURL, storePath: storePath)
    for unlock in result.unlocks {
        print("Unlocked: \(unlock.name) - \(unlock.triggerSummary)")
    }
    for warning in result.warnings {
        fputs("Warning: skipped \(warning.path): \(warning.message)\n", stderr)
    }
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
