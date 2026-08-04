import Foundation

/// Calls any OpenAI-compatible chat/completions endpoint to turn headlines into an image prompt.
/// Works with LM Studio, Ollama, oMLX, OpenAI, Anthropic (via proxy), etc.
struct PromptService {
    let baseURL: String
    let model: String

    /// API key is optional — local servers typically don't need one.
    var apiKey: String?

    func generateImagePrompt(headlines: [String], style: StyleTemplate) async throws -> String {
        let endpoint = baseURL.trimmingSuffix("/") + "/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw DailyMuseError.invalidURL(endpoint)
        }

        let headlineList = headlines.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        let userMessage = """
        Here are today's top headlines:

        \(headlineList)

        Create a single image generation prompt that weaves these into one cohesive visual.
        """

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": style.systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "temperature": 0.8,
            "max_tokens": 500
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw DailyMuseError.llmError("HTTP \(statusCode): \(body)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw DailyMuseError.llmError("Unexpected response format")
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DailyMuseError.llmError("Empty prompt returned")
        }

        return trimmed
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        if hasSuffix(suffix) {
            return String(dropLast(suffix.count))
        }
        return self
    }
}
