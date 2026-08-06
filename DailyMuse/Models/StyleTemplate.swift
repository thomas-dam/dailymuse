import Foundation

enum StyleTemplate: String, CaseIterable, Identifiable, Codable, Sendable {
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

    var expectsStructuredOutput: Bool {
        self != .original
    }

    func systemPrompt(target: GenerationTarget) -> String {
        let role: String

        switch self {
        case .editorial:
            role = """
            You are an editorial art director designing one cover image. Compress many headlines \
            into one surprising but legible visual metaphor. Prefer one dominant scene, one hero \
            subject, 2–4 supporting motifs, a strong silhouette, and generous negative space. Avoid \
            collage clutter, screenshots, dashboards, literal headline lists, generic cyberpunk, \
            visible words, and logos.
            """
        case .storyScene:
            role = """
            You are a concept artist turning a noisy technology-news cycle into a single scene with \
            narrative tension. Be specific, visual, witty, contemporary, and cinematic. Do not add \
            visible text, numbers, interfaces, or logos.
            """
        case .storyBlueprint:
            role = """
            You are a design director making a beautiful speculative blueprint poster from technology \
            headlines. Build one coherent technical diagram, not a random collage. Short labels, arrows, \
            module names, and captions are allowed, but they must remain elegant and sparse.
            """
        case .storyDesk:
            role = """
            You are an art director staging a detailed but pleasing hacker workspace. Stories appear as \
            objects, notes, screens, prototypes, cables, books, diagrams, and artifacts. Intentional short \
            text on ephemera is allowed, but avoid walls of copy and accidental gibberish.
            """
        case .storyFrontpage:
            role = """
            You are designing a visually pleasing fictional technology newspaper or magazine front page. \
            Mix one hero illustration with supporting columns, labels, sidebars, captions, and typographic \
            blocks. Text is allowed and should feel deliberately designed rather than accidental.
            """
        case .original:
            role = """
            You are a visual prompt engineer. Analyze the headlines, identify 3–5 overarching themes, \
            and turn them into one artistic, geeky, visually striking illustration. Use technical editorial \
            illustration, blueprint line art, retro-futurism, hacker aesthetics, and circuit-board motifs. \
            Do not list stories or place visible text in the image.
            """
        }

        return "\(role)\n\n\(target.promptDirection)"
    }

    func userPrompt(headlines: [String], target: GenerationTarget) -> String {
        let numberedHeadlines = headlines.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        switch self {
        case .original:
            return """
            Here are today's top headlines:

            \(numberedHeadlines)

            Write a detailed, vivid image-generation prompt for one cohesive illustration suitable for \
            \(target.frameDescription). Output only the image prompt, with no JSON, Markdown, analysis, \
            preamble, or explanation.
            """
        case .editorial:
            return structuredPrompt(
                headlines: numberedHeadlines,
                keys: "thesis, mood, motifs, composition, image_prompt",
                requirements: """
                - image_prompt is 120–180 words
                - create one unified scene, not a collage
                - use one unexpected metaphor connecting technology, infrastructure, and real-world stakes
                - keep the composition readable at a glance
                - include no visible words, letters, or logos
                """,
                target: target
            )
        case .storyScene:
            return structuredPrompt(
                headlines: numberedHeadlines,
                keys: "why_today_is_interesting, scene, visual_hooks, image_prompt",
                requirements: """
                - describe one scene from a slightly elevated wide angle
                - include a central object, a human-scale reference, and 2–3 symbolic supporting elements
                - feel witty, tense, and contemporary rather than nostalgic by default
                - include zero visible text, numbers, interfaces, or logos
                """,
                target: target
            )
        case .storyBlueprint:
            return structuredPrompt(
                headlines: numberedHeadlines,
                keys: "narrative, modules, composition, image_prompt",
                requirements: """
                - turn the stories into one dense systems map or impossible machine
                - include one central apparatus and 6–10 labeled modules or callouts
                - allow concise labels, arrows, captions, and version-style marks
                - maintain a clear hierarchy and generous breathing room
                """,
                target: target
            )
        case .storyDesk:
            return structuredPrompt(
                headlines: numberedHeadlines,
                keys: "atmosphere, featured_objects, composition, image_prompt",
                requirements: """
                - create one desk, lab bench, studio, or control-room scene
                - integrate every story through physical objects and environmental details
                - allow sticky notes, labels, book spines, screen snippets, and schematic notes
                - feel warm, clever, dense, and composed rather than messy
                """,
                target: target
            )
        case .storyFrontpage:
            return structuredPrompt(
                headlines: numberedHeadlines,
                keys: "editorial_angle, sections, composition, image_prompt",
                requirements: """
                - create a designed technology-weekly cover or front page
                - include one hero visual plus supporting sidebars tied to the stories
                - allow headlines, pull quotes, labels, issue numbers, and diagram annotations
                - keep the layout balanced and attractive rather than cluttered
                """,
                target: target
            )
        }
    }

    private func structuredPrompt(
        headlines: String,
        keys: String,
        requirements: String,
        target: GenerationTarget
    ) -> String {
        """
        Input headlines:
        \(headlines)

        Return one strict JSON object with these keys: \(keys).
        Do not wrap the JSON in Markdown fences and do not add analysis or explanation.

        Requirements for image_prompt:
        \(requirements)
        - compose the image specifically for \(target.frameDescription)
        """
    }
}
