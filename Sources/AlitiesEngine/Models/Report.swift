import Foundation

// MARK: - Report Data

struct ReportData: Codable {
    let summary: SummarySection
    let categories: [CategoryEntry]
    let sources: [SourceEntry]
    let difficulty: [DifficultyEntry]?
    let hints: HintSection
    let questionLength: LengthSection
    let answerStats: AnswerStatsSection

    struct SummarySection: Codable {
        let totalQuestions: Int
        let fileSize: String
        let fileCount: Int
        let files: [FileDetail]?
        let generatedDate: String?
    }

    struct FileDetail: Codable {
        let name: String
        let questionCount: Int
        let fileSize: String
        let format: String
    }

    struct CategoryEntry: Codable {
        let name: String
        let count: Int
        let percentage: Double
    }

    struct SourceEntry: Codable {
        let name: String
        let count: Int
        let percentage: Double
    }

    struct DifficultyEntry: Codable {
        let level: String
        let count: Int
        let percentage: Double
    }

    struct HintSection: Codable {
        let withHints: Int
        let withoutHints: Int
        let sampleHints: [String]
    }

    struct LengthSection: Codable {
        let minChars: Int
        let maxChars: Int
        let avgChars: Int
        let minQuestion: String
        let maxQuestion: String
    }

    struct AnswerStatsSection: Codable {
        let avgAnswersPerQuestion: Double
        let correctPositionDistribution: [String: Int]
    }
}

// MARK: - Report Generation

struct ReportGenerator {
    static func generate(
        from questions: [ProfiledQuestion],
        fileDetails: [ReportData.FileDetail],
        totalFileSize: Int,
        generated: Date?,
        hasDifficulty: Bool
    ) -> ReportData {
        let summary = makeSummary(questions: questions, fileDetails: fileDetails, totalFileSize: totalFileSize, generated: generated)
        let categories = makeCategories(questions)
        let sources = makeSources(questions)
        let difficulty = makeDifficulty(questions, hasDifficulty: hasDifficulty)
        let hints = makeHints(questions)
        let questionLength = makeQuestionLength(questions)
        let answerStats = makeAnswerStats(questions)

        return ReportData(
            summary: summary,
            categories: categories,
            sources: sources,
            difficulty: difficulty,
            hints: hints,
            questionLength: questionLength,
            answerStats: answerStats
        )
    }

