import Foundation
import ArgumentParser
import Logging
import PostgresNIO
import NIOPosix

struct MigrateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate",
        abstract: "Migrate questions from SQLite to PostgreSQL"
    )

    @Option(name: .long, help: "SQLite database path")
    var sqliteDb: String = "~/trivia.db"

    @Option(name: .long, help: "Database host")
    var dbHost: String = "localhost"

    @Option(name: .long, help: "Database port")
    var dbPort: Int = 5432

    @Option(name: .long, help: "Database user")
    var dbUser: String = "trivia"

    @Option(name: .long, help: "Database password")
    var dbPassword: String = "trivia"

    @Option(name: .long, help: "Database name")
    var dbName: String = "trivia_db"

    @Flag(name: .long, help: "Simulate without writing to PostgreSQL")
    var dryRun: Bool = false

    @Flag(name: .shortAndLong, help: "Verbose logging")
    var verbose: Bool = false

    mutating func run() async throws {
        var logger = Logger(label: "alities-engine.migrate")
        logger.logLevel = verbose ? .debug : .info

        let startTime = Date()

        // Open SQLite
        let dbPath = NSString(string: sqliteDb).expandingTildeInPath
        logger.info("Opening SQLite database: \(dbPath)")

        let triviaDB: TriviaDatabase
        do {
            triviaDB = try TriviaDatabase(path: dbPath)
        } catch {
            logger.error("Failed to open SQLite database: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        // Load all questions from SQLite
        logger.info("Loading questions from SQLite...")
        let questions: [ProfiledQuestion]
        do {
            questions = try triviaDB.allQuestions()
        } catch {
            logger.error("Failed to load questions: \(error.localizedDescription)")
            throw ExitCode.failure
        }
        logger.info("Found \(questions.count) questions in SQLite")

        if dryRun {
            // Summarize by category
            var categoryCounts: [String: Int] = [:]
            for q in questions {
                categoryCounts[q.category, default: 0] += 1
            }
            print("")
            print("DRY RUN — Would migrate \(questions.count) questions")
            print("")
            print("Categories:")
            for (cat, count) in categoryCounts.sorted(by: { $0.value > $1.value }) {
                print("  \(cat): \(count)")
            }
            print("")
            let elapsed = Date().timeIntervalSince(startTime)
            print("Elapsed: \(String(format: "%.1f", elapsed))s")
            return
        }

        // Connect to PostgreSQL
        logger.info("Connecting to PostgreSQL: \(dbUser)@\(dbHost):\(dbPort)/\(dbName)")

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? eventLoopGroup.syncShutdownGracefully() }

        let pgConfig = PostgresConnection.Configuration(
            host: dbHost, port: dbPort,
            username: dbUser, password: dbPassword,
            database: dbName, tls: .disable
        )

        let connection = try await PostgresConnection.connect(
            configuration: pgConfig, id: 1, logger: logger
        )
        defer { try? connection.close().wait() }
        logger.info("PostgreSQL connected")

        let pgService = PostgresService(connection: connection, logger: logger)

        // Ensure hint column exists
        try await pgService.ensureHintColumn()

        // Load existing Postgres questions for dedup
        logger.info("Loading existing PostgreSQL questions for dedup...")
        let existingTexts = try await pgService.getAllQuestionTexts()
        logger.info("Found \(existingTexts.count) existing questions in PostgreSQL")

        // Cache for category/source IDs
        var categoryCache: [String: UUID] = [:]
        var sourceCache: [String: UUID] = [:]

        var inserted = 0
        var duplicates = 0
        var errors = 0

        for (index, q) in questions.enumerated() {
            // Progress reporting
            if (index + 1) % 100 == 0 || index == questions.count - 1 {
                logger.info("Progress: \(index + 1)/\(questions.count) (inserted: \(inserted), duplicates: \(duplicates), errors: \(errors))")
            }

            // Check dedup against normalized text
            let normalized = q.question.lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            if existingTexts.contains(normalized) {
                duplicates += 1
                continue
            }

            do {
                // Get or create category
                let categoryId: UUID
                if let cached = categoryCache[q.category] {
                    categoryId = cached
                } else {
                    categoryId = try await pgService.getOrCreateCategory(name: q.category)
                    categoryCache[q.category] = categoryId
                }

                // Get or create source
                let sourceName = q.source ?? "sqlite-import"
                let sourceId: UUID
                if let cached = sourceCache[sourceName] {
                    sourceId = cached
                } else {
                    sourceId = try await pgService.getOrCreateSource(name: sourceName, type: "import")
                    sourceCache[sourceName] = sourceId
                }

                // Build TriviaQuestion
                let choices = q.answers.enumerated().map { (i, text) in
                    TriviaChoice(text: text, isCorrect: i == q.correctIndex)
                }
                let triviaQ = TriviaQuestion(
                    text: q.question,
                    choices: choices,
                    correctChoiceIndex: q.correctIndex,
                    category: q.category,
                    difficulty: Difficulty.from(q.difficulty ?? "medium"),
                    explanation: q.explanation,
                    hint: q.hint,
                    source: sourceName
                )

                _ = try await pgService.insertQuestion(triviaQ, categoryId: categoryId, sourceId: sourceId)
                try await pgService.incrementSourceCount(sourceId: sourceId)
                inserted += 1

            } catch {
                logger.error("Failed to insert question \(index + 1): \(error.localizedDescription)")
                errors += 1
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)

        print("")
        print("═══════════════════════════════════════")
        print("  Migration Complete")
        print("═══════════════════════════════════════")
        print("  Source:     \(dbPath)")
        print("  Target:     \(dbUser)@\(dbHost):\(dbPort)/\(dbName)")
        print("  Total:      \(questions.count)")
        print("  Inserted:   \(inserted)")
        print("  Duplicates: \(duplicates)")
        print("  Errors:     \(errors)")
        print("  Elapsed:    \(String(format: "%.1f", elapsed))s")
        print("═══════════════════════════════════════")
        print("")
    }
}
