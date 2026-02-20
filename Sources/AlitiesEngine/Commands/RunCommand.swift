import Foundation
import ArgumentParser
import Logging
import AsyncHTTPClient
import PostgresNIO
import NIOCore
import NIOPosix
// MARK: - Run Command (daemon)

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Start the trivia acquisition daemon"
    )

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

    @Option(name: .long, help: "OpenAI API key for AI generation")
    var openaiKey: String?

    @Option(name: .long, help: "Seconds between acquisition cycles")
    var interval: Int = 60

    @Option(name: .long, help: "Questions per batch")
    var batchSize: Int = 10

    @Flag(name: .long, help: "Disable AI generation provider")
    var noAi: Bool = false

    @Flag(name: .shortAndLong, help: "Verbose logging")
    var verbose: Bool = false

    @Flag(name: .long, help: "Simulate without writing to the database")
    var dryRun: Bool = false

    @Option(name: .long, help: "Write questions to a JSON file instead of the database")
    var outputFile: String?

    @Option(name: .long, help: "Control server port (0 to disable)")
    var port: Int = 9847

    @Option(name: .long, help: "Control server bind address")
    var host: String = "127.0.0.1"

    @Option(name: .long, help: "SQLite database path (for local CLI commands only)")
    var db: String = "~/trivia.db"

    @Option(name: .long, help: "Directory for static web files (e.g. alities-studio dist)")
    var staticDir: String?

    mutating func run() async throws {
        var logger = Logger(label: "alities-engine")
        logger.logLevel = verbose ? .debug : .info

        logger.info("Starting Alities Engine Daemon...")

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        defer { try? eventLoopGroup.syncShutdownGracefully() }

        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        defer { try? httpClient.syncShutdown() }

        var dbService: PostgresService? = nil
        var connection: PostgresConnection? = nil

        if !dryRun {
            logger.info("Database: \(dbUser)@\(dbHost):\(dbPort)/\(dbName) (password hidden)")
            logger.info("Connecting to database...")
            let dbConfig = PostgresConnection.Configuration(
                host: dbHost, port: dbPort,
                username: dbUser, password: dbPassword,
                database: dbName, tls: .disable
            )

            do {
                let conn = try await PostgresConnection.connect(
                    configuration: dbConfig, id: 1, logger: logger
                )
                connection = conn
                logger.info("Database connected")
                let pgService = PostgresService(connection: conn, logger: logger)
                try await pgService.ensureHintColumn()
                dbService = pgService
            } catch {
                if outputFile != nil {
                    logger.warning("PostgreSQL unavailable, falling back to file-only mode: \(error.localizedDescription)")
                } else {
                    throw error
                }
            }
        }

        defer {
            if let connection { try? connection.close().wait() }
        }

        let config = DaemonConfig(
            dbHost: dbHost, dbPort: dbPort,
            dbUser: dbUser, dbPassword: dbPassword, dbName: dbName,
            openAIKey: openaiKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
            cycleIntervalSeconds: interval, providerDelaySeconds: 5,
            batchSize: batchSize, similarityCheckLimit: 1000,
            dryRun: dryRun,
            outputFile: outputFile.map { URL(fileURLWithPath: $0) }
        )

        let daemon = TriviaGenDaemon(config: config, db: dbService, httpClient: httpClient, logger: logger)

        if noAi { await daemon.disableProvider("AI Generator") }

        // Setup signal handling
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        signalSource.setEventHandler {
            Task {
                logger.info("Received SIGINT, shutting down gracefully...")
                await daemon.stop()
                // daemon.stop() sets state to .stopped, causing runLoop to exit
                // and run() to return normally with defer cleanup
            }
        }
        signalSource.resume()

        let sigTermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        signal(SIGTERM, SIG_IGN)
        sigTermSource.setEventHandler {
            Task {
                logger.info("Received SIGTERM, shutting down gracefully...")
                await daemon.stop()
            }
        }
        sigTermSource.resume()

        let sigUsr1Source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        signal(SIGUSR1, SIG_IGN)
        sigUsr1Source.setEventHandler {
            Task {
                let currentState = await daemon.state
                if currentState == .running {
                    await daemon.pause()
                } else if currentState == .paused {
                    await daemon.resume()
                }
            }
        }
        sigUsr1Source.resume()

        let writeMode: String
        if dryRun {
            writeMode = "DRY-RUN"
            logger.info("DRY RUN MODE: No questions will be written")
        } else if dbService != nil, let outputFile {
            writeMode = "DUAL-WRITE"
            logger.info("DUAL-WRITE MODE: Writing to both PostgreSQL and \(outputFile)")
        } else if let outputFile {
            writeMode = "FILE-ONLY"
            logger.info("FILE OUTPUT MODE: Writing questions to \(outputFile)")
        } else {
            writeMode = "DATABASE"
            logger.info("DATABASE MODE: Writing to PostgreSQL")
        }

        // Start control server
        var controlServer: ControlServer? = nil
        if port > 0 {
            let resolvedStaticDir = staticDir.map { NSString(string: $0).expandingTildeInPath }
            if let dir = resolvedStaticDir {
                logger.info("Serving static files from \(dir)")
            }
            let server = ControlServer(daemon: daemon, db: dbService, host: host, port: port, logger: logger, staticDirectory: resolvedStaticDir)
            try await server.start(eventLoopGroup: eventLoopGroup)
            controlServer = server
        }


        let controlLine = port > 0 ? "║  Control: http://\(host):\(port)\(String(repeating: " ", count: max(0, 5 - String(port).count)))              ║" : "║  Control: disabled                           ║"
        let modeLine = "║  Mode: \(writeMode)\(String(repeating: " ", count: max(0, 10 - writeMode.count)))                             ║"

        logger.info("""

        ╔══════════════════════════════════════════════╗
        ║       Alities Engine Daemon Started          ║
        ╠══════════════════════════════════════════════╣
        ║  Press Ctrl+C to stop                        ║
        ║  Send SIGUSR1 to pause/resume                ║
        ║  Cycle interval: \(String(repeating: " ", count: max(0, 3 - String(interval).count)))\(interval) seconds                  ║
        ║  Batch size: \(String(repeating: " ", count: max(0, 3 - String(batchSize).count)))\(batchSize) questions                   ║
        \(modeLine)
        \(controlLine)
        ╚══════════════════════════════════════════════╝

        """)

        await daemon.start()

        // Clean up control server before defer blocks shut down the event loop
        if let controlServer {
            await controlServer.stop()
        }
    }
}

// MARK: - List Providers Command

struct ListProvidersCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-providers",
        abstract: "List all available trivia providers"
    )

    mutating func run() throws {
        print("")
        print("Available Trivia Providers:")
        print("───────────────────────────────────────────────────")
        print("  AI Generator")
        print("    Source: OpenAI GPT-4 (requires OPENAI_API_KEY)")
        print("───────────────────────────────────────────────────")
        print("")
        print("Disable with: alities-engine run --no-ai")
        print("")
    }
}

// MARK: - Status Command

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show daemon status"
    )

    mutating func run() async throws {
        print("Status command — daemon runs as foreground process")
        print("Check /tmp/alities-engine.stats.json for runtime stats")
    }
}
