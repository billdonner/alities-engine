import Foundation
import ArgumentParser
import AsyncHTTPClient
import NIOCore

struct HarvestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "harvest",
        abstract: "Request targeted AI question generation from running daemon"
    )

    @Option(name: .long, help: "Comma-separated category names")
    var categories: String

    @Option(name: .long, help: "Number of questions to generate")
    var count: Int = 50

    @Option(name: .long, help: "Daemon control port")
    var port: Int?

    mutating func run() async throws {
        let resolvedPort = try port ?? Self.discoverPort()
        let categoryList = categories.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard !categoryList.isEmpty else {
            print("Error: No categories specified")
            throw ExitCode.failure
        }

        let body: [String: Any] = ["categories": categoryList, "count": count]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        defer { try? httpClient.syncShutdown() }

        var request = HTTPClientRequest(url: "http://127.0.0.1:\(resolvedPort)/harvest")
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.body = .bytes(ByteBuffer(data: bodyData))

        do {
            let response = try await httpClient.execute(request, timeout: .seconds(10))
            let responseBody = try await response.body.collect(upTo: 1024 * 1024)
            let json = String(buffer: responseBody)

            if response.status == .accepted || response.status == .ok {
                print("Harvest request accepted:")
                print("  Categories: \(categoryList.joined(separator: ", "))")
                print("  Count: \(count)")
                if let data = json.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let id = dict["id"] {
                    print("  Harvest ID: \(id)")
                }
                print("\nThe daemon is generating questions in the background.")
                print("Use 'alities-engine ctl status' to check progress.")
            } else {
                print("Error (\(response.status)): \(json)")
                throw ExitCode.failure
            }
        } catch let error as HTTPClientError {
            print("Error: Could not connect to daemon on port \(resolvedPort)")
            print("Is the daemon running? Start it with: alities-engine run")
            print("Detail: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    static func discoverPort() throws -> Int {
        let portFile = "/tmp/alities-engine.port"
        guard FileManager.default.fileExists(atPath: portFile),
              let contents = try? String(contentsOfFile: portFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let port = Int(contents) else {
            print("Error: No running daemon found (no port file at \(portFile))")
            print("Start the daemon with: alities-engine run")
            throw ExitCode.failure
        }
        return port
    }
}
