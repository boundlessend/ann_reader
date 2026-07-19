import Foundation

/// парсер списка статей ANN (страница-листинг с превью): RSS-фид картинок не отдаёт,
/// поэтому тянем превью прямо из герольд-блоков html-страницы категории
/// ponytail: html разбираем регекспами - вёрстка ANN стабильна годами, а полноценный
/// html-парсер тут избыточен; тест ниже падает, если структура блока изменится
public enum HeraldParser {
    private static let host = "https://www.animenewsnetwork.com"

    /// один герольд-блок статьи: id, ссылка, заголовок, превью, дата
    public static func parse(_ data: Data) throws -> [NewsItem] {
        guard let html = String(data: data, encoding: .utf8) else {
            throw ANNError.parseFailure("listing not utf8")
        }
        // formatter создаём на вызов: ISO8601DateFormatter не Sendable
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return splitBlocks(html).compactMap { item(from: $0, iso: iso) }
    }

    // режем страницу по началам герольд-блоков, каждый кусок парсим отдельно
    private static func splitBlocks(_ html: String) -> [Substring] {
        let marker = "herald box"
        var result: [Substring] = []
        var search = html.startIndex
        var starts: [String.Index] = []
        while let r = html.range(of: marker, range: search..<html.endIndex) {
            starts.append(r.lowerBound)
            search = r.upperBound
        }
        for (i, start) in starts.enumerated() {
            let end = i + 1 < starts.count ? starts[i + 1] : html.endIndex
            result.append(html[start..<end])
        }
        return result
    }

    private static func item(from block: Substring, iso: ISO8601DateFormatter) -> NewsItem? {
        let s = String(block)
        guard let id = first(s, #"data-topics="article(\d+)"#) else { return nil }
        // ссылка статьи всегда заканчивается на "/.<id>"; не привязываемся к дате в пути,
        // иначе обзоры (/review/title/sub/.id без даты) не находятся
        guard let href = first(s, "<a href=\"(/[^\"]*?/\\.\(id))\""),
              let url = URL(string: host + href) else { return nil }

        let title = first(s, #"<h3>\s*<a [^>]*>(.*?)</a>"#).map(cleanTitle) ?? href
        let image = first(s, #"data-src="(/thumbnails/[^"]+)""#).flatMap { URL(string: host + $0) }
        let date = first(s, #"datetime="([^"]+)""#).flatMap(iso.date(from:))

        return NewsItem(id: id, title: title, link: url, published: date, imageURL: image)
    }

    // первая группа первого совпадения
    private static func first(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    // выкидываем html-теги (<cite> и пр.) и раскрываем html-сущности
    private static func cleanTitle(_ raw: String) -> String {
        let noTags = raw.replacingOccurrences(of: "<[^>]+>", with: "",
                                              options: .regularExpression)
        return decodeEntities(noTags).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ s: String) -> String {
        var out = s
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
        // числовые сущности вида &#xA9; и &#8217;
        for pattern in [#"&#x([0-9a-fA-F]+);"#: 16, #"&#(\d+);"#: 10] {
            out = replaceNumeric(out, pattern: pattern.key, radix: pattern.value)
        }
        // &amp; строго последним: иначе "&amp;lt;" декодировался бы дважды в "<"
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func replaceNumeric(_ s: String, pattern: String, radix: Int) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        var result = s
        let matches = re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed()
        for m in matches {
            guard let whole = Range(m.range, in: result),
                  let g = Range(m.range(at: 1), in: result),
                  let code = UInt32(result[g], radix: radix),
                  let scalar = Unicode.Scalar(code) else { continue }
            result.replaceSubrange(whole, with: String(scalar))
        }
        return result
    }

}
