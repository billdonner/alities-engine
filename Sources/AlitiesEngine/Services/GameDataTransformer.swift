import Foundation

enum GameDataTransformer {
    static func transform(questions: [TriviaQuestion]) -> GameDataOutput {
        let now = Date().timeIntervalSinceReferenceDate

        let challenges = questions.map { q in
            Challenge(
                id: UUID().uuidString,
                topic: q.category,
                pic: TopicPicMapping.symbol(for: q.category),
                question: q.text,
                answers: q.choices.map(\.text),
                correct: q.correctAnswer,
                explanation: q.explanation ?? "",
                hint: q.hint ?? "",
                aisource: q.aisource,
                date: now
            )
        }

        return GameDataOutput(
            id: UUID().uuidString,
            generated: now,
            challenges: challenges
        )
    }
}
