import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import Logging

/// Lightweight HTTP control server for the running daemon
final class ControlServer {
    private let daemon: TriviaGenDaemon
    private let db: PostgresService?
    private let host: String
    private let port: Int
    private let logger: Logger
    private let staticDirectory: String?
    private var channel: Channel?

    init(daemon: TriviaGenDaemon, db: PostgresService?, host: String = "127.0.0.1", port: Int, logger: Logger, staticDirectory: String? = nil) {
        self.daemon = daemon
        self.db = db
        self.host = host
        self.port = port
        self.logger = logger
        self.staticDirectory = staticDirectory
    }

    func start(eventLoopGroup: EventLoopGroup) async throws {
        let daemon = self.daemon
        let db = self.db
        let logger = self.logger

        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [staticDirectory] channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(
                        ControlHTTPHandler(daemon: daemon, db: db, logger: logger, staticDirectory: staticDirectory)
                    )
                }
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)

        let channel = try await bootstrap.bind(host: host, port: port).get()
        self.channel = channel
        logger.info("Control server listening on http://\(host):\(port)")

        // Write port file for CLI discovery
        let portFile = "/tmp/alities-engine.port"
        try "\(port)".write(toFile: portFile, atomically: true, encoding: .utf8)
    }

    func stop() async {
        try? channel?.close().wait()
        try? FileManager.default.removeItem(atPath: "/tmp/alities-engine.port")
    }
}

// MARK: - Route Response

private enum RouteResponse {
    case json(Int, [String: Any])
    case file(Data, String)  // data, contentType
    case notFound
}

// MARK: - HTTP Handler

