import XCTest
@testable import AlitiesEngine

final class TriviaDatabaseTests: XCTestCase {

    // MARK: - Text Hashing

    func testComputeTextHashDeterministic() {
        let hash1 = TriviaDatabase.computeTextHash("What is the capital of France?")
        let hash2 = TriviaDatabase.computeTextHash("What is the capital of France?")
        XCTAssertEqual(hash1, hash2)
    }

    func testComputeTextHashCaseInsensitive() {
        let hash1 = TriviaDatabase.computeTextHash("Hello World")
        let hash2 = TriviaDatabase.computeTextHash("hello world")
        XCTAssertEqual(hash1, hash2)
    }

    func testComputeTextHashIgnoresWhitespace() {
        let hash1 = TriviaDatabase.computeTextHash("Hello World")
        let hash2 = TriviaDatabase.computeTextHash("Hello   World")
        let hash3 = TriviaDatabase.computeTextHash("Hello\nWorld")
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
    }

    func testComputeTextHashIgnoresPunctuation() {
        let hash1 = TriviaDatabase.computeTextHash("What is this?")
        let hash2 = TriviaDatabase.computeTextHash("What is this")
        XCTAssertEqual(hash1, hash2)
    }

    func testComputeTextHashDifferentTextsDifferentHashes() {
        let hash1 = TriviaDatabase.computeTextHash("Question one")
        let hash2 = TriviaDatabase.computeTextHash("Question two")
        XCTAssertNotEqual(hash1, hash2)
    }

    func testComputeTextHashIsSHA256Length() {
        let hash = TriviaDatabase.computeTextHash("Test")
        XCTAssertEqual(hash.count, 64) // SHA-256 = 32 bytes = 64 hex chars
    }

    // MARK: - Database Operations

    func testCreateDatabase() throws {
        let db = try makeTestDB()
        let stats = try db.stats()
        XCTAssertEqual(stats.totalQuestions, 0)
        XCTAssertEqual(stats.totalCategories, 0)
    }

    func testGetOrCreateCategory() throws {
        let db = try makeTestDB()
        let id1 = try db.getOrCreateCategory(name: "Science", pic: "atom")
        let id2 = try db.getOrCreateCategory(name: "Science", pic: "atom")
        XCTAssertEqual(id1, id2) // Same category, same ID

        let id3 = try db.getOrCreateCategory(name: "History", pic: "clock")
        XCTAssertNotEqual(id1, id3)
    }

    func testInsertQuestion() throws {
        let db = try makeTestDB()
        let catId = try db.getOrCreateCategory(name: "Science", pic: "atom")
        let result = try db.insertQuestion(
            text: "What is H2O?",
            choices: [ChoiceEntry(text: "Water", isCorrect: true), ChoiceEntry(text: "Salt", isCorrect: false)],
            correctIndex: 0,
            categoryId: catId,
            difficulty: "easy",
            explanation: "Chemical formula",
            hint: "You drink it",
            source: "test",
            importedFrom: "test.json"
        )
        XCTAssertEqual(result, .inserted)

        let stats = try db.stats()
        XCTAssertEqual(stats.totalQuestions, 1)
        XCTAssertEqual(stats.easyCount, 1)
    }

    func testInsertDuplicateQuestion() throws {
        let db = try makeTestDB()
        let catId = try db.getOrCreateCategory(name: "Science")

        let choices = [ChoiceEntry(text: "A", isCorrect: true)]
        let r1 = try db.insertQuestion(text: "What is H2O?", choices: choices, correctIndex: 0,
                                        categoryId: catId, difficulty: "easy", explanation: nil,
                                        hint: nil, source: "test", importedFrom: nil)
        let r2 = try db.insertQuestion(text: "What is H2O?", choices: choices, correctIndex: 0,
                                        categoryId: catId, difficulty: "easy", explanation: nil,
                                        hint: nil, source: "test", importedFrom: nil)
        XCTAssertEqual(r1, .inserted)
        XCTAssertEqual(r2, .duplicate)

        let stats = try db.stats()
        XCTAssertEqual(stats.totalQuestions, 1)
    }

