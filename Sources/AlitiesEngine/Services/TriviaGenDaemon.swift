import Foundation
import Logging
import AsyncHTTPClient

/// Main daemon service that orchestrates trivia acquisition
actor TriviaGenDaemon {
    enum State {
        case stopped
        case running
        case paused
    }

    private let config: DaemonConfig
    private let logger: Logger
    private let httpClient: HTTPClient
    private let db: PostgresService?
    private let similarity: SimilarityService
    private var providers: [TriviaProvider]
    private var collectedQuestions: [TriviaQuestion] = []

    private(set) var state: State = .stopped
    private var stats: DaemonStats

    init(config: DaemonConfig, db: PostgresService?, httpClient: HTTPClient, logger: Logger) {
        self.config = config
        self.logger = logger
        self.httpClient = httpClient
        self.db = db
        self.similarity = SimilarityService(httpClient: httpClient, openAIKey: config.openAIKey, logger: logger)
        self.stats = DaemonStats()

        self.providers = [
            OpenTriviaDBProvider(httpClient: httpClient),
            TheTriviaAPIProvider(httpClient: httpClient),
            JServiceProvider(httpClient: httpClient),
            AIGeneratorProvider(httpClient: httpClient, apiKey: config.openAIKey),
            FileImportProvider(watchDirectory: config.importDirectory)
        ]
    }

    // MARK: - Control Methods

    func start() async {
        guard state == .stopped else {
            logger.warning("Daemon already running or paused")
            return
        }
        state = .running
        logger.info("Trivia Gen Daemon started")
        stats.startTime = Date()
        writeStatsFile()
        await runLoop()
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
        logger.info("Daemon paused")
    }

    func resume() {
        guard state == .paused else { return }
        state = .running
        logger.info("Daemon resumed")
        Task { await self.runLoop() }
    }

    func stop() {
        state = .stopped
        if config.outputFile != nil { writeOutputFile() }
        logger.info("Daemon stopped")
        writeStatsFile()
        logStats()
    }

    func getStats() -> DaemonStats { return stats }

    func getExportedStats() -> ExportedDaemonStats {
        let providerStatuses = providers.map { provider in
            let pStats = stats.providerStats[provider.name] ?? ProviderStats()
            return ProviderStatus(
                name: provider.name, enabled: provider.isEnabled,
                fetched: pStats.fetched, added: pStats.added,
                duplicates: pStats.duplicates, errors: pStats.errors
            )
        }
        return ExportedDaemonStats(
            state: state.stringValue, startTime: stats.startTime,
            totalFetched: stats.totalFetched, questionsAdded: stats.questionsAdded,
            duplicatesSkipped: stats.duplicatesSkipped, errors: stats.errors,
            providers: providerStatuses
        )
    }

    /// Harvest questions for specific categories using AI provider
    func harvestCategories(_ categories: [String], count: Int) async -> (fetched: Int, added: Int, errors: Int) {
        guard let aiProvider = providers.first(where: { $0 is AIGeneratorProvider }) as? AIGeneratorProvider else {
            logger.error("AI Generator provider not found")
            return (0, 0, 1)
        }

        logger.info("Harvesting \(count) questions for categories: \(categories.joined(separator: ", "))")

        do {
            let questions = try await aiProvider.fetchQuestions(count: count, categories: categories)
            logger.info("Harvest fetched \(questions.count) questions")

            let prevAdded = stats.questionsAdded
            for question in questions {
                await processQuestion(question, from: "AI Generator (harvest)")
            }

            stats.totalFetched += questions.count
            if config.outputFile != nil { writeOutputFile() }
            writeStatsFile()

            let added = stats.questionsAdded - prevAdded
            return (questions.count, added, 0)
        } catch {
            logger.error("Harvest failed: \(error.localizedDescription)")
            return (0, 0, 1)
        }
    }

    private func writeOutputFile() {
        guard let outputFile = config.outputFile else { return }
        guard !collectedQuestions.isEmpty else { return }

        let rawFile = outputFile.deletingPathExtension()
            .appendingPathExtension("raw")
            .appendingPathExtension("json")

        var allQuestions = [TriviaQuestion]()
        if FileManager.default.fileExists(atPath: rawFile.path) {
            if let data = try? Data(contentsOf: rawFile),
               let existing = try? JSONDecoder().decode([TriviaQuestion].self, from: data) {
                allQuestions = existing
            }
        }

        let previousCount = allQuestions.count
        allQuestions.append(contentsOf: collectedQuestions)
        collectedQuestions.removeAll()

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let rawData = try encoder.encode(allQuestions)
            try rawData.write(to: rawFile)

            let gameData = GameDataTransformer.transform(questions: allQuestions)
            let gameDataBytes = try encoder.encode(gameData)
            try gameDataBytes.write(to: outputFile)

            logger.info("Wrote \(allQuestions.count) questions to \(outputFile.path) (\(allQuestions.count - previousCount) new, \(gameData.challenges.count) challenges)")
        } catch {
            logger.error("Failed to write output file: \(error.localizedDescription)")
        }
    }

    func writeStatsFile() {
        let statsPath = "/tmp/alities-engine.stats.json"
        let providerStatuses = providers.map { provider in
            let pStats = stats.providerStats[provider.name] ?? ProviderStats()
            return ProviderStatus(
                name: provider.name, enabled: provider.isEnabled,
                fetched: pStats.fetched, added: pStats.added,
                duplicates: pStats.duplicates, errors: pStats.errors
            )
        }

        let exportStats = ExportedDaemonStats(
            state: state.stringValue, startTime: stats.startTime,
            totalFetched: stats.totalFetched, questionsAdded: stats.questionsAdded,
            duplicatesSkipped: stats.duplicatesSkipped, errors: stats.errors,
            providers: providerStatuses
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(exportStats)
            try data.write(to: URL(fileURLWithPath: statsPath))
        } catch {
            logger.error("Failed to write stats file: \(error.localizedDescription)")
        }
    }

    func enableProvider(_ name: String) {
        for i in providers.indices {
            if providers[i].name.lowercased() == name.lowercased() {
                providers[i].isEnabled = true
                logger.info("Enabled provider: \(name)")
            }
        }
    }

    func disableProvider(_ name: String) {
        for i in providers.indices {
            if providers[i].name.lowercased() == name.lowercased() {
                providers[i].isEnabled = false
                logger.info("Disabled provider: \(name)")
            }
        }
    }

    // MARK: - Main Loop

    private func runLoop() async {
        while state == .running {
            await processProviders()
            if config.outputFile != nil { writeOutputFile() }
            writeStatsFile()
            // Sleep in 1-second increments so shutdown signals are responsive
            for _ in 0..<config.cycleIntervalSeconds {
                guard state == .running else { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func processProviders() async {
        let enabledProviders = providers.filter { $0.isEnabled }

        for provider in enabledProviders {
            guard state == .running else { break }

            if stats.providerStats[provider.name] == nil {
                stats.providerStats[provider.name] = ProviderStats()
            }

            do {
                logger.info("Fetching from \(provider.name)...")
                let questions = try await provider.fetchQuestions(count: config.batchSize)

                if questions.isEmpty {
                    logger.info("\(provider.name): No questions returned")
                    continue
                }

                logger.info("\(provider.name): Fetched \(questions.count) questions")
                stats.totalFetched += questions.count
                stats.providerStats[provider.name]?.fetched += questions.count

                for question in questions {
                    guard state == .running else { break }
                    await processQuestion(question, from: provider.name)
                }

                try? await Task.sleep(nanoseconds: UInt64(config.providerDelaySeconds) * 1_000_000_000)

            } catch ProviderError.rateLimited {
                logger.warning("\(provider.name): Rate limited, will retry later")
                stats.rateLimitHits += 1
            } catch ProviderError.apiKeyMissing {
                logger.warning("\(provider.name): API key not configured, skipping")
            } catch {
                logger.error("\(provider.name) error: \(error.localizedDescription)")
                stats.errors += 1
                stats.providerStats[provider.name]?.errors += 1
            }
        }
    }

    private func processQuestion(_ question: TriviaQuestion, from providerName: String) async {
        do {
            if config.dryRun {
                logger.info("[DRY RUN] Would add question: \(question.text.prefix(80))...")
                stats.questionsAdded += 1
                stats.providerStats[providerName]?.added += 1
                return
            }

            // File output (always runs if outputFile is set)
            if config.outputFile != nil {
                collectedQuestions.append(question)
                logger.info("Collected question: \(question.text.prefix(60))...")
            }

            // PostgreSQL insert (runs if db is available)
            if let db {
                let existingQuestions = try await db.getExistingQuestions(limit: config.similarityCheckLimit)

                if let similarId = await similarity.findSimilar(question, existingQuestions: existingQuestions) {
                    logger.debug("Skipping Postgres duplicate (similar to \(similarId)): \(question.text.prefix(50))...")
                    stats.duplicatesSkipped += 1
                    stats.providerStats[providerName]?.duplicates += 1
                    // Still count as added if file output succeeded
                    if config.outputFile != nil {
                        stats.questionsAdded += 1
                        stats.providerStats[providerName]?.added += 1
                    }
                    return
                }

                do {
                    let categoryId = try await db.getOrCreateCategory(name: question.category)
                    let sourceId = try await db.getOrCreateSource(name: providerName, type: "api")
                    let questionId = try await db.insertQuestion(question, categoryId: categoryId, sourceId: sourceId)
                    try await db.incrementSourceCount(sourceId: sourceId)
                    await similarity.register(question, id: questionId)
                    logger.info("Added to Postgres: \(question.text.prefix(50))...")
                } catch {
                    if config.outputFile != nil {
                        logger.warning("Postgres insert failed (file write succeeded): \(error.localizedDescription)")
                    } else {
                        throw error
                    }
                }
            } else if config.outputFile == nil {
                logger.error("No database connection and no output file configured")
                return
            }

            stats.questionsAdded += 1
            stats.providerStats[providerName]?.added += 1

        } catch {
            logger.error("Failed to process question: \(error.localizedDescription)")
            stats.errors += 1
            stats.providerStats[providerName]?.errors += 1
        }
    }

    private func logStats() {
        let runtime = Date().timeIntervalSince(stats.startTime ?? Date())
        logger.info("""
        === Daemon Statistics ===
        Runtime: \(Int(runtime)) seconds
        Total Fetched: \(stats.totalFetched)
        Questions Added: \(stats.questionsAdded)
        Duplicates Skipped: \(stats.duplicatesSkipped)
        Rate Limit Hits: \(stats.rateLimitHits)
        Errors: \(stats.errors)
        =========================
        """)
    }
}

// MARK: - Configuration

struct DaemonConfig {
    let dbHost: String
    let dbPort: Int
    let dbUser: String
    let dbPassword: String
    let dbName: String
    let openAIKey: String?
    let importDirectory: URL
    let cycleIntervalSeconds: Int
    let providerDelaySeconds: Int
    let batchSize: Int
    let similarityCheckLimit: Int
    let dryRun: Bool
    let outputFile: URL?

    static func fromEnvironment() -> DaemonConfig {
        DaemonConfig(
            dbHost: ProcessInfo.processInfo.environment["DB_HOST"] ?? "localhost",
            dbPort: Int(ProcessInfo.processInfo.environment["DB_PORT"] ?? "5432") ?? 5432,
            dbUser: ProcessInfo.processInfo.environment["DB_USER"] ?? "trivia",
            dbPassword: ProcessInfo.processInfo.environment["DB_PASSWORD"] ?? "trivia",
            dbName: ProcessInfo.processInfo.environment["DB_NAME"] ?? "trivia_db",
            openAIKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
            importDirectory: URL(fileURLWithPath: ProcessInfo.processInfo.environment["IMPORT_DIR"] ?? "/tmp/trivia-import"),
            cycleIntervalSeconds: Int(ProcessInfo.processInfo.environment["CYCLE_INTERVAL"] ?? "60") ?? 60,
            providerDelaySeconds: Int(ProcessInfo.processInfo.environment["PROVIDER_DELAY"] ?? "5") ?? 5,
            batchSize: Int(ProcessInfo.processInfo.environment["BATCH_SIZE"] ?? "10") ?? 10,
            similarityCheckLimit: Int(ProcessInfo.processInfo.environment["SIMILARITY_LIMIT"] ?? "1000") ?? 1000,
            dryRun: false, outputFile: nil
        )
    }
}

// MARK: - Statistics

struct ProviderStats {
    var fetched: Int = 0
    var added: Int = 0
    var duplicates: Int = 0
    var errors: Int = 0
}

struct DaemonStats {
    var startTime: Date?
    var totalFetched: Int = 0
    var questionsAdded: Int = 0
    var duplicatesSkipped: Int = 0
    var rateLimitHits: Int = 0
    var errors: Int = 0
    var providerStats: [String: ProviderStats] = [:]
}

struct ProviderStatus: Codable {
    let name: String
    let enabled: Bool
    let fetched: Int
    let added: Int
    let duplicates: Int
    let errors: Int
}

struct ExportedDaemonStats: Codable {
    let state: String
    let startTime: Date?
    let totalFetched: Int
    let questionsAdded: Int
    let duplicatesSkipped: Int
    let errors: Int
    let providers: [ProviderStatus]
}

extension TriviaGenDaemon.State {
    var stringValue: String {
        switch self {
        case .stopped: return "stopped"
        case .running: return "running"
        case .paused: return "paused"
        }
    }
}
