import Foundation
import Testing
@testable import DailyMuse

struct PromptServiceTests {
    @Test("Structured output extracts final JSON after a reasoning preamble")
    func extractsFinalJSONAfterReasoning() throws {
        let rawOutput = """
        Thinking Process:
        Compare {hardware} with biology, then choose a physical metaphor.

        {"thesis":"Physical systems converge","image_prompt":"A solar observatory built across a silicon wafer, with a translucent resin seal bridging one fractured trace."}
        """

        let prompt = try PromptService.extractImagePrompt(
            from: rawOutput,
            expectsStructuredOutput: true
        )

        #expect(prompt == "A solar observatory built across a silicon wafer, with a translucent resin seal bridging one fractured trace.")
    }

    @Test("Truncated reasoning is rejected instead of becoming an image prompt")
    func rejectsTruncatedReasoning() {
        let rawOutput = """
        Thinking Process:
        The strongest connections are etched silicon, turbulence on the Sun, and biological materials.
        I will now refine the scene before writing the JSON response...
        """

        do {
            _ = try PromptService.extractImagePrompt(
                from: rawOutput,
                expectsStructuredOutput: true,
                finishReason: "length"
            )
            Issue.record("Expected truncated structured output to be rejected.")
        } catch let error as DailyMuseError {
            #expect(error.errorDescription?.contains("ran out of output tokens") == true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Original style continues to accept a plain prompt")
    func acceptsPlainUnstructuredPrompt() throws {
        let prompt = try PromptService.extractImagePrompt(
            from: "A paper city folded around a botanical specimen.",
            expectsStructuredOutput: false
        )

        #expect(prompt == "A paper city folded around a botanical specimen.")
    }
}
