import ArgumentParser
import Foundation

struct StatsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Quick summary statistics from the database"
    )

    @Option(name: .long, help: "Path to SQLite database (default: ~/trivia.db)")
    var db: String = "~/trivia.db"

    func run() throws {
        let dbPath = (db as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: dbPath) else {
            print("Database not found at \(dbPath). Run 'alities-engine import' first.")
            throw ExitCode.failure
        }

        let triviaDB = try TriviaDatabase(path: dbPath)
        let s = try triviaDB.stats()

        let line = String(repeating: "─", count: 50)
        print(line)
        print("  Alities Engine — Database Stats")
        print(line)
        print("  Questions  : \(s.totalQuestions)")
        print("  Categories : \(s.totalCategories)")
        print("  Sources    : \(s.totalSources)")
        print("  Difficulty : easy=\(s.easyCount) medium=\(s.mediumCount) hard=\(s.hardCount) none=\(s.noDifficultyCount)")

        let attrs = try FileManager.default.attributesOfItem(atPath: dbPath)
        if let size = attrs[.size] as? Int64 {
            let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            print("  DB size    : \(sizeStr)")
        }
    }
}
