import Foundation
import ANNKit

/// дисковый кэш HTML открытых статей на 15 дней: повторный заход открывается
/// мгновенно и переживает перезапуск приложения
/// ponytail: чтение одного файла при открытии статьи синхронно (операция редкая,
/// пользовательская), а запись крупного html уводим с главного потока
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
        let path = cacheFilePath(dir: dir, url: url, ext: "html")
        guard cacheIsFresh(path, ttl: ttl) else { return nil }
        return try? String(contentsOf: path, encoding: .utf8)
    }

    /// сохраняет HTML неблокирующе и раз за запуск выметает протухшие записи
    func store(_ html: String, for url: URL) {
        let path = cacheFilePath(dir: dir, url: url, ext: "html")
        let sweepNow = !swept
        swept = true
        let dir = self.dir, ttl = self.ttl
        Task.detached(priority: .utility) {
            try? html.write(to: path, atomically: true, encoding: .utf8)
            if sweepNow { cacheSweep(dir: dir, ttl: ttl) }
        }
    }
}
