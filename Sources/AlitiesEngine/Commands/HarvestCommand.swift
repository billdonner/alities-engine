import Foundation
import ArgumentParser

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
        let resolvedPort = try port ?? CtlHelper.discoverPort()
        let categoryList = categories.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard !categoryList.isEmpty else {
            print("Error: No categories specified")
            throw ExitCode.failure
        }

        let body: [String: Any] = ["categories": categoryList, "count": count]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        let url = URL(string: "http://127.0.0.1:\(resolvedPort)/harvest")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            if statusCode == 202 || statusCode == 200 {
                print("Harvest request accepted:")
                print("  Categories: \(categoryList.joined(separator: ", "))")
                print("  Count: \(count)")
                if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let id = dict["id"] {
                    print("  Harvest ID: \(id)")
                }
                print("\nThe daemon is generating questions in the background.")
                print("Use 'alities-engine ctl status' to check progress.")
            } else {
                let json = String(data: data, encoding: .utf8) ?? ""
                print("Error (\(statusCode)): \(json)")
                throw ExitCode.failure
            }
        } catch is URLError {
            print("Error: Could not connect to daemon on port \(resolvedPort)")
            print("Is the daemon running? Start it with: alities-engine run")
            throw ExitCode.failure
        }
    }
}
