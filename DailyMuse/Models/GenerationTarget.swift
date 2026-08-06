import Foundation

enum GenerationTarget: String, Codable, Sendable {
    case web
    case eink

    var frameDescription: String {
        switch self {
        case .web:
            "a 16:9 desktop wallpaper for a modern screen"
        case .eink:
            "an 800×480 monochrome e-ink display"
        }
    }

    var promptDirection: String {
        switch self {
        case .web:
            """
            Optimize for a rich 16:9 desktop wallpaper. Use the full tonal range and color where \
            helpful, with readable composition, atmospheric lighting, and enough quiet space for \
            desktop icons. Do not force monochrome or 1-bit constraints.
            """
        case .eink:
            """
            Optimize for a 1-bit 800×480 black-and-white e-ink display. White must be the dominant \
            field, targeting roughly 75–85% white area and 15–25% black area. Avoid giant black \
            backgrounds, dense black slabs, subtle gray-on-gray detail, and full-frame darkness. \
            Favor clean white space, bold black linework, silhouettes, outlines, and details that \
            remain readable after monochrome dithering.
            """
        }
    }
}
