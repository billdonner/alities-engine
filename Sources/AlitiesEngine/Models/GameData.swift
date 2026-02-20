import Foundation

// MARK: - Unified Game Data Output

/// Top-level output format — shared by generator and profile
struct GameDataOutput: Codable {
    let id: String
    let generated: TimeInterval
    let challenges: [Challenge]
}

/// Unified Challenge model.
/// All fields are non-optional in memory for ease of use.
/// The custom decoder handles missing/null values from JSON gracefully.
struct Challenge: Codable {
    let id: String
    let topic: String
    let pic: String
    let question: String
    let answers: [String]
    let correct: String
    let explanation: String
    let hint: String
    let aisource: String
    let date: TimeInterval

    // Standard memberwise init
    init(
        id: String = UUID().uuidString,
        topic: String,
        pic: String = "questionmark.circle",
        question: String,
        answers: [String],
        correct: String,
        explanation: String = "",
        hint: String = "",
        aisource: String = "unknown",
        date: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) {
        self.id = id
        self.topic = topic
        self.pic = pic
        self.question = question
        self.answers = answers
        self.correct = correct
        self.explanation = explanation
        self.hint = hint
        self.aisource = aisource
        self.date = date
    }

    // Custom decoder handles null/missing fields from JSON
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        topic = try container.decode(String.self, forKey: .topic)
        pic = try container.decodeIfPresent(String.self, forKey: .pic) ?? "questionmark.circle"
        question = try container.decode(String.self, forKey: .question)
        answers = try container.decode([String].self, forKey: .answers)
        correct = try container.decode(String.self, forKey: .correct)
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        hint = try container.decodeIfPresent(String.self, forKey: .hint) ?? ""
        aisource = try container.decodeIfPresent(String.self, forKey: .aisource) ?? "unknown"
        date = try container.decodeIfPresent(TimeInterval.self, forKey: .date) ?? 0
    }
}

// MARK: - SF Symbol mapping (from generator)

enum TopicPicMapping {
    private static let mappings: [(substring: String, symbol: String)] = [
        ("history", "clock"),
        ("science", "atom"),
        ("nature", "leaf"),
        ("animal", "hare"),
        ("geography", "globe.americas"),
        ("sport", "sportscourt"),
        ("music", "music.note"),
        ("movie", "film"),
        ("film", "film"),
        ("television", "tv"),
        ("art", "paintbrush"),
        ("literature", "book"),
        ("book", "book"),
        ("technology", "desktopcomputer"),
        ("computer", "desktopcomputer"),
        ("food", "fork.knife"),
        ("drink", "cup.and.saucer"),
        ("pop culture", "star"),
        ("celebrity", "star"),
        ("math", "number"),
        ("politic", "building.columns"),
        ("mythology", "sparkles"),
        ("vehicle", "car"),
        ("game", "gamecontroller"),
        ("comic", "text.bubble"),
        ("anime", "sparkle"),
        ("cartoon", "paintpalette"),
        ("general", "questionmark.circle"),
        ("society", "person.3"),
        ("culture", "person.3"),
    ]

    static func symbol(for category: String) -> String {
        let lower = category.lowercased()
        for mapping in mappings {
            if lower.contains(mapping.substring) {
                return mapping.symbol
            }
        }
        return "questionmark.circle"
    }
}

// MARK: - aisource mapping

extension TriviaQuestion {
    var aisource: String {
        switch source.lowercased() {
        case let s where s.contains("ai generated"):
            return "openai"
        default:
            return source.lowercased().replacingOccurrences(of: " ", with: "")
        }
    }
}
