import Foundation
import ANNKit

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
        let path = cacheFilePath(dir: dir, url: url, ext: "img")
        if cacheIsFresh(path, ttl: ttl), let fresh = try? Data(contentsOf: path) { return fresh }
        var req = URLRequest(url: url)
        req.setValue(APIClient.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            return try? Data(contentsOf: path)
        }
        try? data.write(to: path)
        return data
    }

    // один раз за запуск выметаем протухшие файлы, чтобы кэш не рос вечно
    private func sweepOnce() {
        guard !swept else { return }
        swept = true
        cacheSweep(dir: dir, ttl: ttl)
    }
}
