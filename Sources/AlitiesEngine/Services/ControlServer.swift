import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import Logging

/// Lightweight HTTP control server for the running daemon
final class ControlServer {
    private let daemon: TriviaGenDaemon
    private let triviaDB: TriviaDatabase?
    private let port: Int
    private let logger: Logger
    private var channel: Channel?

    init(daemon: TriviaGenDaemon, triviaDB: TriviaDatabase?, port: Int, logger: Logger) {
        self.daemon = daemon
        self.triviaDB = triviaDB
        self.port = port
        self.logger = logger
    }

    func start(eventLoopGroup: EventLoopGroup) async throws {
        let daemon = self.daemon
        let triviaDB = self.triviaDB
        let logger = self.logger

        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(
                        ControlHTTPHandler(daemon: daemon, triviaDB: triviaDB, logger: logger)
                    )
                }
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)

        let channel = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
        self.channel = channel
        logger.info("Control server listening on http://127.0.0.1:\(port)")

        // Write port file for CLI discovery
        let portFile = "/tmp/alities-engine.port"
        try "\(port)".write(toFile: portFile, atomically: true, encoding: .utf8)
    }

    func stop() async {
        try? channel?.close().wait()
        try? FileManager.default.removeItem(atPath: "/tmp/alities-engine.port")
    }
}

// MARK: - HTTP Handler

private final class ControlHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let daemon: TriviaGenDaemon
    private let triviaDB: TriviaDatabase?
    private let logger: Logger

    private var requestHead: HTTPRequestHead?
    private var body = ByteBuffer()

    init(daemon: TriviaGenDaemon, triviaDB: TriviaDatabase?, logger: Logger) {
        self.daemon = daemon
        self.triviaDB = triviaDB
        self.logger = logger
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
            let triviaDB = self.triviaDB
            let logger = self.logger
            let path = head.uri.split(separator: "?").first.map(String.init) ?? head.uri
            let method = head.method

            // Handle async route processing
            let promise = context.eventLoop.makePromise(of: (Int, [String: Any]).self)
            promise.completeWithTask {
                await Self.handleRoute(method: method, path: path, body: bodyData,
                                       daemon: daemon, triviaDB: triviaDB, logger: logger)
            }
            promise.futureResult.whenComplete { result in
                let (status, responseDict): (Int, [String: Any])
                switch result {
                case .success(let val):
                    (status, responseDict) = val
                case .failure(let error):
                    (status, responseDict) = (500, ["error": error.localizedDescription])
                }

                let responseData = (try? JSONSerialization.data(withJSONObject: responseDict, options: .prettyPrinted)) ?? Data()
                self.sendResponse(context: context, status: HTTPResponseStatus(statusCode: status), body: responseData)
            }
        }
    }

    private static func handleRoute(
        method: HTTPMethod, path: String, body: Data?,
        daemon: TriviaGenDaemon, triviaDB: TriviaDatabase?, logger: Logger
    ) async -> (Int, [String: Any]) {

        switch (method, path) {
        case (.GET, "/status"):
            let stats = await daemon.getExportedStats()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(stats),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return (200, dict)
            }
            return (200, ["state": await daemon.state.stringValue])

        case (.GET, "/categories"):
            guard let db = triviaDB else {
                return (503, ["error": "No SQLite database configured"])
            }
            do {
                let cats = try db.allCategories()
                let list = cats.map { ["name": $0.name, "pic": $0.pic, "count": $0.count] as [String: Any] }
                return (200, ["categories": list, "total": cats.count])
            } catch {
                return (500, ["error": error.localizedDescription])
            }

        case (.POST, "/harvest"):
            guard let body = body,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let categories = json["categories"] as? [String] else {
                return (400, ["error": "Request body must include 'categories' array"])
            }
            guard !categories.isEmpty else {
                return (400, ["error": "'categories' array must not be empty"])
            }
            let rawCount = json["count"] as? Int ?? 50
            let count = max(1, min(rawCount, 1000))
            let harvestId = UUID().uuidString.prefix(8).lowercased()

            // Fire off harvest in background
            Task {
                let result = await daemon.harvestCategories(categories, count: count)
                logger.info("Harvest \(harvestId) complete: fetched=\(result.fetched) added=\(result.added) errors=\(result.errors)")

                if triviaDB != nil, result.added > 0 {
                    logger.info("Harvest results will be available in next daemon cycle output")
                }
            }
            return (202, ["accepted": true, "id": String(harvestId), "categories": categories, "count": count])

        case (.POST, "/pause"):
            await daemon.pause()
            return (200, ["state": "paused"])

        case (.POST, "/resume"):
            await daemon.resume()
            return (200, ["state": "running"])

        case (.POST, "/stop"):
            // Schedule stop after responding — daemon.stop() sets state to .stopped
            // which causes runLoop to exit, allowing normal program termination with defers
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay for response
                await daemon.stop()
            }
            return (200, ["state": "stopping"])

        case (.POST, "/import"):
            guard let db = triviaDB else {
                return (503, ["error": "No SQLite database configured"])
            }
            guard let body = body,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let filePath = json["file"] as? String else {
                return (400, ["error": "Request body must include 'file' path"])
            }

            guard FileManager.default.fileExists(atPath: filePath) else {
                return (404, ["error": "File not found: \(filePath)"])
            }

            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
                let questions = try JSONDecoder().decode([TriviaQuestion].self, from: data)
                var inserted = 0
                var duplicates = 0
                for q in questions {
                    let catId = try db.getOrCreateCategory(name: q.category)
                    let choices = q.choices.map { ChoiceEntry(text: $0.text, isCorrect: $0.isCorrect) }
                    let result = try db.insertQuestion(
                        text: q.text, choices: choices, correctIndex: q.correctChoiceIndex,
                        categoryId: catId, difficulty: q.difficulty.rawValue,
                        explanation: q.explanation, hint: q.hint,
                        source: q.source, importedFrom: filePath
                    )
                    switch result {
                    case .inserted: inserted += 1
                    case .duplicate: duplicates += 1
                    }
                }
                return (200, ["inserted": inserted, "duplicates": duplicates, "total": questions.count])
            } catch {
                return (500, ["error": "Import failed: \(error.localizedDescription)"])
            }

        default:
            return (404, ["error": "Not found: \(path)"])
        }
    }

    private func sendResponse(context: ChannelHandlerContext, status: HTTPResponseStatus, body: Data) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Content-Length", value: "\(body.count)")
        headers.add(name: "Connection", value: "close")

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
