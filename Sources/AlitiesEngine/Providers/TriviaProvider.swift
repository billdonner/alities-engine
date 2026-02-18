import Foundation

/// Protocol for trivia question providers
protocol TriviaProvider {
    var name: String { get }
    var isEnabled: Bool { get set }

    /// Fetch a batch of questions from this provider
    func fetchQuestions(count: Int) async throws -> [TriviaQuestion]
}

/// Provider errors
enum ProviderError: Error, LocalizedError {
    case networkError(String)
    case parseError(String)
    case rateLimited
    case noResults
    case apiKeyMissing
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "Network error: \(msg)"
        case .parseError(let msg): return "Parse error: \(msg)"
        case .rateLimited: return "Rate limited by provider"
        case .noResults: return "No results from provider"
        case .apiKeyMissing: return "API key not configured"
        case .invalidResponse: return "Invalid response from provider"
        }
    }
}
