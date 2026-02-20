import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ArgumentParser

struct CtlCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ctl",
        abstract: "Control a running daemon",
        subcommands: [
            CtlStatusCommand.self,
            CtlPauseCommand.self,
            CtlResumeCommand.self,
            CtlStopCommand.self,
            CtlImportCommand.self,
            CtlCategoriesCommand.self,
        ],
        defaultSubcommand: CtlStatusCommand.self
    )
}

// MARK: - Shared helpers

enum CtlHelper {
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

    static func sendRequest(method: String, path: String, port: Int, body: Data? = nil) async throws -> (Int, [String: Any]) {
        let url = URL(string: "http://127.0.0.1:\(port)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (statusCode, json)
    }
}

// MARK: - ctl status

struct CtlStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Show daemon status")

    @Option(name: .long, help: "Daemon control port")
    var port: Int?

    mutating func run() async throws {
        let resolvedPort = try port ?? CtlHelper.discoverPort()
        do {
            let (statusCode, json) = try await CtlHelper.sendRequest(method: "GET", path: "/status", port: resolvedPort)
            guard statusCode == 200 else {
                print("Error: \(json["error"] ?? "Unknown error")")
                throw ExitCode.failure
            }

            print("Daemon Status:")
            print("  State: \(json["state"] ?? "unknown")")
            if let startTime = json["startTime"] as? String {
                print("  Started: \(startTime)")
            }
            print("  Total Fetched: \(json["totalFetched"] ?? 0)")
            print("  Questions Added: \(json["questionsAdded"] ?? 0)")
            print("  Duplicates Skipped: \(json["duplicatesSkipped"] ?? 0)")
            print("  Errors: \(json["errors"] ?? 0)")

            if let providers = json["providers"] as? [[String: Any]] {
                print("\n  Providers:")
                for p in providers {
                    let enabled = (p["enabled"] as? Bool ?? false) ? "ON" : "OFF"
                    let name = p["name"] as? String ?? "?"
                    let fetched = p["fetched"] as? Int ?? 0
                    let added = p["added"] as? Int ?? 0
                    print("    [\(enabled)] \(name): fetched=\(fetched) added=\(added)")
                }
            }
        } catch is URLError {
            print("Error: Could not connect to daemon on port \(resolvedPort)")
            print("Is the daemon running? Start it with: alities-engine run")
            throw ExitCode.failure
        }
    }
}

// MARK: - ctl pause

struct CtlPauseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "pause", abstract: "Pause the daemon")

    @Option(name: .long, help: "Daemon control port")
    var port: Int?

    mutating func run() async throws {
        let resolvedPort = try port ?? CtlHelper.discoverPort()
        let (_, json) = try await CtlHelper.sendRequest(method: "POST", path: "/pause", port: resolvedPort)
        print("Daemon state: \(json["state"] ?? "unknown")")
    }
}

// MARK: - ctl resume

struct CtlResumeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "resume", abstract: "Resume the daemon")

    @Option(name: .long, help: "Daemon control port")
    var port: Int?

    mutating func run() async throws {
        let resolvedPort = try port ?? CtlHelper.discoverPort()
        let (_, json) = try await CtlHelper.sendRequest(method: "POST", path: "/resume", port: resolvedPort)
        print("Daemon state: \(json["state"] ?? "unknown")")
    }
}

// MARK: - ctl stop

struct CtlStopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "stop", abstract: "Gracefully stop the daemon")

    @Option(name: .long, help: "Daemon control port")
    var port: Int?

    mutating func run() async throws {
        let resolvedPort = try port ?? CtlHelper.discoverPort()
        let (_, json) = try await CtlHelper.sendRequest(method: "POST", path: "/stop", port: resolvedPort)
        print("Daemon state: \(json["state"] ?? "stopping")")
        print("Daemon is shutting down gracefully.")
    }
}

// MARK: - ctl import

struct CtlImportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "import", abstract: "Import a JSON file via daemon")

    @Argument(help: "Path to JSON file to import")
    var file: String

    @Option(name: .long, help: "Daemon control port")
    var port: Int?

    mutating func run() async throws {
        let resolvedPort = try port ?? CtlHelper.discoverPort()
        let absPath = NSString(string: file).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: absPath) else {
            print("Error: File not found: \(absPath)")
            throw ExitCode.failure
        }

        let body = try JSONSerialization.data(withJSONObject: ["file": absPath])
        let (statusCode, json) = try await CtlHelper.sendRequest(method: "POST", path: "/import", port: resolvedPort, body: body)

        if statusCode == 200 {
            print("Import complete:")
            print("  Inserted: \(json["inserted"] ?? 0)")
            print("  Duplicates: \(json["duplicates"] ?? 0)")
            print("  Total in file: \(json["total"] ?? 0)")
        } else {
            print("Error: \(json["error"] ?? "Import failed")")
            throw ExitCode.failure
        }
    }
}

// MARK: - ctl categories

struct CtlCategoriesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "categories", abstract: "Show live category counts from daemon")

    @Option(name: .long, help: "Daemon control port")
    var port: Int?

    mutating func run() async throws {
        let resolvedPort = try port ?? CtlHelper.discoverPort()
        let (statusCode, json) = try await CtlHelper.sendRequest(method: "GET", path: "/categories", port: resolvedPort)

        if statusCode == 200 {
            if let categories = json["categories"] as? [[String: Any]] {
                print("Categories (\(json["total"] ?? 0) total):")
                print("  \("Category".padding(toLength: 30, withPad: " ", startingAt: 0))  Count")
                print("  " + String(repeating: "─", count: 40))
                for cat in categories {
                    let name = cat["name"] as? String ?? "?"
                    let count = cat["count"] as? Int ?? 0
                    print("  \(name.padding(toLength: 30, withPad: " ", startingAt: 0))  \(count)")
                }
            }
        } else {
            print("Error: \(json["error"] ?? "Failed to get categories")")
            throw ExitCode.failure
        }
    }
}