    func testInsertDuplicateNormalized() throws {
        let db = try makeTestDB()
        let catId = try db.getOrCreateCategory(name: "Science")
        let choices = [ChoiceEntry(text: "A", isCorrect: true)]

        let r1 = try db.insertQuestion(text: "What is H2O?", choices: choices, correctIndex: 0,
                                        categoryId: catId, difficulty: nil, explanation: nil,
                                        hint: nil, source: "test", importedFrom: nil)
        let r2 = try db.insertQuestion(text: "what is h2o", choices: choices, correctIndex: 0,
                                        categoryId: catId, difficulty: nil, explanation: nil,
                                        hint: nil, source: "test", importedFrom: nil)
        XCTAssertEqual(r1, .inserted)
        XCTAssertEqual(r2, .duplicate)
    }

    func testDifficultyNormalization() throws {
        let db = try makeTestDB()
        let catId = try db.getOrCreateCategory(name: "Science")
        let choices = [ChoiceEntry(text: "A", isCorrect: true)]

        // Valid difficulties
        _ = try db.insertQuestion(text: "Q1", choices: choices, correctIndex: 0,
                                   categoryId: catId, difficulty: "EASY", explanation: nil,
                                   hint: nil, source: "test", importedFrom: nil)

        // Invalid difficulty becomes nil
        _ = try db.insertQuestion(text: "Q2", choices: choices, correctIndex: 0,
                                   categoryId: catId, difficulty: "impossible", explanation: nil,
                                   hint: nil, source: "test", importedFrom: nil)

        let stats = try db.stats()
        XCTAssertEqual(stats.easyCount, 1)
        XCTAssertEqual(stats.noDifficultyCount, 1)
    }

