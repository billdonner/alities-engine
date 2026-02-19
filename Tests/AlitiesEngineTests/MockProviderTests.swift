import XCTest
@testable import AlitiesEngine

// MARK: - Mock Provider

private final class MockProvider: TriviaProvider {
    let name: String
    var isEnabled: Bool
    var questionsToReturn: [TriviaQuestion]
    var errorToThrow: Error?
    var fetchCallCount: Int = 0

    init(name: String = "MockProvider", isEnabled: Bool = true, questions: [TriviaQuestion] = []) {
        self.name = name
        self.isEnabled = isEnabled
        self.questionsToReturn = questions
    }

    func fetchQuestions(count: Int) async throws -> [TriviaQuestion] {
        fetchCallCount += 1
        if let error = errorToThrow {
            throw error
        }
        return Array(questionsToReturn.prefix(count))
    }
}

// MARK: - Tests

final class MockProviderTests: XCTestCase {

    // MARK: - Protocol Conformance

    func testProviderHasName() {
        let provider = MockProvider(name: "TestProvider")
        XCTAssertEqual(provider.name, "TestProvider")
    }

    func testProviderStartsEnabled() {
        let provider = MockProvider()
        XCTAssertTrue(provider.isEnabled)
    }

    func testProviderCanBeDisabled() {
        let provider = MockProvider()
        provider.isEnabled = false
        XCTAssertFalse(provider.isEnabled)
    }

    // MARK: - Fetch Behavior

    func testFetchReturnsQuestionsUpToCount() async throws {
        let questions = (0..<5).map { makeTriviaQuestion(index: $0) }
        let provider = MockProvider(questions: questions)

        let result = try await provider.fetchQuestions(count: 3)
        XCTAssertEqual(result.count, 3)
    }

    func testFetchReturnsAllWhenCountExceedsAvailable() async throws {
        let questions = [makeTriviaQuestion(index: 0)]
        let provider = MockProvider(questions: questions)

        let result = try await provider.fetchQuestions(count: 10)
        XCTAssertEqual(result.count, 1)
    }

    func testFetchReturnsEmptyWhenNoQuestions() async throws {
        let provider = MockProvider()
        let result = try await provider.fetchQuestions(count: 10)
        XCTAssertTrue(result.isEmpty)
    }

    func testFetchThrowsNetworkError() async {
        let provider = MockProvider()
        provider.errorToThrow = ProviderError.networkError("Connection refused")

        do {
            _ = try await provider.fetchQuestions(count: 10)
            XCTFail("Expected error to be thrown")
        } catch let error as ProviderError {
            if case .networkError(let message) = error {
                XCTAssertEqual(message, "Connection refused")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchThrowsRateLimited() async {
        let provider = MockProvider()
        provider.errorToThrow = ProviderError.rateLimited

        do {
            _ = try await provider.fetchQuestions(count: 10)
            XCTFail("Expected error to be thrown")
        } catch let error as ProviderError {
            if case .rateLimited = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchThrowsApiKeyMissing() async {
        let provider = MockProvider()
        provider.errorToThrow = ProviderError.apiKeyMissing

        do {
            _ = try await provider.fetchQuestions(count: 10)
            XCTFail("Expected error to be thrown")
        } catch let error as ProviderError {
            if case .apiKeyMissing = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchTracksCallCount() async throws {
        let provider = MockProvider()
        _ = try await provider.fetchQuestions(count: 1)
        _ = try await provider.fetchQuestions(count: 1)
        _ = try await provider.fetchQuestions(count: 1)
        XCTAssertEqual(provider.fetchCallCount, 3)
    }

    // MARK: - Provider Error Descriptions

    func testProviderErrorNetworkDescription() {
        let error = ProviderError.networkError("timeout")
        XCTAssertNotNil(error.errorDescription)
        XCTAssert(error.errorDescription!.contains("timeout"))
    }

    func testProviderErrorParseDescription() {
        let error = ProviderError.parseError("invalid JSON")
        XCTAssertNotNil(error.errorDescription)
        XCTAssert(error.errorDescription!.contains("invalid JSON"))
    }

    func testProviderErrorRateLimitedDescription() {
        let error = ProviderError.rateLimited
        XCTAssertNotNil(error.errorDescription)
    }

    func testProviderErrorApiKeyMissingDescription() {
        let error = ProviderError.apiKeyMissing
        XCTAssertNotNil(error.errorDescription)
    }

    func testProviderErrorNoResultsDescription() {
        let error = ProviderError.noResults
        XCTAssertNotNil(error.errorDescription)
    }

    func testProviderErrorInvalidResponseDescription() {
        let error = ProviderError.invalidResponse
        XCTAssertNotNil(error.errorDescription)
    }

    // MARK: - Helpers

    private func makeTriviaQuestion(index: Int) -> TriviaQuestion {
        TriviaQuestion(
            text: "Question \(index)?",
            choices: [
                TriviaChoice(text: "A", isCorrect: false),
                TriviaChoice(text: "B", isCorrect: true),
                TriviaChoice(text: "C", isCorrect: false),
                TriviaChoice(text: "D", isCorrect: false),
            ],
            correctChoiceIndex: 1,
            category: "Test",
            difficulty: .medium,
            explanation: nil, hint: nil,
            source: "MockProvider"
        )
    }
}
