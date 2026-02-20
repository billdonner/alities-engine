import Foundation
import PostgresNIO
import Logging

/// Service for PostgreSQL database operations (from trivia-gen-daemon)
actor PostgresService {
    private let connection: PostgresConnection
    private let logger: Logger

    init(connection: PostgresConnection, logger: Logger) {
        self.connection = connection
        self.logger = logger
    }

    // MARK: - Categories

    func getOrCreateCategory(name: String, choiceCount: Int = 4) async throws -> UUID {
        let rows = try await connection.query(
            "SELECT id FROM categories WHERE name = \(name)",
            logger: logger
        )

        for try await id in rows.decode(UUID.self) {
            return id
        }

        let newId = UUID()
        try await connection.query(
            """
            INSERT INTO categories (id, name, description, choice_count, is_auto_generated, created_at, updated_at)
            VALUES (\(newId), \(name), \("Auto-generated category"), \(choiceCount), true, NOW(), NOW())
            """,
            logger: logger
        )

        logger.info("Created new category: \(name)")
        return newId
    }

    func getAllCategories() async throws -> [Category] {
        var categories: [Category] = []

        let rows = try await connection.query(
            "SELECT id, name, description, choice_count FROM categories ORDER BY name",
            logger: logger
        )

        for try await (id, name, description, choiceCount) in rows.decode((UUID, String, String?, Int).self) {
            categories.append(Category(id: id, name: name, description: description, choiceCount: choiceCount))
        }

        return categories
    }

    // MARK: - Sources

    func getOrCreateSource(name: String, type: String = "api") async throws -> UUID {
        let rows = try await connection.query(
            "SELECT id FROM question_sources WHERE name = \(name)",
            logger: logger
        )

        for try await id in rows.decode(UUID.self) {
            return id
        }

        let newId = UUID()
        try await connection.query(
            """
            INSERT INTO question_sources (id, name, type, question_count, created_at, updated_at)
            VALUES (\(newId), \(name), \(type)::source_type, 0, NOW(), NOW())
            """,
            logger: logger
        )

        logger.info("Created new source: \(name)")
        return newId
    }

    func incrementSourceCount(sourceId: UUID) async throws {
        try await connection.query(
            "UPDATE question_sources SET question_count = question_count + 1, updated_at = NOW() WHERE id = \(sourceId)",
            logger: logger
        )
    }

    // MARK: - Questions

    func getExistingQuestions(limit: Int = 1000) async throws -> [(id: UUID, text: String, answer: String)] {
        var questions: [(id: UUID, text: String, answer: String)] = []

        let rows = try await connection.query(
            """
            SELECT id, text, choices::text, correct_choice_index
            FROM questions
            ORDER BY created_at DESC
            LIMIT \(limit)
            """,
            logger: logger
        )

        for try await (id, text, choicesJson, correctIndex) in rows.decode((UUID, String, String, Int).self) {
            var answer = ""
            if let data = choicesJson.data(using: .utf8),
               let wrapper = try? JSONDecoder().decode(PGChoicesWrapper.self, from: data) {
                if correctIndex >= 0 && correctIndex < wrapper.items.count {
                    answer = wrapper.items[correctIndex].text
                }
            }
            questions.append((id: id, text: text, answer: answer))
        }

        return questions
    }

    func insertQuestion(_ question: TriviaQuestion, categoryId: UUID, sourceId: UUID) async throws -> UUID {
        let questionId = UUID()

        let choicesWrapper = PGChoicesWrapper(items: question.choices.map {
            PGChoiceItem(text: $0.text, isCorrect: $0.isCorrect)
        })
        let choicesData = try JSONEncoder().encode(choicesWrapper)
        let choicesJson = String(data: choicesData, encoding: .utf8) ?? "{\"items\":[]}"
        let difficultyStr = question.difficulty.rawValue
        let explanationStr = question.explanation ?? ""
        let hintStr = question.hint ?? ""

        try await connection.query(
            """
            INSERT INTO questions (id, text, choices, correct_choice_index, category_id, source_id, difficulty, explanation, hint, created_at, updated_at)
            VALUES (\(questionId), \(question.text), \(choicesJson)::jsonb, \(question.correctChoiceIndex), \(categoryId), \(sourceId), \(difficultyStr)::difficulty, \(explanationStr), \(hintStr), NOW(), NOW())
            """,
            logger: logger
        )

        return questionId
    }

    /// Idempotent: adds hint column to questions table if missing
    func ensureHintColumn() async throws {
        let rows = try await connection.query(
            """
            SELECT column_name FROM information_schema.columns
            WHERE table_name = 'questions' AND column_name = 'hint'
            """,
            logger: logger
        )

        var exists = false
        for try await _ in rows.decode(String.self) {
            exists = true
        }

        if !exists {
            try await connection.query(
                "ALTER TABLE questions ADD COLUMN hint TEXT DEFAULT ''",
                logger: logger
            )
            logger.info("Added hint column to questions table")
        }
    }

    /// Load all existing question texts (normalized) for O(1) dedup during migration
    func getAllQuestionTexts() async throws -> Set<String> {
        var texts = Set<String>()
        let rows = try await connection.query(
            "SELECT text FROM questions",
            logger: logger
        )
        for try await text in rows.decode(String.self) {
            let normalized = text.lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            texts.insert(normalized)
        }
        return texts
    }

    // MARK: - Control Server Queries

    /// Categories with question counts (for /categories endpoint)
    struct CategoryWithCount: Sendable {
        let name: String
        let count: Int
    }

    func categoriesWithCounts() async throws -> [CategoryWithCount] {
        var result: [CategoryWithCount] = []
        let rows = try await connection.query(
            """
            SELECT c.name, COUNT(q.id)::int as count
            FROM categories c
            LEFT JOIN questions q ON q.category_id = c.id
            GROUP BY c.id, c.name
            ORDER BY count DESC
            """,
            logger: logger
        )
        for try await (name, count) in rows.decode((String, Int).self) {
            result.append(CategoryWithCount(name: name, count: count))
        }
        return result
    }

    /// All questions with category/source info (for /gamedata endpoint)
    func allQuestionsProfiled() async throws -> [ProfiledQuestion] {
        var result: [ProfiledQuestion] = []
        let rows = try await connection.query(
            """
            SELECT q.text, q.choices::text, q.correct_choice_index, c.name,
                   q.difficulty::text, q.explanation, q.hint, qs.name
            FROM questions q
            JOIN categories c ON c.id = q.category_id
            LEFT JOIN question_sources qs ON qs.id = q.source_id
            ORDER BY q.created_at DESC
            """,
            logger: logger
        )
        for try await (text, choicesJson, correctIndex, categoryName, difficulty, explanation, hint, sourceName)
            in rows.decode((String, String, Int, String, String?, String?, String?, String?).self) {
            var answers: [String] = []
            var correctAnswer = ""
            if let data = choicesJson.data(using: .utf8),
               let wrapper = try? JSONDecoder().decode(PGChoicesWrapper.self, from: data) {
                answers = wrapper.items.map { $0.text }
                if correctIndex >= 0 && correctIndex < wrapper.items.count {
                    correctAnswer = wrapper.items[correctIndex].text
                }
            }
            result.append(ProfiledQuestion(
                question: text,
                answers: answers,
                correctAnswer: correctAnswer,
                correctIndex: correctIndex,
                category: categoryName,
                difficulty: difficulty,
                explanation: explanation,
                hint: hint,
                source: sourceName
            ))
        }
        return result
    }

    /// Quick stats (for /metrics endpoint)
    struct QuickStats: Sendable {
        let totalQuestions: Int
        let totalCategories: Int
        let totalSources: Int
    }

    func stats() async throws -> QuickStats {
        var totalQ = 0, totalC = 0, totalS = 0
        let qRows = try await connection.query("SELECT COUNT(*)::int FROM questions", logger: logger)
        for try await count in qRows.decode(Int.self) { totalQ = count }
        let cRows = try await connection.query("SELECT COUNT(*)::int FROM categories", logger: logger)
        for try await count in cRows.decode(Int.self) { totalC = count }
        let sRows = try await connection.query("SELECT COUNT(*)::int FROM question_sources", logger: logger)
        for try await count in sRows.decode(Int.self) { totalS = count }
        return QuickStats(totalQuestions: totalQ, totalCategories: totalC, totalSources: totalS)
    }

    func getQuestionCount() async throws -> Int {
        let rows = try await connection.query(
            "SELECT COUNT(*)::int FROM questions",
            logger: logger
        )

        for try await count in rows.decode(Int.self) {
            return count
        }

        return 0
    }
}

// MARK: - Helper Types

private struct PGChoicesWrapper: Codable {
    let items: [PGChoiceItem]
}

private struct PGChoiceItem: Codable {
    let text: String
    let isCorrect: Bool
}
