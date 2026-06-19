import Foundation

/// кэш HTML открытых статей в памяти: повторный заход в течение 5 минут
/// открывается мгновенно, потом запись автоудаляется
/// ponytail: in-memory словарь, TTL от последней загрузки; диск не нужен -
/// статьи лёгкие и кэш живёт лишь минуты
@MainActor
final class PageCache {
    static let shared = PageCache()

    private struct Entry {
        let html: String
        let storedAt: Date
    }

    private let ttl: TimeInterval = 300
    private var entries: [String: Entry] = [:]

    private init() {}

    /// свежий HTML для url, если он есть и не протух
    func html(for url: URL) -> String? {
        let key = url.absoluteString
        guard let entry = entries[key] else { return nil }
        if Date().timeIntervalSince(entry.storedAt) >= ttl {
            entries[key] = nil
            return nil
        }
        return entry.html
    }

    /// сохраняет HTML и попутно выметает протухшие записи
    func store(_ html: String, for url: URL) {
        let now = Date()
        entries = entries.filter { now.timeIntervalSince($0.value.storedAt) < ttl }
        entries[url.absoluteString] = Entry(html: html, storedAt: now)
    }
}
