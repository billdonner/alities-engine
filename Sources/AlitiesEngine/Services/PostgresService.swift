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

        for try await (id,) in rows.decode(UUID.self) {
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

        for try await (id,) in rows.decode(UUID.self) {
            return id
        }

        let newId = UUID()
        try await connection.query(
            """
            INSERT INTO question_sources (id, name, type, question_count, created_at, updated_at)
            VALUES (\(newId), \(name), 'api'::source_type, 0, NOW(), NOW())
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

        try await connection.query(
            """
            INSERT INTO questions (id, text, choices, correct_choice_index, category_id, source_id, difficulty, explanation, created_at, updated_at)
            VALUES (\(questionId), \(question.text), \(choicesJson)::jsonb, \(question.correctChoiceIndex), \(categoryId), \(sourceId), \(difficultyStr)::difficulty, \(explanationStr), NOW(), NOW())
            """,
            logger: logger
        )

        return questionId
    }

    func getQuestionCount() async throws -> Int {
        let rows = try await connection.query(
            "SELECT COUNT(*)::int FROM questions",
            logger: logger
        )

        for try await (count,) in rows.decode(Int.self) {
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
