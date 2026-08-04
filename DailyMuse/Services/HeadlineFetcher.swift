import Foundation

enum HeadlineSourceType: String, CaseIterable, Identifiable {
    case hackerNews
    case rss

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hackerNews: "Hacker News"
        case .rss: "RSS Feed"
        }
    }
}

enum HeadlineFetcher {

    static func fetch(source: HeadlineSourceType, rssURL: String = "", count: Int = 10) async throws -> [String] {
        switch source {
        case .hackerNews:
            return try await fetchHackerNews(count: count)
        case .rss:
            return try await fetchRSS(urlString: rssURL, count: count)
        }
    }

    // MARK: - Hacker News (Firebase API)

    private static func fetchHackerNews(count: Int) async throws -> [String] {
        let topStoriesURL = URL(string: "https://hacker-news.firebaseio.com/v0/topstories.json")!
        let (data, _) = try await URLSession.shared.data(from: topStoriesURL)
        let ids = try JSONDecoder().decode([Int].self, from: data)

        let topIDs = Array(ids.prefix(count))

        return try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, id) in topIDs.enumerated() {
                group.addTask {
                    let itemURL = URL(string: "https://hacker-news.firebaseio.com/v0/item/\(id).json")!
                    let (itemData, _) = try await URLSession.shared.data(from: itemURL)
                    let item = try JSONDecoder().decode(HNItem.self, from: itemData)
                    return (index, item.title)
                }
            }

            var results = [(Int, String)]()
            for try await result in group {
                results.append(result)
            }

            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    // MARK: - RSS (basic XML parsing)

    private static func fetchRSS(urlString: String, count: Int) async throws -> [String] {
        guard let url = URL(string: urlString) else {
            throw DailyMuseError.invalidURL(urlString)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let parser = RSSParser(count: count)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()

        guard !parser.titles.isEmpty else {
            throw DailyMuseError.noHeadlines
        }

        return parser.titles
    }
}

// MARK: - Models

private struct HNItem: Decodable {
    let title: String
}

// MARK: - RSS Parser

private class RSSParser: NSObject, XMLParserDelegate {
    let maxCount: Int
    var titles: [String] = []

    private var insideItem = false
    private var insideTitle = false
    private var currentTitle = ""

    init(count: Int) {
        self.maxCount = count
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if element == "item" || element == "entry" { insideItem = true }
        if insideItem && (element == "title") {
            insideTitle = true
            currentTitle = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideTitle { currentTitle += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        if insideTitle && element == "title" {
            insideTitle = false
            let trimmed = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && titles.count < maxCount {
                titles.append(trimmed)
            }
        }
        if element == "item" || element == "entry" { insideItem = false }
    }
}
