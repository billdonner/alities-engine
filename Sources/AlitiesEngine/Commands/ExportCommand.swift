import ArgumentParser
import Foundation

struct ExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export questions from SQLite database to JSON"
    )

    @Argument(help: "Output file path (default: stdout)")
    var output: String? = nil

    @Option(name: .long, help: "Path to SQLite database (default: ~/trivia.db)")
    var db: String = "~/trivia.db"

    @Option(name: .long, help: "Output format: raw or gamedata")
    var format: String = "raw"

    @Option(name: .long, help: "Filter by category name")
    var category: String? = nil

    @Option(name: .long, help: "Filter by difficulty: easy, medium, hard")
    var difficulty: String? = nil

    @Option(name: .long, help: "Maximum number of questions to export")
    var limit: Int? = nil

    func run() throws {
        let dbPath = (db as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: dbPath) else {
            print("Database not found at \(dbPath). Run 'alities-engine import' first.")
            throw ExitCode.failure
        }

        let triviaDB = try TriviaDatabase(path: dbPath)
        let questions = try triviaDB.allQuestions(
            category: category, difficulty: difficulty, limit: limit
        )

        guard !questions.isEmpty else {
            print("No questions match the specified filters.")
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let jsonData: Data

        if format == "gamedata" {
            let challenges = questions.map { q in
                Challenge(
                    topic: q.category,
                    pic: CategoryMap.symbol(for: q.category),
                    question: q.question,
                    answers: q.answers,
                    correct: q.correctAnswer,
                    explanation: q.explanation ?? "",
                    hint: q.hint ?? "",
                    aisource: q.source ?? "unknown",
                    date: Date().timeIntervalSinceReferenceDate
                )
            }
            let gameDataOutput = GameDataOutput(
                id: UUID().uuidString,
                generated: Date().timeIntervalSinceReferenceDate,
                challenges: challenges
            )
            jsonData = try encoder.encode(gameDataOutput)
        } else {
            let rawQuestions = questions.map { q in
                RawQuestion(
                    text: q.question,
                    choices: q.answers.enumerated().map { (i, text) in
                        RawChoice(text: text, isCorrect: i == q.correctIndex)
                    },
                    correctChoiceIndex: q.correctIndex,
                    category: q.category,
                    difficulty: q.difficulty,
                    explanation: q.explanation,
                    hint: q.hint,
                    source: q.source
                )
            }
            jsonData = try encoder.encode(rawQuestions)
        }

        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"

        if let outputPath = output {
            let path = (outputPath as NSString).expandingTildeInPath
            try jsonString.write(toFile: path, atomically: true, encoding: .utf8)
            print("Exported \(questions.count) questions to \(path)")
        } else {
            print(jsonString)
        }
    }
}
