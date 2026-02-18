import ArgumentParser
import Foundation

struct CategoriesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "categories",
        abstract: "List all categories with question counts"
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
        let categories = try triviaDB.allCategories()

        let total = categories.reduce(0) { $0 + $1.count }
        let line = String(repeating: "─", count: 60)
        print(line)
        print("  Categories (\(categories.count) total, \(total) questions)")
        print(line)

        let maxName = max(categories.map(\.name.count).max() ?? 0, 8)
        for cat in categories where cat.count > 0 {
            let pct = total > 0 ? Double(cat.count) / Double(total) * 100 : 0
            let bar = String(repeating: "█", count: Int(pct / 2))
            let name = cat.name.padding(toLength: maxName, withPad: " ", startingAt: 0)
            print("  \(name)  \(cat.pic.padding(toLength: 22, withPad: " ", startingAt: 0))  \(String(format: "%4d", cat.count))  (\(String(format: "%5.1f%%", pct)))  \(bar)")
        }

        let aliases = try triviaDB.allAliases()
        if !aliases.isEmpty {
            print("")
            print(line)
            print("  Aliases (\(aliases.count) mappings)")
            print(line)
            var grouped: [String: [String]] = [:]
            for a in aliases {
                grouped[a.canonical, default: []].append(a.alias)
            }
            for (canonical, aliasList) in grouped.sorted(by: { $0.key < $1.key }) {
                print("  \(canonical): \(aliasList.joined(separator: ", "))")
            }
        }
    }
}
