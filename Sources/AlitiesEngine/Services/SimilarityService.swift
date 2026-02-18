import Foundation
import AsyncHTTPClient
import NIOCore

/// Service for detecting duplicate/similar questions using AI and text comparison
actor SimilarityService {
    private let httpClient: HTTPClient
    private let openAIKey: String?
    private var questionSignatures: [String: UUID] = [:]
    private let textSimilarityThreshold: Double = 0.85
    private let aiSimilarityThreshold: Double = 0.8

    init(httpClient: HTTPClient, openAIKey: String?) {
        self.httpClient = httpClient
        self.openAIKey = openAIKey
    }

    func findSimilar(_ question: TriviaQuestion, existingQuestions: [(id: UUID, text: String, answer: String)]) async -> UUID? {
        let signature = generateSignature(question)
        if let existingId = questionSignatures[signature] {
            return existingId
        }

        for existing in existingQuestions {
            let similarity = calculateTextSimilarity(question.normalizedText, normalize(existing.text))
            if similarity >= textSimilarityThreshold {
                questionSignatures[signature] = existing.id
                return existing.id
            }
        }

        if let apiKey = openAIKey, !apiKey.isEmpty {
            let candidates = existingQuestions.filter { existing in
                let similarity = calculateTextSimilarity(question.normalizedText, normalize(existing.text))
                return similarity >= 0.5 && similarity < textSimilarityThreshold
            }

            if !candidates.isEmpty {
                if let similarId = await checkWithAI(question, candidates: candidates) {
                    questionSignatures[signature] = similarId
                    return similarId
                }
            }
        }

        return nil
    }

    func register(_ question: TriviaQuestion, id: UUID) {
        let signature = generateSignature(question)
        questionSignatures[signature] = id
    }

    func clearCache() {
        questionSignatures.removeAll()
    }

    private func generateSignature(_ question: TriviaQuestion) -> String {
        let normalized = question.normalizedText
        let answer = question.correctAnswer.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(normalized)|\(answer)"
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
    }

    private func calculateTextSimilarity(_ text1: String, _ text2: String) -> Double {
        let words1 = Set(text1.split(separator: " ").map(String.init))
        let words2 = Set(text2.split(separator: " ").map(String.init))
        guard !words1.isEmpty || !words2.isEmpty else { return 0 }
        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count
        return Double(intersection) / Double(union)
    }

    private func checkWithAI(_ question: TriviaQuestion, candidates: [(id: UUID, text: String, answer: String)]) async -> UUID? {
        guard let apiKey = openAIKey else { return nil }

        let candidateList = candidates.prefix(5).enumerated().map { idx, c in
            "\(idx + 1). \(c.text) (Answer: \(c.answer))"
        }.joined(separator: "\n")

        let prompt = """
        Determine if the new question is semantically the same as any of the existing questions.

        New question: \(question.text)
        New answer: \(question.correctAnswer)

        Existing questions:
        \(candidateList)

        If the new question is essentially the same as one of the existing questions, respond with just the number (1-5).
        If the new question is different from all existing questions, respond with "0".
        Only respond with a single number, nothing else.
        """

        do {
            var request = HTTPClientRequest(url: "https://api.openai.com/v1/chat/completions")
            request.method = .POST
            request.headers.add(name: "Authorization", value: "Bearer \(apiKey)")
            request.headers.add(name: "Content-Type", value: "application/json")

            let body: [String: Any] = [
                "model": "gpt-4o-mini",
                "messages": [["role": "user", "content": prompt]],
                "temperature": 0, "max_tokens": 10
            ]

            let bodyData = try JSONSerialization.data(withJSONObject: body)
            request.body = .bytes(ByteBuffer(data: bodyData))

            let response = try await httpClient.execute(request, timeout: .seconds(30))
            let responseBody = try await response.body.collect(upTo: 1024 * 100)

            guard response.status == .ok else { return nil }

            let data = Data(buffer: responseBody)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String,
               let matchIndex = Int(content.trimmingCharacters(in: .whitespacesAndNewlines)),
               matchIndex > 0 && matchIndex <= candidates.count {
                return candidates[matchIndex - 1].id
            }
        } catch {
            // Silently fail AI check
        }

        return nil
    }
}
