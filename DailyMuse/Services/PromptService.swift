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

        var userPrompt = style.userPrompt(headlines: headlines, target: target)
        if modelIdentifier.localizedCaseInsensitiveContains("qwen") {
            userPrompt += style.expectsStructuredOutput
                ? "\n\n/no_think\nBegin the response with { and output only the requested final JSON object."
                : "\n\n/no_think\nOutput only the final image prompt."
        }

        var body: [String: Any] = [
            "model": modelIdentifier,
            "messages": [
                ["role": "system", "content": style.systemPrompt(target: target)],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.5,
            // Reasoning models may spend a substantial part of their response analyzing the
            // headlines before emitting the requested JSON. Give structured styles enough room
            // to reach the final image_prompt instead of forwarding a truncated thought process.
            "max_tokens": style.expectsStructuredOutput ? 2_400 : 1_200
        ]

        if Self.isOpenRouter(baseURL), style.expectsStructuredOutput {
            // The upstream hn_local_image app disables thinking in the model's chat template.
            // OpenRouter exposes the equivalent behavior through its normalized reasoning field.
            body["reasoning"] = ["effort": "none", "exclude": true]
            body["response_format"] = ["type": "json_object"]
        }

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
        let finishReason = choices.first?["finish_reason"] as? String

        let rawOutput = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawOutput.isEmpty else {
            throw DailyMuseError.llmError("Empty prompt returned")
        }

        let imagePrompt = try Self.extractImagePrompt(
            from: rawOutput,
            expectsStructuredOutput: style.expectsStructuredOutput,
            finishReason: finishReason
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

    private static func isOpenRouter(_ rawBaseURL: String) -> Bool {
        guard let host = URL(string: rawBaseURL)?.host?.lowercased() else { return false }
        return host == "openrouter.ai" || host.hasSuffix(".openrouter.ai")
    }

    static func extractImagePrompt(
        from rawOutput: String,
        expectsStructuredOutput: Bool,
        finishReason: String? = nil
    ) throws -> String {
        let withoutThinking = rawOutput.removingThinkingBlocks()

        if let object = withoutThinking.extractedJSONObject(),
           let imagePrompt = object["image_prompt"] as? String {
            return try validatedPrompt(imagePrompt)
        }

        // Structured styles deliberately separate headline synthesis from the final prompt.
        // Never let prose, visible chain-of-thought, or a token-truncated response cross the
        // boundary into image generation just because it is non-empty.
        if expectsStructuredOutput {
            if finishReason == "length" {
                throw DailyMuseError.llmError(
                    "The prompt model ran out of output tokens before returning its final image_prompt. No image was generated."
                )
            }
            throw DailyMuseError.llmError(
                "The prompt model did not return the required JSON image_prompt. No image was generated from its analysis text."
            )
        }

        let cleaned = withoutThinking
            .removingMarkdownFence()
            .extractingPromptAfterKnownMarker()
            .trimmingCharacters(in: .whitespacesAndNewlines)

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

    func extractedJSONObject() -> [String: Any]? {
        guard let end = lastIndex(of: "}") else { return nil }

        // Work backwards so a valid final JSON answer can still be recovered when a model
        // prints an unrequested reasoning preamble that itself contains braces.
        let starts = indices.filter { self[$0] == "{" }.reversed()
        for start in starts where start <= end {
            let candidate = String(self[start...end])
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if object["image_prompt"] != nil {
                return object
            }
        }
        return nil
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
}
