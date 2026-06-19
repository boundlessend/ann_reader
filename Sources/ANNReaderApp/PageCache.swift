import Foundation
import CryptoKit

/// дисковый кэш HTML открытых статей на 15 дней: повторный заход открывается
/// мгновенно и переживает перезапуск приложения
/// ponytail: синхронное чтение одного файла при открытии статьи - операция
/// пользовательская и редкая, отдельный поток не нужен; ключ - SHA256 от url
@MainActor
final class PageCache {
    static let shared = PageCache()

    private let ttl: TimeInterval = 15 * 86_400
    private let dir: URL
    private var swept = false

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("ANNReaderPages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// свежий HTML для url, если он есть и не протух
    func html(for url: URL) -> String? {
        let path = cachePath(url)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let mtime = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(mtime) < ttl else { return nil }
        return try? String(contentsOf: path, encoding: .utf8)
    }

    /// сохраняет HTML и один раз за запуск выметает протухшие записи
    func store(_ html: String, for url: URL) {
        sweepOnce()
        try? html.write(to: cachePath(url), atomically: true, encoding: .utf8)
    }

    private func cachePath(_ url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent("\(key).html")
    }

    private func sweepOnce() {
        guard !swept else { return }
        swept = true
        let cutoff = Date().addingTimeInterval(-ttl)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir,
                     includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let mtime, mtime < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }
}