    private static func makeSummary(
        questions: [ProfiledQuestion],
        fileDetails: [ReportData.FileDetail],
        totalFileSize: Int,
        generated: Date?
    ) -> ReportData.SummarySection {
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(totalFileSize), countStyle: .file)
        var dateStr: String? = nil
        if let generated {
            let fmt = DateFormatter()
            fmt.dateStyle = .long
            fmt.timeStyle = .short
            dateStr = fmt.string(from: generated)
        }
        return .init(
            totalQuestions: questions.count,
            fileSize: sizeStr,
            fileCount: fileDetails.count,
            files: fileDetails.count > 1 ? fileDetails : nil,
            generatedDate: dateStr
        )
    }

    private static func makeCategories(_ questions: [ProfiledQuestion]) -> [ReportData.CategoryEntry] {
        let counts = Dictionary(grouping: questions, by: \.category).mapValues(\.count)
        let total = Double(questions.count)
        return counts.sorted { $0.value > $1.value }.map {
            .init(name: $0.key, count: $0.value, percentage: Double($0.value) / total * 100)
        }
    }

    private static func makeSources(_ questions: [ProfiledQuestion]) -> [ReportData.SourceEntry] {
        let counts = Dictionary(grouping: questions, by: { $0.source ?? "unknown" }).mapValues(\.count)
        let total = Double(questions.count)
        return counts.sorted { $0.value > $1.value }.map {
            .init(name: $0.key, count: $0.value, percentage: Double($0.value) / total * 100)
        }
    }

    private static func makeDifficulty(_ questions: [ProfiledQuestion], hasDifficulty: Bool) -> [ReportData.DifficultyEntry]? {
        let withDifficulty = questions.compactMap(\.difficulty)
        guard !withDifficulty.isEmpty else { return nil }
        let counts = Dictionary(grouping: withDifficulty, by: { $0 }).mapValues(\.count)
        let total = Double(withDifficulty.count)
        let order = ["easy", "medium", "hard"]
        return counts.sorted { a, b in
            let ai = order.firstIndex(of: a.key.lowercased()) ?? 99
            let bi = order.firstIndex(of: b.key.lowercased()) ?? 99
            return ai < bi
        }.map {
            .init(level: $0.key, count: $0.value, percentage: Double($0.value) / total * 100)
        }
    }

    private static func makeHints(_ questions: [ProfiledQuestion]) -> ReportData.HintSection {
        let withHints = questions.filter { $0.hint != nil && !$0.hint!.isEmpty }
        let samples = Array(withHints.prefix(3).compactMap(\.hint))
        return .init(withHints: withHints.count, withoutHints: questions.count - withHints.count, sampleHints: samples)
    }

    private static func makeQuestionLength(_ questions: [ProfiledQuestion]) -> ReportData.LengthSection {
        let lengths = questions.map(\.question.count)
        let minLen = lengths.min() ?? 0
        let maxLen = lengths.max() ?? 0
        let avgLen = lengths.isEmpty ? 0 : lengths.reduce(0, +) / lengths.count
        let shortest = questions.min(by: { $0.question.count < $1.question.count })?.question ?? ""
        let longest = questions.max(by: { $0.question.count < $1.question.count })?.question ?? ""
        return .init(minChars: minLen, maxChars: maxLen, avgChars: avgLen,
                     minQuestion: String(shortest.prefix(80)),
                     maxQuestion: String(longest.prefix(80)))
    }

    private static func makeAnswerStats(_ questions: [ProfiledQuestion]) -> ReportData.AnswerStatsSection {
        let totalAnswers = questions.map(\.answers.count).reduce(0, +)
        let avg = questions.isEmpty ? 0.0 : Double(totalAnswers) / Double(questions.count)
        var positionDist: [String: Int] = [:]
        for q in questions {
            let pos = "Position \(q.correctIndex + 1)"
            positionDist[pos, default: 0] += 1
        }
        return .init(avgAnswersPerQuestion: avg, correctPositionDistribution: positionDist)
    }
}

// MARK: - Text Rendering

struct TextRenderer {
    static func render(_ data: ReportData, section: String? = nil) -> String {
        var parts: [String] = []

        if section == nil || section == "summary" {
            parts.append(renderSummary(data.summary))
        }
        if section == nil || section == "categories" {
            parts.append(renderCategories(data.categories))
        }
        if section == nil || section == "sources" {
            parts.append(renderSources(data.sources))
        }
        if section == nil || section == "difficulty" {
            parts.append(renderDifficulty(data.difficulty))
        }
        if section == nil || section == "hints" {
            parts.append(renderHints(data.hints))
        }
        if section == nil || section == "length" {
            parts.append(renderQuestionLength(data.questionLength))
        }
        if section == nil || section == "answers" {
            parts.append(renderAnswerStats(data.answerStats))
        }

        return parts.joined(separator: "\n")
    }

