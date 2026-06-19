import Foundation
import CryptoKit

/// дисковый кэш превью на 15 дней: сервер отдаёт max-age лишь сутки, а нам нужно,
/// чтобы картинки переживали перезапуск и показывались офлайн
/// ponytail: без троттлинга (превью грузятся пачкой), ключ - SHA256 от url;
/// протухшее отдаём как офлайн-фоллбэк, если сеть недоступна
actor ImageCache {
    static let shared = ImageCache()

    private let ttl: TimeInterval = 15 * 86_400
    private let dir: URL
    private var swept = false

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("ANNReaderImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// свежие данные из кэша, иначе из сети; при сбое сети - последняя копия с диска
    func data(for url: URL) async -> Data? {
        sweepOnce()
        let path = cachePath(url)
        if let fresh = freshData(path) { return fresh }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            return try? Data(contentsOf: path)
        }
        try? data.write(to: path)
        return data
    }

    private func cachePath(_ url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent("\(key).img")
    }

    private func freshData(_ path: URL) -> Data? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let mtime = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(mtime) < ttl else { return nil }
        return try? Data(contentsOf: path)
    }

    // один раз за запуск выметаем протухшие файлы, чтобы кэш не рос вечно
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
