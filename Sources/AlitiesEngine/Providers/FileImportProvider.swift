import Foundation

/// Provider that imports trivia questions from local JSON/CSV files
final class FileImportProvider: TriviaProvider {
    let name = "File Import"
    var isEnabled = true

    private let watchDirectory: URL
    private let processedDirectory: URL
    private var processedFiles: Set<String> = []

    init(watchDirectory: URL) {
        self.watchDirectory = watchDirectory
        self.processedDirectory = watchDirectory.appendingPathComponent("processed")
        try? FileManager.default.createDirectory(at: watchDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: processedDirectory, withIntermediateDirectories: true)
    }

    func fetchQuestions(count: Int) async throws -> [TriviaQuestion] {
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: watchDirectory, includingPropertiesForKeys: nil)
            .filter { url in
                let ext = url.pathExtension.lowercased()
                return (ext == "json" || ext == "csv") && !processedFiles.contains(url.lastPathComponent)
            }

        guard let file = files.first else { return [] }

        let questions: [TriviaQuestion]
        if file.pathExtension.lowercased() == "json" {
            questions = try importJSON(from: file)
        } else {
            questions = try importCSV(from: file)
        }

        processedFiles.insert(file.lastPathComponent)
        let destination = processedDirectory.appendingPathComponent(file.lastPathComponent)
        try? fileManager.moveItem(at: file, to: destination)

        return Array(questions.prefix(count))
    }

    private func importJSON(from url: URL) throws -> [TriviaQuestion] {
        let data = try Data(contentsOf: url)

        if let questions = try? JSONDecoder().decode([TriviaQuestion].self, from: data) {
            return questions
        }
        if let wrapped = try? JSONDecoder().decode(WrappedQuestions.self, from: data) {
            return wrapped.questions
        }
        if let simple = try? JSONDecoder().decode([SimpleQuestion].self, from: data) {
            return simple.map { $0.toTriviaQuestion() }
        }

        throw ProviderError.parseError("Unrecognized JSON format")
    }

    private func importCSV(from url: URL) throws -> [TriviaQuestion] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }

        let header = parseCSVLine(lines[0]).map { $0.lowercased() }
        let questionIndex = header.firstIndex(of: "question") ?? header.firstIndex(of: "text") ?? 0
        let correctIndex = header.firstIndex(of: "correct_answer") ?? header.firstIndex(of: "answer") ?? 1
        let categoryIndex = header.firstIndex(of: "category")
        let difficultyIndex = header.firstIndex(of: "difficulty")
        let incorrectIndices = header.enumerated().compactMap { index, name -> Int? in
            (name.contains("incorrect") || name.contains("wrong")) ? index : nil
        }

        var questions: [TriviaQuestion] = []

        for i in 1..<lines.count {
            let values = parseCSVLine(lines[i])
            guard values.count > max(questionIndex, correctIndex) else { continue }

            let questionText = values[questionIndex]
            let correctAnswer = values[correctIndex]
            let category = categoryIndex.flatMap { values.indices.contains($0) ? values[$0] : nil } ?? "General"
            let difficulty = difficultyIndex.flatMap { values.indices.contains($0) ? Difficulty.from(values[$0]) : nil } ?? .medium

            var incorrectAnswers: [String] = []
            for idx in incorrectIndices {
                if values.indices.contains(idx) && !values[idx].isEmpty {
                    incorrectAnswers.append(values[idx])
                }
            }
            if incorrectAnswers.isEmpty {
                for j in (correctIndex + 1)..<min(correctIndex + 4, values.count) {
                    if !values[j].isEmpty { incorrectAnswers.append(values[j]) }
                }
            }
            while incorrectAnswers.count < 3 { incorrectAnswers.append("Unknown") }

            var allAnswers = Array(incorrectAnswers.prefix(3))
            let correctIdx = Int.random(in: 0...3)
            allAnswers.insert(correctAnswer, at: correctIdx)

            let choices = allAnswers.enumerated().map { index, text in
                TriviaChoice(text: text, isCorrect: index == correctIdx)
            }

            questions.append(TriviaQuestion(
                text: questionText, choices: choices,
                correctChoiceIndex: correctIdx, category: category,
                difficulty: difficulty, explanation: nil, hint: nil,
                source: "File Import: \(url.lastPathComponent)"
            ))
        }
        return questions
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" { inQuotes.toggle() }
            else if char == "," && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else { current.append(char) }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }
}

private struct WrappedQuestions: Codable {
    let questions: [TriviaQuestion]
}

private struct SimpleQuestion: Codable {
    let question: String
    let correctAnswer: String
    let incorrectAnswers: [String]
    let category: String?
    let difficulty: String?

    enum CodingKeys: String, CodingKey {
        case question
        case correctAnswer = "correct_answer"
        case incorrectAnswers = "incorrect_answers"
        case category, difficulty
    }

    func toTriviaQuestion() -> TriviaQuestion {
        var allAnswers = incorrectAnswers
        let correctIdx = Int.random(in: 0...allAnswers.count)
        allAnswers.insert(correctAnswer, at: correctIdx)
        let choices = allAnswers.enumerated().map { index, text in
            TriviaChoice(text: text, isCorrect: index == correctIdx)
        }
        return TriviaQuestion(
            text: question, choices: choices,
            correctChoiceIndex: correctIdx,
            category: category ?? "General",
            difficulty: difficulty.map { Difficulty.from($0) } ?? .medium,
            explanation: nil, hint: nil, source: "File Import"
        )
    }
}
