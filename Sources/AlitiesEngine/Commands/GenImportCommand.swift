import Foundation
import ArgumentParser
import Logging
import AsyncHTTPClient
import PostgresNIO
import NIOCore
import NIOPosix

/// Import trivia from a file directly into PostgreSQL (from trivia-gen-daemon)
struct GenImportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gen-import",
        abstract: "Import trivia from a file into PostgreSQL"
    )

    @Argument(help: "Path to JSON or CSV file")
    var file: String

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

    mutating func run() async throws {
        var logger = Logger(label: "alities-engine")
        logger.logLevel = .info

        guard FileManager.default.fileExists(atPath: file) else {
            print("Error: File not found: \(file)")
            return
        }

        print("Importing from: \(file)")

        let fileURL = URL(fileURLWithPath: file)
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? eventLoopGroup.syncShutdownGracefully() }

        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        defer { try? httpClient.syncShutdown() }

        let dbConfig = PostgresConnection.Configuration(
            host: dbHost, port: dbPort,
            username: dbUser, password: dbPassword,
            database: dbName, tls: .disable
        )

        let connection = try await PostgresConnection.connect(
            configuration: dbConfig, id: 1, logger: logger
        )
        defer { try? connection.close().wait() }

        let dbService = PostgresService(connection: connection, logger: logger)
        let importProvider = FileImportProvider(watchDirectory: fileURL.deletingLastPathComponent())

        let tempURL = fileURL.deletingLastPathComponent().appendingPathComponent("_import_\(fileURL.lastPathComponent)")
        try FileManager.default.copyItem(at: fileURL, to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            let questions = try await importProvider.fetchQuestions(count: 10000)
            print("Found \(questions.count) questions")

            var added = 0
            var skipped = 0

            let similarity = SimilarityService(httpClient: httpClient, openAIKey: nil, logger: logger)
            let existingQuestions = try await dbService.getExistingQuestions()

            for question in questions {
                if await similarity.findSimilar(question, existingQuestions: existingQuestions) != nil {
                    skipped += 1
                    continue
                }

                let categoryId = try await dbService.getOrCreateCategory(name: question.category)
                let sourceId = try await dbService.getOrCreateSource(name: "File Import", type: "manual")
                let questionId = try await dbService.insertQuestion(question, categoryId: categoryId, sourceId: sourceId)
                try await dbService.incrementSourceCount(sourceId: sourceId)
                await similarity.register(question, id: questionId)
                added += 1
            }

            print("Import complete: \(added) added, \(skipped) duplicates skipped")

        } catch {
            print("Import failed: \(error)")
        }
    }
}