private final class ControlHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let daemon: TriviaGenDaemon
    private let db: PostgresService?
    private let logger: Logger
    private let staticDirectory: String?

    /// API key for protecting destructive endpoints (from CONTROL_API_KEY env var)
    private let apiKey: String?

    private var requestHead: HTTPRequestHead?
    private var body = ByteBuffer()

    init(daemon: TriviaGenDaemon, db: PostgresService?, logger: Logger, staticDirectory: String? = nil) {
        self.daemon = daemon
        self.db = db
        self.logger = logger
        self.staticDirectory = staticDirectory
        self.apiKey = ProcessInfo.processInfo.environment["CONTROL_API_KEY"]
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            requestHead = head
            body.clear()
        case .body(var buf):
            body.writeBuffer(&buf)
        case .end:
            guard let head = requestHead else { return }
            let bodyData = body.readableBytes > 0 ? body.getData(at: body.readerIndex, length: body.readableBytes) : nil

            let daemon = self.daemon
            let db = self.db
            let logger = self.logger
            let apiKey = self.apiKey
            let path = head.uri.split(separator: "?").first.map(String.init) ?? head.uri
            let method = head.method
            let headers = head.headers

            // Handle CORS preflight
            if method == .OPTIONS {
                self.sendResponse(context: context, status: .ok, body: Data())
                return
            }

            // Handle async route processing
            let staticDirectory = self.staticDirectory
            let promise = context.eventLoop.makePromise(of: RouteResponse.self)
            promise.completeWithTask {
                await Self.handleRoute(method: method, path: path, body: bodyData, headers: headers,
                                       daemon: daemon, db: db, logger: logger, apiKey: apiKey,
                                       staticDirectory: staticDirectory)
            }
            promise.futureResult.whenComplete { result in
                let response: RouteResponse
                switch result {
                case .success(let val):
                    response = val
                case .failure(let error):
                    response = .json(500, ["error": error.localizedDescription])
                }

                switch response {
                case .json(let status, let responseDict):
                    let responseData = (try? JSONSerialization.data(withJSONObject: responseDict, options: .prettyPrinted)) ?? Data()
                    self.sendResponse(context: context, status: HTTPResponseStatus(statusCode: status), body: responseData, contentType: "application/json")
                case .file(let data, let contentType):
                    self.sendResponse(context: context, status: .ok, body: data, contentType: contentType)
                case .notFound:
                    let responseData = (try? JSONSerialization.data(withJSONObject: ["error": "Not found"], options: .prettyPrinted)) ?? Data()
                    self.sendResponse(context: context, status: .notFound, body: responseData, contentType: "application/json")
                }
            }
        }
    }

    /// Check Bearer token authorization for protected endpoints
    private static func isAuthorized(headers: HTTPHeaders, apiKey: String?) -> Bool {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            return true // No key configured = no auth required
        }
        guard let authHeader = headers.first(name: "Authorization") else {
            return false
        }
        return authHeader == "Bearer \(apiKey)"
    }

    private static func handleRoute(
        method: HTTPMethod, path: String, body: Data?, headers: HTTPHeaders,
        daemon: TriviaGenDaemon, db: PostgresService?, logger: Logger, apiKey: String?,
        staticDirectory: String?
    ) async -> RouteResponse {

        switch (method, path) {

        // MARK: - Public GET endpoints

        case (.GET, "/health"):
            return .json(200, ["ok": true])

        case (.GET, "/metrics"):
            var metrics: [[String: Any]] = []

            // Daemon state
            let stats = await daemon.getExportedStats()
            let stateStr = await daemon.state.stringValue
            metrics.append(["key": "daemon_state", "label": "Daemon State", "value": stateStr])

            // Uptime (from stats start time)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(stats),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let startTime = dict["startTime"] as? String {
                let fmt = ISO8601DateFormatter()
                if let start = fmt.date(from: startTime) {
                    let uptime = Int(Date().timeIntervalSince(start))
                    metrics.append(["key": "uptime_seconds", "label": "Uptime", "value": uptime, "unit": "seconds"])
                }
            }

            // Memory usage
            let memBytes = ProcessInfo.processInfo.physicalMemory
            metrics.append(["key": "system_memory_gb", "label": "System Memory", "value": Double(memBytes) / 1_073_741_824.0, "unit": "GB"])

            // Daemon stats
            if let data = try? encoder.encode(stats),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let fetched = dict["totalFetched"] as? Int {
                    metrics.append(["key": "total_fetched", "label": "Questions Fetched", "value": fetched, "unit": "count"])
                }
                if let added = dict["questionsAdded"] as? Int {
                    metrics.append(["key": "questions_added", "label": "Questions Added", "value": added, "unit": "count"])
                }
                if let dupes = dict["duplicatesSkipped"] as? Int {
                    metrics.append(["key": "duplicates_skipped", "label": "Duplicates Skipped", "value": dupes, "unit": "count"])
                }
                if let errors = dict["errors"] as? Int {
                    metrics.append(["key": "errors", "label": "Errors", "value": errors, "unit": "count", "warn_above": 0])
                }
                // Provider status
                if let providers = dict["providers"] as? [[String: Any]] {
                    for p in providers {
                        let name = p["name"] as? String ?? "unknown"
                        let pFetched = p["fetched"] as? Int ?? 0
                        metrics.append(["key": "provider_\(name.lowercased())_fetched", "label": "\(name) Fetched", "value": pFetched, "unit": "count"])
                    }
                }
            }

            // PostgreSQL stats
            if let db = db {
                do {
                    let dbStats = try await db.stats()
                    metrics.append(["key": "db_questions", "label": "DB Questions", "value": dbStats.totalQuestions, "unit": "count"])
                    metrics.append(["key": "db_categories", "label": "DB Categories", "value": dbStats.totalCategories, "unit": "count"])
                    metrics.append(["key": "db_sources", "label": "DB Sources", "value": dbStats.totalSources, "unit": "count"])
                } catch {
                    logger.warning("Failed to get PostgreSQL stats for /metrics: \(error)")
                }
            }

            return .json(200, ["metrics": metrics])

        case (.GET, "/status"):
            let stats = await daemon.getExportedStats()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(stats),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return .json(200, dict)
            }
            return .json(200, ["state": await daemon.state.stringValue])

        case (.GET, "/categories"):
            guard let db = db else {
                return .json(503, ["error": "No database configured"])
            }
            do {
                let cats = try await db.categoriesWithCounts()
                let list = cats.map { ["name": $0.name, "pic": CategoryMap.symbol(for: $0.name), "count": $0.count] as [String: Any] }
                return .json(200, ["categories": list, "total": cats.count])
            } catch {
                return .json(500, ["error": error.localizedDescription])
            }

        case (.GET, "/gamedata"):
            guard let db = db else {
                return .json(503, ["error": "No database configured"])
            }
            do {
                let questions = try await db.allQuestionsProfiled()
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
                let output = GameDataOutput(
                    id: UUID().uuidString,
                    generated: Date().timeIntervalSinceReferenceDate,
                    challenges: challenges
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? encoder.encode(output),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    return .json(200, dict)
                }
                return .json(500, ["error": "Failed to encode game data"])
            } catch {
                return .json(500, ["error": error.localizedDescription])
            }

        // MARK: - Protected POST endpoints (require Bearer token if CONTROL_API_KEY is set)

        case (.POST, "/harvest"):
            guard isAuthorized(headers: headers, apiKey: apiKey) else {
                return .json(401, ["error": "Unauthorized — Bearer token required"])
            }
            guard let body = body,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let categories = json["categories"] as? [String] else {
                return .json(400, ["error": "Request body must include 'categories' array"])
            }
            guard !categories.isEmpty else {
                return .json(400, ["error": "'categories' array must not be empty"])
            }
            let rawCount = json["count"] as? Int ?? 50
            let count = max(1, min(rawCount, 1000))
            let harvestId = UUID().uuidString.prefix(8).lowercased()

            // Fire off harvest in background
            Task {
                let result = await daemon.harvestCategories(categories, count: count)
                logger.info("Harvest \(harvestId) complete: fetched=\(result.fetched) added=\(result.added) errors=\(result.errors)")
            }
            return .json(202, ["accepted": true, "id": String(harvestId), "categories": categories, "count": count])

        case (.POST, "/pause"):
            guard isAuthorized(headers: headers, apiKey: apiKey) else {
                return .json(401, ["error": "Unauthorized — Bearer token required"])
            }
            await daemon.pause()
            return .json(200, ["state": "paused"])

        case (.POST, "/resume"):
            guard isAuthorized(headers: headers, apiKey: apiKey) else {
                return .json(401, ["error": "Unauthorized — Bearer token required"])
            }
            await daemon.resume()
            return .json(200, ["state": "running"])

        case (.POST, "/stop"):
            guard isAuthorized(headers: headers, apiKey: apiKey) else {
                return .json(401, ["error": "Unauthorized — Bearer token required"])
            }
            // Schedule stop after responding
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay for response
                await daemon.stop()
            }
            return .json(200, ["state": "stopping"])

        case (.POST, "/import"):
            guard isAuthorized(headers: headers, apiKey: apiKey) else {
                return .json(401, ["error": "Unauthorized — Bearer token required"])
            }
            guard let db = db else {
                return .json(503, ["error": "No database configured"])
            }
            guard let body = body,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let filePath = json["file"] as? String else {
                return .json(400, ["error": "Request body must include 'file' path"])
            }

            guard FileManager.default.fileExists(atPath: filePath) else {
                return .json(404, ["error": "File not found: \(filePath)"])
            }

            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
                let questions = try JSONDecoder().decode([TriviaQuestion].self, from: data)
                var inserted = 0
                for q in questions {
                    let catId = try await db.getOrCreateCategory(name: q.category)
                    let sourceId = try await db.getOrCreateSource(name: q.source ?? "import")
                    _ = try await db.insertQuestion(q, categoryId: catId, sourceId: sourceId)
                    inserted += 1
                }
                return .json(200, ["inserted": inserted, "total": questions.count])
            } catch {
                return .json(500, ["error": "Import failed: \(error.localizedDescription)"])
            }

        default:
            // Try serving static files if a static directory is configured
            if method == .GET, let staticDir = staticDirectory {
                return serveStaticFile(path: path, from: staticDir)
            }
            return .notFound
        }
    }

    // MARK: - Static File Serving

    private static let contentTypeMap: [String: String] = [
        ".html": "text/html",
        ".js": "application/javascript",
        ".css": "text/css",
        ".svg": "image/svg+xml",
        ".json": "application/json",
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".gif": "image/gif",
        ".ico": "image/x-icon",
        ".woff": "font/woff",
        ".woff2": "font/woff2",
        ".ttf": "font/ttf",
        ".map": "application/json",
        ".txt": "text/plain",
    ]

    private static func serveStaticFile(path: String, from staticDir: String) -> RouteResponse {
        // Normalize: strip leading slash
        var relativePath = path
        if relativePath.hasPrefix("/") {
            relativePath = String(relativePath.dropFirst())
        }

        // Security: prevent directory traversal
        guard !relativePath.contains("..") else {
            return .notFound
        }

        let fm = FileManager.default

        // If path has no file extension, serve index.html (SPA fallback)
        let ext = (relativePath as NSString).pathExtension
        if ext.isEmpty {
            let indexPath = (staticDir as NSString).appendingPathComponent("index.html")
            if let data = fm.contents(atPath: indexPath) {
                return .file(data, "text/html")
            }
            return .notFound
        }

        // Resolve file path
        let filePath = (staticDir as NSString).appendingPathComponent(relativePath)
        guard let data = fm.contents(atPath: filePath) else {
            return .notFound
        }

        let dotExt = ".\(ext)"
        let contentType = contentTypeMap[dotExt] ?? "application/octet-stream"
        return .file(data, contentType)
    }

    private func sendResponse(context: ChannelHandlerContext, status: HTTPResponseStatus, body: Data, contentType: String = "application/json") {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: contentType)
        headers.add(name: "Content-Length", value: "\(body.count)")
        headers.add(name: "Connection", value: "close")
        // CORS headers for studio web app
        headers.add(name: "Access-Control-Allow-Origin", value: "*")
        headers.add(name: "Access-Control-Allow-Methods", value: "GET, POST, OPTIONS")
        headers.add(name: "Access-Control-Allow-Headers", value: "Content-Type, Authorization")

        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        var buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
}