    func testAllQuestions() throws {
        let db = try makeTestDB()
        let catId = try db.getOrCreateCategory(name: "Science", pic: "atom")
        let choices = [ChoiceEntry(text: "Water", isCorrect: true), ChoiceEntry(text: "Salt", isCorrect: false)]

        _ = try db.insertQuestion(text: "Q1?", choices: choices, correctIndex: 0,
                                   categoryId: catId, difficulty: "easy", explanation: "E1",
                                   hint: "H1", source: "opentdb", importedFrom: nil)
        _ = try db.insertQuestion(text: "Q2?", choices: choices, correctIndex: 0,
                                   categoryId: catId, difficulty: "hard", explanation: nil,
                                   hint: nil, source: "opentdb", importedFrom: nil)

        let all = try db.allQuestions()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].question, "Q1?")
        XCTAssertEqual(all[0].category, "Science")
        XCTAssertEqual(all[0].answers, ["Water", "Salt"])
        XCTAssertEqual(all[0].correctAnswer, "Water")
    }

    func testAllQuestionsWithFilters() throws {
        let db = try makeTestDB()
        let sciId = try db.getOrCreateCategory(name: "Science", pic: "atom")
        let hisId = try db.getOrCreateCategory(name: "History", pic: "clock")
        let choices = [ChoiceEntry(text: "A", isCorrect: true)]

        _ = try db.insertQuestion(text: "SciQ?", choices: choices, correctIndex: 0,
                                   categoryId: sciId, difficulty: "easy", explanation: nil,
                                   hint: nil, source: "opentdb", importedFrom: nil)
        _ = try db.insertQuestion(text: "HisQ?", choices: choices, correctIndex: 0,
                                   categoryId: hisId, difficulty: "hard", explanation: nil,
                                   hint: nil, source: "test", importedFrom: nil)

        let sciOnly = try db.allQuestions(category: "Science")
        XCTAssertEqual(sciOnly.count, 1)
        XCTAssertEqual(sciOnly[0].question, "SciQ?")

        let easyOnly = try db.allQuestions(difficulty: "easy")
        XCTAssertEqual(easyOnly.count, 1)

        let testOnly = try db.allQuestions(source: "test")
        XCTAssertEqual(testOnly.count, 1)
        XCTAssertEqual(testOnly[0].question, "HisQ?")

        let limited = try db.allQuestions(limit: 1)
        XCTAssertEqual(limited.count, 1)
    }

    func testAllCategories() throws {
        let db = try makeTestDB()
        let sciId = try db.getOrCreateCategory(name: "Science", pic: "atom")
        _ = try db.getOrCreateCategory(name: "History", pic: "clock")
        let choices = [ChoiceEntry(text: "A", isCorrect: true)]

        _ = try db.insertQuestion(text: "Q1", choices: choices, correctIndex: 0,
                                   categoryId: sciId, difficulty: nil, explanation: nil,
                                   hint: nil, source: "test", importedFrom: nil)

        let cats = try db.allCategories()
        XCTAssertEqual(cats.count, 2)
        XCTAssertEqual(cats[0].name, "Science")
        XCTAssertEqual(cats[0].count, 1)
        XCTAssertEqual(cats[1].name, "History")
        XCTAssertEqual(cats[1].count, 0)
    }

    func testAliases() throws {
        let db = try makeTestDB()
        _ = try db.getOrCreateCategory(name: "Science & Nature", pic: "atom")
        try db.addAlias("science", forCategory: "Science & Nature")
        try db.addAlias("nature", forCategory: "Science & Nature")

        let aliases = try db.allAliases()
        XCTAssertEqual(aliases.count, 2)
        XCTAssertTrue(aliases.contains { $0.alias == "science" && $0.canonical == "Science & Nature" })
        XCTAssertTrue(aliases.contains { $0.alias == "nature" && $0.canonical == "Science & Nature" })
    }

    func testResolveCategoryId() throws {
        let db = try makeTestDB()
        try CategoryMap.seedDatabase(db)

        // Resolve via alias
        let sciId = try db.resolveCategoryId(for: "science")
        let natId = try db.resolveCategoryId(for: "nature")
        XCTAssertEqual(sciId, natId) // Both map to "Science & Nature"

        // Resolve unknown creates new category
        let newId = try db.resolveCategoryId(for: "Quantum Physics")
        XCTAssertNotEqual(newId, sciId)
    }

    func testStats() throws {
        let db = try makeTestDB()
        let catId = try db.getOrCreateCategory(name: "Science")
        let choices = [ChoiceEntry(text: "A", isCorrect: true)]

        _ = try db.insertQuestion(text: "Q1", choices: choices, correctIndex: 0,
                                   categoryId: catId, difficulty: "easy", explanation: nil,
                                   hint: nil, source: "src1", importedFrom: nil)
        _ = try db.insertQuestion(text: "Q2", choices: choices, correctIndex: 0,
                                   categoryId: catId, difficulty: "medium", explanation: nil,
                                   hint: nil, source: "src2", importedFrom: nil)
        _ = try db.insertQuestion(text: "Q3", choices: choices, correctIndex: 0,
                                   categoryId: catId, difficulty: "hard", explanation: nil,
                                   hint: nil, source: "src1", importedFrom: nil)

        let stats = try db.stats()
        XCTAssertEqual(stats.totalQuestions, 3)
        XCTAssertEqual(stats.totalCategories, 1)
        XCTAssertEqual(stats.totalSources, 2)
        XCTAssertEqual(stats.easyCount, 1)
        XCTAssertEqual(stats.mediumCount, 1)
        XCTAssertEqual(stats.hardCount, 1)
        XCTAssertEqual(stats.noDifficultyCount, 0)
    }

    // MARK: - Helpers

    private func makeTestDB() throws -> TriviaDatabase {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).sqlite").path
        return try TriviaDatabase(path: path)
    }
}
