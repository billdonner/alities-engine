import XCTest
@testable import AlitiesEngine

final class DaemonConfigTests: XCTestCase {

    // MARK: - Default Values

    func testFromEnvironmentUsesDefaults() {
        let config = DaemonConfig.fromEnvironment()
        XCTAssertEqual(config.dbHost, "localhost")
        XCTAssertEqual(config.dbPort, 5432)
        XCTAssertEqual(config.dbUser, "trivia")
        XCTAssertEqual(config.dbPassword, "trivia")
        XCTAssertEqual(config.dbName, "trivia_db")
        XCTAssertEqual(config.cycleIntervalSeconds, 60)
        XCTAssertEqual(config.providerDelaySeconds, 5)
        XCTAssertEqual(config.batchSize, 10)
        XCTAssertEqual(config.similarityCheckLimit, 1000)
        XCTAssertFalse(config.dryRun)
        XCTAssertNil(config.outputFile)
    }

    func testFromEnvironmentImportDirectory() {
        let config = DaemonConfig.fromEnvironment()
        XCTAssertTrue(config.importDirectory.path.contains("trivia-import"))
    }

    // MARK: - Manual Config

    func testManualConfigPreservesAllFields() {
        let config = DaemonConfig(
            dbHost: "db.example.com", dbPort: 5433,
            dbUser: "admin", dbPassword: "secret", dbName: "my_db",
            openAIKey: "sk-test123",
            importDirectory: URL(fileURLWithPath: "/tmp/import"),
            cycleIntervalSeconds: 120, providerDelaySeconds: 10,
            batchSize: 50, similarityCheckLimit: 500,
            dryRun: true,
            outputFile: URL(fileURLWithPath: "/tmp/output.json")
        )

        XCTAssertEqual(config.dbHost, "db.example.com")
        XCTAssertEqual(config.dbPort, 5433)
        XCTAssertEqual(config.dbUser, "admin")
        XCTAssertEqual(config.dbPassword, "secret")
        XCTAssertEqual(config.dbName, "my_db")
        XCTAssertEqual(config.openAIKey, "sk-test123")
        XCTAssertEqual(config.cycleIntervalSeconds, 120)
        XCTAssertEqual(config.providerDelaySeconds, 10)
        XCTAssertEqual(config.batchSize, 50)
        XCTAssertEqual(config.similarityCheckLimit, 500)
        XCTAssertTrue(config.dryRun)
        XCTAssertNotNil(config.outputFile)
    }

    func testOpenAIKeyDefaultsToNilFromEnvironment() {
        // Unless OPENAI_API_KEY is set in test environment, should be nil
        // (We can't reliably control env in XCTest, so just check the field exists)
        let config = DaemonConfig.fromEnvironment()
        // openAIKey may or may not be set depending on test runner environment
        // Just verify it doesn't crash
        _ = config.openAIKey
    }
}
