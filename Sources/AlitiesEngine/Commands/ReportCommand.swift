import ArgumentParser
import Foundation

struct ReportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Profile and report on trivia question data"
    )

    @Argument(help: "Path(s) to JSON trivia data file(s). If none given, reads from database.")
    var files: [String] = []

    @Option(name: .long, help: "Path to SQLite database (default: ~/trivia.db)")
    var db: String = "~/trivia.db"

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Show only a specific section: summary, categories, sources, difficulty, hints, length, answers")
    var section: String? = nil

    func run() throws {
        if files.isEmpty {
            try runFromDatabase()
        } else {
            try runFromFiles()
        }
    }

    private func runFromDatabase() throws {
        let dbPath = (db as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: dbPath) else {
            print("Database not found at \(dbPath). Run 'alities-engine import' first, or provide JSON file(s).")
            throw ExitCode.failure
        }

        let triviaDB = try TriviaDatabase(path: dbPath)
        let allQuestions = try triviaDB.allQuestions()

        guard !allQuestions.isEmpty else {
            print("Database is empty. Run 'alities-engine import' to load data.")
            return
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: dbPath)
        let fileSize = (attrs[.size] as? Int) ?? 0

        let fileDetails: [ReportData.FileDetail] = [
            .init(name: "trivia.db", questionCount: allQuestions.count,
                  fileSize: ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file),
                  format: "SQLite")
        ]

        let hasDifficulty = allQuestions.contains { $0.difficulty != nil }

        let report = ReportGenerator.generate(
            from: allQuestions, fileDetails: fileDetails,
            totalFileSize: fileSize, generated: nil, hasDifficulty: hasDifficulty
        )

        if json {
            print(JSONRenderer.render(report, section: section))
        } else {
            print(TextRenderer.render(report, section: section))
        }
    }

    private func runFromFiles() throws {
        var allQuestions: [ProfiledQuestion] = []
        var totalFileSize = 0
        var fileDetails: [ReportData.FileDetail] = []
        var latestGenerated: Date? = nil
        var hasDifficulty = false

        for filePath in files {
            let path = (filePath as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: path)

            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ProfileError.fileNotFound(filePath)
            }

            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = (attrs[.size] as? Int) ?? 0
            totalFileSize += fileSize

            let (questions, format, generated) = try DataLoader.load(from: url)
            allQuestions.append(contentsOf: questions)

            if format == .raw { hasDifficulty = true }

            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
            let formatStr = format == .gameData ? "Game Data" : "Raw"
            fileDetails.append(.init(
                name: url.lastPathComponent, questionCount: questions.count,
                fileSize: sizeStr, format: formatStr
            ))

            if let generated {
                if latestGenerated == nil || generated > latestGenerated! {
                    latestGenerated = generated
                }
            }
        }

        let report = ReportGenerator.generate(
            from: allQuestions, fileDetails: fileDetails,
            totalFileSize: totalFileSize, generated: latestGenerated,
            hasDifficulty: hasDifficulty
        )

        if json {
            print(JSONRenderer.render(report, section: section))
        } else {
            print(TextRenderer.render(report, section: section))
        }
    }
}
