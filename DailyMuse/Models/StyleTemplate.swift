import Foundation

enum StyleTemplate: String, CaseIterable, Identifiable, Codable {
    case editorial
    case storyScene = "story_scene"
    case storyBlueprint = "story_blueprint"
    case storyDesk = "story_desk"
    case storyFrontpage = "story_frontpage"
    case original

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .editorial: "Editorial"
        case .storyScene: "Story Scene"
        case .storyBlueprint: "Blueprint"
        case .storyDesk: "Hacker's Desk"
        case .storyFrontpage: "Front Page"
        case .original: "Original"
        }
    }

    var description: String {
        switch self {
        case .editorial: "Single-scene editorial metaphor — clean, graphic, high contrast"
        case .storyScene: "Cinematic human scene — more narrative, less retro-tech"
        case .storyBlueprint: "Dense annotated systems poster — technical drawing aesthetic"
        case .storyDesk: "Detailed workspace scene built from the day's stories"
        case .storyFrontpage: "Faux newspaper or magazine cover layout"
        case .original: "Classic style from the original project"
        }
    }

    /// System prompt sent to the LLM to shape its prompt generation behavior.
    var systemPrompt: String {
        """
        You are a visual prompt engineer. You receive a list of headlines and create \
        a single, detailed image generation prompt that weaves them into one cohesive scene.

        Style direction: \(styleDirective)

        Rules:
        - Output ONLY the image prompt text. No JSON, no markdown, no explanation.
        - The prompt should be 80–150 words.
        - Optimize for high contrast, strong silhouettes, and graphic clarity.
        - Include specific objects, textures, and lighting direction.
        - End with style keywords: medium, lighting, resolution, camera angle.
        - Do NOT include any text or lettering in the image description.
        """
    }

    private var styleDirective: String {
        switch self {
        case .editorial:
            "Create a single powerful editorial illustration that captures the dominant theme. " +
            "Think New Yorker cover or Economist illustration — one strong visual metaphor."
        case .storyScene:
            "Create a cinematic scene with human figures engaged in activity that represents " +
            "the day's themes. Warm, narrative, almost like a film still."
        case .storyBlueprint:
            "Create a dense technical blueprint or systems diagram that encodes each headline " +
            "as an annotated component. Engineering drawing aesthetic with callouts and labels."
        case .storyDesk:
            "Create a detailed overhead or eye-level view of a cluttered but curated workspace. " +
            "Each headline becomes a specific object on the desk — hardware, documents, screens, tools."
        case .storyFrontpage:
            "Create a designed newspaper or magazine front page layout. Modules, columns, " +
            "masthead area, section dividers. Typography-heavy but as visual design, not readable text."
        case .original:
            "Create a striking monochrome illustration that abstractly represents the themes. " +
            "Bold shapes, stark contrast, minimal detail."
        }
    }
}
