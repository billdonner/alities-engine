import ArgumentParser
import Foundation

/// Import JSON trivia files into SQLite database (from trivia-profile)
struct ProfileImportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import JSON trivia files into SQLite database"
    )

    @Argument(help: "Path(s) to JSON trivia data file(s)")
    var files: [String]

    @Option(name: .long, help: "Path to SQLite database (default: ~/trivia.db)")
    var db: String = "~/trivia.db"

    @Flag(name: .long, help: "Show what would be imported without writing")
    var dryRun: Bool = false

    func run() throws {
        let dbPath = (db as NSString).expandingTildeInPath

        if !dryRun {
            let triviaDB = try TriviaDatabase(path: dbPath)
            try CategoryMap.seedDatabase(triviaDB)

            var totalImported = 0
            var totalSkipped = 0
            var newCategories = Set<String>()

            for filePath in files {
                let path = (filePath as NSString).expandingTildeInPath
                let url = URL(fileURLWithPath: path)

                guard FileManager.default.fileExists(atPath: url.path) else {
                    print("  WARNING: File not found: \(filePath), skipping")
                    continue
                }

                let (questions, _, _) = try DataLoader.load(from: url)
                let fileName = url.lastPathComponent
                var imported = 0
                var skipped = 0

                for q in questions {
                    let canonical = CategoryMap.normalize(q.category)
                    let categoryId = try triviaDB.resolveCategoryId(for: q.category)

                    let choices = q.answers.enumerated().map { (i, text) in
                        ChoiceEntry(text: text, isCorrect: i == q.correctIndex)
                    }

                    let result = try triviaDB.insertQuestion(
                        text: q.question, choices: choices,
                        correctIndex: q.correctIndex, categoryId: categoryId,
                        difficulty: q.difficulty, explanation: q.explanation,
                        hint: q.hint, source: q.source ?? "unknown",
                        importedFrom: fileName
                    )

                    switch result {
                    case .inserted:
                        imported += 1
                        newCategories.insert(canonical)
                    case .duplicate:
                        skipped += 1
                    }
                }

                print("  \(fileName): \(imported) imported, \(skipped) duplicates skipped")
                totalImported += imported
                totalSkipped += skipped
            }

            print("\nTotal: \(totalImported) imported, \(totalSkipped) duplicates skipped, \(newCategories.count) categories")
        } else {
            var totalQuestions = 0
            var allCategories = Set<String>()
            var hashSet = Set<String>()
            var dupeCount = 0

            for filePath in files {
                let path = (filePath as NSString).expandingTildeInPath
                let url = URL(fileURLWithPath: path)

                guard FileManager.default.fileExists(atPath: url.path) else {
                    print("  WARNING: File not found: \(filePath), skipping")
                    continue
                }

                let (questions, format, _) = try DataLoader.load(from: url)
                let formatStr = format == .gameData ? "Game Data" : "Raw"

                var dupes = 0
                for q in questions {
                    let hash = TriviaDatabase.computeTextHash(q.question)
                    if hashSet.contains(hash) {
                        dupes += 1
                    } else {
                        hashSet.insert(hash)
                    }
                    allCategories.insert(CategoryMap.normalize(q.category))
                }

                print("  \(url.lastPathComponent): \(questions.count) questions (\(formatStr)), \(dupes) cross-file dupes")
                totalQuestions += questions.count
                dupeCount += dupes
            }

            print("\nDry run summary:")
            print("  Total questions: \(totalQuestions)")
            print("  Unique (by hash): \(hashSet.count)")
            print("  Duplicates: \(dupeCount)")
            print("  Categories: \(allCategories.count)")
            print("  Would write to: \(dbPath)")
        }
    }
}
