import Foundation
import GRDB
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// MARK: - Database Records

struct CategoryRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "categories"
    var id: Int64?
    var name: String
    var pic: String

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct CategoryAliasRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "category_aliases"
    var alias: String
    var categoryId: Int64

    enum CodingKeys: String, CodingKey {
        case alias
        case categoryId = "category_id"
    }
}

struct QuestionRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "questions"
    var id: Int64?
    var text: String
    var textHash: String
    var choicesJson: String
    var correctIndex: Int
    var categoryId: Int64
    var difficulty: String?
    var explanation: String?
    var hint: String?
    var source: String
    var importedFrom: String?
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, text
        case textHash = "text_hash"
        case choicesJson = "choices_json"
        case correctIndex = "correct_index"
        case categoryId = "category_id"
        case difficulty, explanation, hint, source
        case importedFrom = "imported_from"
        case createdAt = "created_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct ChoiceEntry: Codable {
    let text: String
    let isCorrect: Bool
}

// MARK: - TriviaDatabase

class TriviaDatabase {
    let dbQueue: DatabaseQueue

    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "categories", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("pic", .text).notNull().defaults(to: "questionmark.circle")
            }

            try db.create(table: "category_aliases", ifNotExists: true) { t in
                t.primaryKey("alias", .text)
                t.column("category_id", .integer).notNull()
                    .references("categories", onDelete: .cascade)
            }

            try db.create(table: "questions", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("text", .text).notNull()
                t.column("text_hash", .text).notNull().unique()
                t.column("choices_json", .text).notNull()
                t.column("correct_index", .integer).notNull()
                t.column("category_id", .integer).notNull()
                    .references("categories", onDelete: .restrict)
                t.column("difficulty", .text)
                    .check(sql: "difficulty IN ('easy','medium','hard')")
                t.column("explanation", .text)
                t.column("hint", .text)
                t.column("source", .text).notNull().defaults(to: "unknown")
                t.column("imported_from", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
            }

            try db.create(index: "idx_questions_category", on: "questions",
                          columns: ["category_id"], ifNotExists: true)
            try db.create(index: "idx_questions_difficulty", on: "questions",
                          columns: ["difficulty"], ifNotExists: true)
            try db.create(index: "idx_questions_source", on: "questions",
                          columns: ["source"], ifNotExists: true)
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - Text Hashing

    static func computeTextHash(_ text: String) -> String {
        let normalized = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines).joined()
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0) }.joined()
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Category Operations

    @discardableResult
    func getOrCreateCategory(name: String, pic: String? = nil) throws -> Int64 {
        try dbQueue.write { db in
            if let existing = try CategoryRecord.filter(Column("name") == name).fetchOne(db) {
                return existing.id!
            }
            let record = CategoryRecord(
                id: nil, name: name,
                pic: pic ?? CategoryMap.symbol(for: name)
            )
            try record.insert(db)
            return db.lastInsertedRowID
        }
    }

    func addAlias(_ alias: String, forCategory canonicalName: String) throws {
        try dbQueue.write { db in
            guard let cat = try CategoryRecord.filter(Column("name") == canonicalName).fetchOne(db) else {
                return
            }
            try? CategoryAliasRecord(alias: alias, categoryId: cat.id!).insert(db)
        }
    }

    func resolveCategoryId(for rawName: String) throws -> Int64 {
        let lowered = rawName.lowercased().trimmingCharacters(in: .whitespaces)

        return try dbQueue.write { db in
            if let aliasRec = try CategoryAliasRecord.filter(Column("alias") == lowered).fetchOne(db) {
                return aliasRec.categoryId
            }

            let canonical = CategoryMap.normalize(rawName)
            if let existing = try CategoryRecord.filter(Column("name") == canonical).fetchOne(db) {
                return existing.id!
            }

            let record = CategoryRecord(
                id: nil, name: canonical,
                pic: CategoryMap.symbol(for: canonical)
            )
            try record.insert(db)
            return db.lastInsertedRowID
        }
    }

    // MARK: - Question Operations

    enum InsertResult {
        case inserted
        case duplicate
    }

    func insertQuestion(
        text: String, choices: [ChoiceEntry], correctIndex: Int,
        categoryId: Int64, difficulty: String?, explanation: String?,
        hint: String?, source: String, importedFrom: String?
    ) throws -> InsertResult {
        let hash = TriviaDatabase.computeTextHash(text)
        let choicesData = try JSONEncoder().encode(choices)
        let choicesJson = String(data: choicesData, encoding: .utf8)!

        let normalizedDifficulty: String?
        if let d = difficulty?.lowercased(), ["easy", "medium", "hard"].contains(d) {
            normalizedDifficulty = d
        } else {
            normalizedDifficulty = nil
        }

        return try dbQueue.write { db in
            let exists = try QuestionRecord.filter(Column("text_hash") == hash).fetchOne(db)
            if exists != nil { return .duplicate }

            let record = QuestionRecord(
                id: nil, text: text, textHash: hash, choicesJson: choicesJson,
                correctIndex: correctIndex, categoryId: categoryId,
                difficulty: normalizedDifficulty, explanation: explanation,
                hint: hint, source: source, importedFrom: importedFrom,
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
            try record.insert(db)
            return .inserted
        }
    }

    // MARK: - Query Operations

    struct CategoryStats {
        let id: Int64
        let name: String
        let pic: String
        let count: Int
    }

    func allCategories() throws -> [CategoryStats] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.id, c.name, c.pic, COUNT(q.id) as count
                FROM categories c
                LEFT JOIN questions q ON q.category_id = c.id
                GROUP BY c.id
                ORDER BY count DESC
            """)
            return rows.map {
                CategoryStats(id: $0["id"], name: $0["name"], pic: $0["pic"], count: $0["count"])
            }
        }
    }

    func allAliases() throws -> [(alias: String, canonical: String)] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT ca.alias, c.name
                FROM category_aliases ca
                JOIN categories c ON c.id = ca.category_id
                ORDER BY c.name, ca.alias
            """)
            return rows.map { (alias: $0["alias"] as String, canonical: $0["name"] as String) }
        }
    }

    struct QuickStats {
        let totalQuestions: Int
        let totalCategories: Int
        let totalSources: Int
        let easyCount: Int
        let mediumCount: Int
        let hardCount: Int
        let noDifficultyCount: Int
    }

    func stats() throws -> QuickStats {
        try dbQueue.read { db in
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM questions") ?? 0
            let cats = try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT category_id) FROM questions") ?? 0
            let sources = try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT source) FROM questions") ?? 0
            let easy = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM questions WHERE difficulty = 'easy'") ?? 0
            let medium = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM questions WHERE difficulty = 'medium'") ?? 0
            let hard = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM questions WHERE difficulty = 'hard'") ?? 0
            let noDiff = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM questions WHERE difficulty IS NULL") ?? 0
            return QuickStats(
                totalQuestions: total, totalCategories: cats, totalSources: sources,
                easyCount: easy, mediumCount: medium, hardCount: hard, noDifficultyCount: noDiff
            )
        }
    }

    func allQuestions(category: String? = nil, difficulty: String? = nil,
                      source: String? = nil, limit: Int? = nil) throws -> [ProfiledQuestion] {
        try dbQueue.read { db in
            var sql = """
                SELECT q.*, c.name as category_name
                FROM questions q
                JOIN categories c ON c.id = q.category_id
                WHERE 1=1
            """
            var args: [DatabaseValueConvertible] = []

            if let category {
                sql += " AND c.name = ?"
                args.append(category)
            }
            if let difficulty {
                sql += " AND q.difficulty = ?"
                args.append(difficulty)
            }
            if let source {
                sql += " AND q.source = ?"
                args.append(source)
            }
            sql += " ORDER BY q.id"
            if let limit {
                sql += " LIMIT ?"
                args.append(limit)
            }

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return try rows.map { row -> ProfiledQuestion in
                let choicesJson: String = row["choices_json"]
                let choices = try JSONDecoder().decode([ChoiceEntry].self, from: Data(choicesJson.utf8))
                let categoryName: String = row["category_name"]
                let correctIdx: Int = row["correct_index"]
                let correctText = choices.indices.contains(correctIdx) ? choices[correctIdx].text : ""

                return ProfiledQuestion(
                    question: row["text"], answers: choices.map(\.text),
                    correctAnswer: correctText, correctIndex: correctIdx,
                    category: categoryName, difficulty: row["difficulty"],
                    explanation: row["explanation"], hint: row["hint"],
                    source: row["source"]
                )
            }
        }
    }
}
