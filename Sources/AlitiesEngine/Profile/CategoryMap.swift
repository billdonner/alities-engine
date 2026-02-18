import Foundation

// MARK: - Category Normalization

struct CategoryMap {
    static let aliasToCanonical: [String: String] = [
        "science": "Science & Nature",
        "science & nature": "Science & Nature",
        "nature": "Science & Nature",
        "animals": "Science & Nature",
        "science - computers": "Technology",
        "science - gadgets": "Technology",
        "technology": "Technology",
        "mathematics": "Mathematics",
        "science - mathematics": "Mathematics",
        "history": "History",
        "geography": "Geography",
        "politics": "Politics",
        "sports": "Sports",
        "sport_and_leisure": "Sports",
        "music": "Music",
        "musicals & theatres": "Music",
        "literature": "Literature",
        "books": "Literature",
        "arts_and_literature": "Arts & Literature",
        "arts and literature": "Arts & Literature",
        "art": "Arts & Literature",
        "movies": "Film & TV",
        "film": "Film & TV",
        "film_and_tv": "Film & TV",
        "television": "Film & TV",
        "cartoon & animations": "Film & TV",
        "japanese anime & manga": "Film & TV",
        "video games": "Video Games",
        "board games": "Board Games",
        "comics": "Comics",
        "food & drink": "Food & Drink",
        "food_and_drink": "Food & Drink",
        "pop culture": "Pop Culture",
        "celebrities": "Pop Culture",
        "mythology": "Mythology",
        "society_and_culture": "Society & Culture",
        "society and culture": "Society & Culture",
        "general_knowledge": "General Knowledge",
        "general knowledge": "General Knowledge",
        "vehicles": "Vehicles",
    ]

    static let canonicalToSymbol: [String: String] = [
        "Science & Nature": "atom",
        "Technology": "desktopcomputer",
        "Mathematics": "number",
        "History": "clock",
        "Geography": "globe.americas",
        "Politics": "building.columns",
        "Sports": "sportscourt",
        "Music": "music.note",
        "Literature": "book",
        "Arts & Literature": "paintbrush",
        "Film & TV": "film",
        "Video Games": "gamecontroller",
        "Board Games": "gamecontroller",
        "Comics": "text.bubble",
        "Food & Drink": "fork.knife",
        "Pop Culture": "star",
        "Mythology": "sparkles",
        "Society & Culture": "person.3",
        "General Knowledge": "questionmark.circle",
        "Vehicles": "car",
    ]

    static func normalize(_ raw: String) -> String {
        let key = raw.lowercased().trimmingCharacters(in: .whitespaces)
        return aliasToCanonical[key] ?? raw
    }

    static func symbol(for canonical: String) -> String {
        canonicalToSymbol[canonical] ?? "questionmark.circle"
    }

    static func seedDatabase(_ db: TriviaDatabase) throws {
        for (canonical, symbol) in canonicalToSymbol {
            try db.getOrCreateCategory(name: canonical, pic: symbol)
        }
        for (alias, canonical) in aliasToCanonical {
            try db.addAlias(alias, forCategory: canonical)
        }
    }
}
