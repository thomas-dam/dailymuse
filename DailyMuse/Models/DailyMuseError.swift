import Foundation

enum DailyMuseError: LocalizedError {
    case invalidURL(String)
    case noHeadlines
    case llmError(String)
    case imageError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): "Invalid URL: \(url)"
        case .noHeadlines: "No headlines found from the source"
        case .llmError(let msg): "LLM error: \(msg)"
        case .imageError(let msg): "Image generation error: \(msg)"
        }
    }
}
