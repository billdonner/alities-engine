import XCTest
import Logging
import AsyncHTTPClient
import NIOPosix
@testable import AlitiesEngine

final class SimilarityServiceTests: XCTestCase {
    private var eventLoopGroup: MultiThreadedEventLoopGroup!
    private var httpClient: HTTPClient!
    private var logger: Logger!

    override func setUp() {
        super.setUp()
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        logger = Logger(label: "test")
        logger.logLevel = .critical // suppress output during tests
    }

    override func tearDown() {
        try? httpClient.syncShutdown()
        try? eventLoopGroup.syncShutdownGracefully()
        super.tearDown()
    }

    // MARK: - Registration and Cache

    func testRegisterAndFindExactMatch() async {
        let service = SimilarityService(httpClient: httpClient, openAIKey: nil, logger: logger)
        let question = makeQuestion(text: "What is the capital of France?", answer: "Paris")
        let id = UUID()

        await service.register(question, id: id)

        let result = await service.findSimilar(question, existingQuestions: [])
        XCTAssertEqual(result, id)
    }

    func testFindSimilarReturnsNilForNewQuestion() async {
        let service = SimilarityService(httpClient: httpClient, openAIKey: nil, logger: logger)
        let question = makeQuestion(text: "What is the capital of France?", answer: "Paris")

        let result = await service.findSimilar(question, existingQuestions: [])
        XCTAssertNil(result)
    }

    func testClearCacheRemovesAllEntries() async {
        let service = SimilarityService(httpClient: httpClient, openAIKey: nil, logger: logger)
        let question = makeQuestion(text: "What is 2 + 2?", answer: "4")
        let id = UUID()

        await service.register(question, id: id)
        await service.clearCache()

        let result = await service.findSimilar(question, existingQuestions: [])
        XCTAssertNil(result)
    }

    func testDifferentQuestionsGetDifferentSignatures() async {
        let service = SimilarityService(httpClient: httpClient, openAIKey: nil, logger: logger)
        let q1 = makeQuestion(text: "What is 2 + 2?", answer: "4")
        let q2 = makeQuestion(text: "What is 3 + 3?", answer: "6")
        let id1 = UUID()
        let id2 = UUID()

        await service.register(q1, id: id1)
        await service.register(q2, id: id2)

        let result1 = await service.findSimilar(q1, existingQuestions: [])
        let result2 = await service.findSimilar(q2, existingQuestions: [])
        XCTAssertEqual(result1, id1)
        XCTAssertEqual(result2, id2)
    }

    // MARK: - Text Similarity via existingQuestions

    func testFindSimilarDetectsHighTextSimilarity() async {
        let service = SimilarityService(httpClient: httpClient, openAIKey: nil, logger: logger)
        // These two questions are nearly identical
        let question = makeQuestion(text: "What is the capital of France", answer: "Paris")
        let existingId = UUID()
        let existing = [(id: existingId, text: "What is the capital of France?", answer: "Paris")]

        let result = await service.findSimilar(question, existingQuestions: existing)
        XCTAssertEqual(result, existingId)
    }

    func testFindSimilarAllowsDifferentQuestions() async {
        let service = SimilarityService(httpClient: httpClient, openAIKey: nil, logger: logger)
        let question = makeQuestion(text: "What is the largest planet in our solar system?", answer: "Jupiter")
        let existingId = UUID()
        let existing = [(id: existingId, text: "What is the smallest country in the world?", answer: "Vatican City")]

        let result = await service.findSimilar(question, existingQuestions: existing)
        XCTAssertNil(result)
    }

    // MARK: - Cache Eviction

    func testCacheEvictsOldEntriesWhenFull() async {
        let service = SimilarityService(httpClient: httpClient, openAIKey: nil, logger: logger)

        // Register more than maxCacheSize (10,000) entries
        for i in 0..<10_050 {
            let q = makeQuestion(text: "Question number \(i)?", answer: "Answer \(i)")
            await service.register(q, id: UUID())
        }

        // The earliest entries should have been evicted
        // Entry 0 should be gone (evicted in the first batch of 2,500)
        let q0 = makeQuestion(text: "Question number 0?", answer: "Answer 0")
        let result = await service.findSimilar(q0, existingQuestions: [])
        XCTAssertNil(result, "Entry 0 should have been evicted from cache")

        // A recent entry should still be in cache
        let qRecent = makeQuestion(text: "Question number 10049?", answer: "Answer 10049")
        let resultRecent = await service.findSimilar(qRecent, existingQuestions: [])
        XCTAssertNotNil(resultRecent, "Recent entry should still be in cache")
    }

    // MARK: - Helpers

    private func makeQuestion(text: String, answer: String) -> TriviaQuestion {
        TriviaQuestion(
            text: text,
            choices: [
                TriviaChoice(text: answer, isCorrect: true),
                TriviaChoice(text: "Wrong 1", isCorrect: false),
                TriviaChoice(text: "Wrong 2", isCorrect: false),
                TriviaChoice(text: "Wrong 3", isCorrect: false),
            ],
            correctChoiceIndex: 0,
            category: "Test",
            difficulty: .medium,
            explanation: nil, hint: nil,
            source: "Test"
        )
    }
}