    private static func renderSummary(_ s: ReportData.SummarySection) -> String {
        var lines = [
            header("Summary"),
            "  Total questions : \(s.totalQuestions)",
            "  Total file size : \(s.fileSize)",
            "  Files           : \(s.fileCount)",
        ]
        if let files = s.files {
            for f in files {
                lines.append("    \(f.name.padding(toLength: 28, withPad: " ", startingAt: 0))  \(String(format: "%5d", f.questionCount)) questions  \(f.fileSize.padding(toLength: 8, withPad: " ", startingAt: 0))  \(f.format)")
            }
        }
        if let date = s.generatedDate {
            lines.append("  Latest generated: \(date)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func renderCategories(_ cats: [ReportData.CategoryEntry]) -> String {
        var lines = [header("Categories (\(cats.count) topics)")]
        let maxName = max(cats.map(\.name.count).max() ?? 0, 8)
        for cat in cats {
            let bar = String(repeating: "█", count: Int(cat.percentage / 2))
            let name = cat.name.padding(toLength: maxName, withPad: " ", startingAt: 0)
            lines.append("  \(name)  \(String(format: "%4d", cat.count))  (\(String(format: "%5.1f%%", cat.percentage)))  \(bar)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func renderSources(_ sources: [ReportData.SourceEntry]) -> String {
        var lines = [header("Sources")]
        let maxName = max(sources.map(\.name.count).max() ?? 0, 8)
        for src in sources {
            let name = src.name.padding(toLength: maxName, withPad: " ", startingAt: 0)
            lines.append("  \(name)  \(String(format: "%4d", src.count))  (\(String(format: "%5.1f%%", src.percentage)))")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func renderDifficulty(_ diff: [ReportData.DifficultyEntry]?) -> String {
        var lines = [header("Difficulty")]
        guard let diff, !diff.isEmpty else {
            lines.append("  (not available — game data format has no difficulty field)")
            lines.append("")
            return lines.joined(separator: "\n")
        }
        for d in diff {
            let bar = String(repeating: "█", count: Int(d.percentage / 2))
            lines.append("  \(d.level.padding(toLength: 10, withPad: " ", startingAt: 0))  \(String(format: "%4d", d.count))  (\(String(format: "%5.1f%%", d.percentage)))  \(bar)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func renderHints(_ h: ReportData.HintSection) -> String {
        var lines = [header("Hints")]
        let total = h.withHints + h.withoutHints
        let pct = total > 0 ? Double(h.withHints) / Double(total) * 100 : 0
        lines.append("  With hints    : \(h.withHints) (\(String(format: "%.1f%%", pct)))")
        lines.append("  Without hints : \(h.withoutHints)")
        if !h.sampleHints.isEmpty {
            lines.append("  Sample hints  :")
            for hint in h.sampleHints {
                lines.append("    - \(hint)")
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func renderQuestionLength(_ l: ReportData.LengthSection) -> String {
        var lines = [header("Question Length")]
        lines.append("  Shortest : \(l.minChars) chars — \"\(l.minQuestion)\"")
        lines.append("  Longest  : \(l.maxChars) chars — \"\(l.maxQuestion)\"")
        lines.append("  Average  : \(l.avgChars) chars")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func renderAnswerStats(_ a: ReportData.AnswerStatsSection) -> String {
        var lines = [header("Answer Stats")]
        lines.append("  Avg answers/question : \(String(format: "%.1f", a.avgAnswersPerQuestion))")
        lines.append("  Correct answer position distribution:")
        for key in a.correctPositionDistribution.keys.sorted() {
            lines.append("    \(key) : \(a.correctPositionDistribution[key]!)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func header(_ title: String) -> String {
        let line = String(repeating: "─", count: 50)
        return "\(line)\n  \(title)\n\(line)"
    }
}

// MARK: - JSON Rendering

struct JSONRenderer {
    static func render(_ data: ReportData, section: String? = nil) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let toEncode: Codable
        if let section {
            switch section {
            case "summary": toEncode = data.summary
            case "categories": toEncode = data.categories
            case "sources": toEncode = data.sources
            case "difficulty": toEncode = data.difficulty ?? [] as [ReportData.DifficultyEntry]
            case "hints": toEncode = data.hints
            case "length": toEncode = data.questionLength
            case "answers": toEncode = data.answerStats
            default: toEncode = data
            }
        } else {
            toEncode = data
        }

        guard let jsonData = try? encoder.encode(AnyEncodable(toEncode)) else {
            return "{}"
        }
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }
}

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: Codable) {
        _encode = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
