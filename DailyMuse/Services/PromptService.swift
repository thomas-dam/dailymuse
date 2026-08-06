import Foundation

/// Calls an OpenAI-compatible chat/completions endpoint to turn headlines into an image prompt.
/// Works with LM Studio, Ollama, oMLX, OpenAI, Anthropic-compatible proxies, and similar servers.
struct PromptService: Sendable {
    let baseURL: String
    let model: String

    /// API key is optional because local servers typically do not require one.
    var apiKey: String?

    func generateImagePrompt(
        headlines: [String],
        style: StyleTemplate,
        target: GenerationTarget
    ) async throws -> ImagePromptResult {
        let modelIdentifier = try Self.validatedModelIdentifier(model)
        let endpoint = baseURL.trimmingSuffix("/") + "/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw DailyMuseError.invalidURL(endpoint)
        }

        let body: [String: Any] = [
            "model": modelIdentifier,
            "messages": [
                ["role": "system", "content": style.systemPrompt(target: target)],
                ["role": "user", "content": style.userPrompt(headlines: headlines, target: target)]
            ],
            "temperature": 0.7,
            "max_tokens": 900
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? "no body"
            throw DailyMuseError.llmError("HTTP \(statusCode): \(responseBody)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw DailyMuseError.llmError("Unexpected response format")
        }

        let rawOutput = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawOutput.isEmpty else {
            throw DailyMuseError.llmError("Empty prompt returned")
        }

        let imagePrompt = try Self.extractImagePrompt(
            from: rawOutput,
            expectsStructuredOutput: style.expectsStructuredOutput
        )
        return ImagePromptResult(rawOutput: rawOutput, imagePrompt: imagePrompt)
    }

    /// Returns one model identifier suitable for an OpenAI-compatible request.
    /// Blank lines are harmless, but pasted lists are rejected instead of being sent silently.
    static func validatedModelIdentifier(_ rawValue: String) throws -> String {
        let expandedValue = rawValue
            .replacing("\\r\\n", with: "\n")
            .replacing("\\n", with: "\n")
            .replacing("\\r", with: "\n")

        let identifiers = expandedValue
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard identifiers.count == 1, let identifier = identifiers.first else {
            if identifiers.isEmpty {
                throw DailyMuseError.llmError("Enter an LLM model identifier.")
            }
            throw DailyMuseError.llmError(
                "The LLM model setting contains multiple identifiers. Enter exactly one model, such as qwen3-vl-8b-instruct."
            )
        }

        return identifier
    }

    static func extractImagePrompt(
        from rawOutput: String,
        expectsStructuredOutput: Bool
    ) throws -> String {
        let withoutThinking = rawOutput.removingThinkingBlocks()

        if let jsonDocument = withoutThinking.extractedJSONDocument(),
           let data = jsonDocument.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let imagePrompt = object["image_prompt"] as? String {
            return try validatedPrompt(imagePrompt)
        }

        let cleaned = withoutThinking
            .removingMarkdownFence()
            .extractingPromptAfterKnownMarker()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if expectsStructuredOutput, cleaned.looksLikeJSONObject {
            throw DailyMuseError.llmError(
                "The prompt model returned JSON without a valid image_prompt string; it was not sent to image generation."
            )
        }

        return try validatedPrompt(cleaned)
    }

    private static func validatedPrompt(_ prompt: String) throws -> String {
        let cleaned = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .removingMatchingOuterQuotes()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            throw DailyMuseError.llmError("The prompt model returned an empty image_prompt")
        }
        return cleaned
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }

    func removingThinkingBlocks() -> String {
        replacingOccurrences(
            of: #"<think>[\s\S]*?</think>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func extractedJSONDocument() -> String? {
        guard let start = firstIndex(of: "{"),
              let end = lastIndex(of: "}"),
              start <= end else {
            return nil
        }
        return String(self[start...end])
    }

    func removingMarkdownFence() -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        var lines = trimmed.components(separatedBy: .newlines)
        if !lines.isEmpty {
            lines.removeFirst()
        }
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    func extractingPromptAfterKnownMarker() -> String {
        let markers = ["image prompt:", "image_prompt:", "prompt:"]

        for marker in markers {
            if let range = range(of: marker, options: [.caseInsensitive, .backwards]) {
                let candidate = self[range.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty {
                    return candidate
                }
            }
        }
        return self
    }

    func removingMatchingOuterQuotes() -> String {
        guard count >= 2,
              let first,
              let last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return self
        }
        return String(dropFirst().dropLast())
    }

    var looksLikeJSONObject: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") && trimmed.hasSuffix("}")
    }
}
