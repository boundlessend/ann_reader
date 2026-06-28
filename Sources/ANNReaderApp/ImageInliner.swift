import Foundation
import ANNKit

/// встраивает картинки статьи в html как data-URI, чтобы сохранённая страница
/// открывалась полностью офлайн (вместе с изображениями)
/// ponytail: грузим максимум 25 картинок (окном по 6 параллельно, чтобы не бить
/// по серверу разом) и пропускаем тяжелее 3 МБ - потолок против раздувания
/// хранилища; статьям ANN этого с запасом хватает
enum ImageInliner {
    private static let maxImages = 25
    private static let maxBytes = 3_000_000
    private static let maxConcurrent = 6

    static func inline(html: String) async -> String {
        let urls = Array(imageURLs(in: html).prefix(maxImages))
        var replacements: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            var next = 0
            while next < min(maxConcurrent, urls.count) {
                let raw = urls[next]
                group.addTask { (raw, await dataURI(for: raw)) }
                next += 1
            }
            for await (raw, uri) in group {
                if let uri { replacements[raw] = uri }
                if next < urls.count {
                    let raw = urls[next]
                    group.addTask { (raw, await dataURI(for: raw)) }
                    next += 1
                }
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
        var req = URLRequest(url: url)
        req.setValue(APIClient.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              data.count <= maxBytes else { return nil }
        let mime = response.mimeType ?? "image/jpeg"
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
}
