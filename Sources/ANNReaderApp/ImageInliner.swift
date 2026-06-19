import Foundation

/// встраивает картинки статьи в html как data-URI, чтобы сохранённая страница
/// открывалась полностью офлайн (вместе с изображениями)
/// ponytail: грузим максимум 25 картинок и пропускаем тяжелее 3 МБ - потолок
/// против раздувания хранилища; статьям ANN этого с запасом хватает
enum ImageInliner {
    private static let maxImages = 25
    private static let maxBytes = 3_000_000

    static func inline(html: String) async -> String {
        let urls = imageURLs(in: html).prefix(maxImages)
        var replacements: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            for raw in urls {
                group.addTask { (raw, await dataURI(for: raw)) }
            }
            for await (raw, uri) in group {
                if let uri { replacements[raw] = uri }
            }
        }
        var result = html
        for (raw, uri) in replacements {
            result = result.replacingOccurrences(of: raw, with: uri)
        }
        return result
    }

    private static func imageURLs(in html: String) -> [String] {
        let pattern = #"https?://[^"'\s)]+\.(?:jpg|jpeg|png|gif|webp)"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        let found = re.matches(in: html, range: range).compactMap { Range($0.range, in: html).map { String(html[$0]) } }
        return Array(Set(found))
    }

    private static func dataURI(for raw: String) async -> String? {
        guard let url = URL(string: raw) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              data.count <= maxBytes else { return nil }
        let mime = response.mimeType ?? "image/jpeg"
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
}
