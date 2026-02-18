import XCTest
@testable import AlitiesEngine

final class ReportTests: XCTestCase {

    // MARK: - Report Generation

    func testGenerateBasicReport() {
        let questions = sampleQuestions()
        let report = ReportGenerator.generate(
            from: questions,
            fileDetails: [.init(name: "test.json", questionCount: 4, fileSize: "1 KB", format: "raw")],
            totalFileSize: 1024,
            generated: nil,
            hasDifficulty: true
        )

        XCTAssertEqual(report.summary.totalQuestions, 4)
        XCTAssertEqual(report.summary.fileCount, 1)
    }

    func testCategoryGrouping() {
        let questions = sampleQuestions()
        let report = ReportGenerator.generate(
            from: questions, fileDetails: [], totalFileSize: 0,
            generated: nil, hasDifficulty: true
        )

        XCTAssertEqual(report.categories.count, 2) // Science (3) and History (1)
        XCTAssertEqual(report.categories[0].name, "Science")
        XCTAssertEqual(report.categories[0].count, 3)
        XCTAssertEqual(report.categories[1].name, "History")
        XCTAssertEqual(report.categories[1].count, 1)
    }

    func testCategoryPercentages() {
        let questions = sampleQuestions()
        let report = ReportGenerator.generate(
            from: questions, fileDetails: [], totalFileSize: 0,
            generated: nil, hasDifficulty: true
        )

        XCTAssertEqual(report.categories[0].percentage, 75.0) // 3/4
        XCTAssertEqual(report.categories[1].percentage, 25.0) // 1/4
    }

    func testSourceGrouping() {
        let questions = sampleQuestions()
        let report = ReportGenerator.generate(
            from: questions, fileDetails: [], totalFileSize: 0,
            generated: nil, hasDifficulty: true
        )

        XCTAssertEqual(report.sources.count, 2) // opentdb (3) and test (1)
        XCTAssertEqual(report.sources[0].count, 3)
        XCTAssertEqual(report.sources[1].count, 1)
    }

    func testDifficultyOrdering() {
        let questions = sampleQuestions()
        let report = ReportGenerator.generate(
            from: questions, fileDetails: [], totalFileSize: 0,
            generated: nil, hasDifficulty: true
        )

        guard let difficulty = report.difficulty else {
            XCTFail("Expected difficulty data")
            return
        }

        // Should be ordered: easy, medium, hard
        let levels = difficulty.map(\.level)
        XCTAssertEqual(levels, ["easy", "medium", "hard"])
    }

    func testDifficultyNilWhenNoDifficulty() {
        let questions = [
            ProfiledQuestion(question: "Q?", answers: ["A"], correctAnswer: "A",
                           correctIndex: 0, category: "Test", difficulty: nil,
                           explanation: nil, hint: nil, source: nil),
        ]
        let report = ReportGenerator.generate(
            from: questions, fileDetails: [], totalFileSize: 0,
            generated: nil, hasDifficulty: false
        )

        XCTAssertNil(report.difficulty)
    }

    func testHintStats() {
        let questions = sampleQuestions()
        let report = ReportGenerator.generate(
            from: questions, fileDetails: [], totalFileSize: 0,
            generated: nil, hasDifficulty: true
        )

        XCTAssertEqual(report.hints.withHints, 2)
        XCTAssertEqual(report.hints.withoutHints, 2)
        XCTAssertEqual(report.hints.sampleHints.count, 2)
    }

    func testQuestionLength() {
        let questions = sampleQuestions()
        let report = ReportGenerator.generate(
            from: questions, fileDetails: [], totalFileSize: 0,
            generated: nil, hasDifficulty: true
        )

        XCTAssertGreaterThan(report.questionLength.maxChars, 0)
        XCTAssertGreaterThan(report.questionLength.minChars, 0)
        XCTAssertGreaterThanOrEqual(report.questionLength.maxChars, report.questionLength.minChars)
        XCTAssertGreaterThanOrEqual(report.questionLength.avgChars, report.questionLength.minChars)
        XCTAssertLessThanOrEqual(report.questionLength.avgChars, report.questionLength.maxChars)
    }

    func testAnswerStats() {
        let questions = sampleQuestions()
        let report = ReportGenerator.generate(
            from: questions, fileDetails: [], totalFileSize: 0,
            generated: nil, hasDifficulty: true
        )

        XCTAssertGreaterThan(report.answerStats.avgAnswersPerQuestion, 0)
        XCTAssertFalse(report.answerStats.correctPositionDistribution.isEmpty)
    }

    // MARK: - Text Rendering

    func testTextRendererProducesOutput() {
        let report = makeReport()
        let text = TextRenderer.render(report)
        XCTAssertTrue(text.contains("Summary"))
        XCTAssertTrue(text.contains("Categories"))
        XCTAssertTrue(text.contains("Sources"))
    }

    func testTextRendererSectionFilter() {
        let report = makeReport()
        let summaryOnly = TextRenderer.render(report, section: "summary")
        XCTAssertTrue(summaryOnly.contains("Summary"))
        XCTAssertFalse(summaryOnly.contains("Categories"))
    }

    // MARK: - JSON Rendering

    func testJSONRendererProducesValidJSON() throws {
        let report = makeReport()
        let json = JSONRenderer.render(report)
        let data = json.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(parsed is [String: Any])
    }

    func testJSONRendererSectionFilter() throws {
        let report = makeReport()
        let json = JSONRenderer.render(report, section: "summary")
        let data = json.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(parsed?["totalQuestions"])
    }

    // MARK: - ReportData Codable

    func testReportDataCodable() throws {
        let report = makeReport()
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(ReportData.self, from: data)
        XCTAssertEqual(decoded.summary.totalQuestions, report.summary.totalQuestions)
        XCTAssertEqual(decoded.categories.count, report.categories.count)
    }

    // MARK: - Helpers

    private func sampleQuestions() -> [ProfiledQuestion] {
        [
            ProfiledQuestion(question: "What is H2O?", answers: ["Water", "Salt", "Oil", "Sugar"],
                           correctAnswer: "Water", correctIndex: 0, category: "Science",
                           difficulty: "easy", explanation: nil, hint: "You drink it", source: "opentdb"),
            ProfiledQuestion(question: "What is the speed of light?", answers: ["300k km/s", "150k km/s"],
                           correctAnswer: "300k km/s", correctIndex: 0, category: "Science",
                           difficulty: "hard", explanation: "In vacuum", hint: nil, source: "opentdb"),
            ProfiledQuestion(question: "What is DNA?", answers: ["Molecule", "Protein", "Cell"],
                           correctAnswer: "Molecule", correctIndex: 0, category: "Science",
                           difficulty: "medium", explanation: nil, hint: "Double helix", source: "opentdb"),
            ProfiledQuestion(question: "When was WWII?", answers: ["1939", "1940", "1941"],
                           correctAnswer: "1939", correctIndex: 0, category: "History",
                           difficulty: "easy", explanation: nil, hint: nil, source: "test"),
        ]
    }

    private func makeReport() -> ReportData {
        ReportGenerator.generate(
            from: sampleQuestions(), fileDetails: [], totalFileSize: 0,
            generated: nil, hasDifficulty: true
        )
    }
}
