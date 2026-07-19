import Foundation
import Observation
import Network
import ANNKit

/// состояние приложения и единый клиент ANN (троттлинг общий на IP)
@MainActor
@Observable
final class AppModel {
    let client = APIClient()
    var isOffline = false

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor in self?.isOffline = offline }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    /// переводит ошибки сети или API в понятное локализованное сообщение
    func friendly(_ error: Error) -> String {
        if let e = error as? ANNError {
            switch e {
            case .rateLimited:
                return String(localized: "ANN rate-limited requests (1/sec limit). Wait a moment and retry.")
            case .http(let code):
                return String(localized: "ANN server returned an error (HTTP \(code)).")
            case .parseFailure(let msg):
                return String(localized: "Could not parse ANN response: \(msg)")
            case .badURL:
                return String(localized: "Invalid request to ANN.")
            }
        }
        if let u = error as? URLError, u.code == .notConnectedToInternet {
            return String(localized: "No internet connection.")
        }
        return error.localizedDescription
    }

    // отмена задачи (переключили вкладку, ушли с экрана) - не ошибка для пользователя:
    // иначе отменённый запрос затирает общее состояние словом "cancelled"
    private func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    var news: [NewsItem] = []
    var newsError: String?
    var loadingNews = false
    // растёт на каждую загрузку ленты: Refresh порождает неструктурированную задачу,
    // которую смена вкладки не отменяет, и без счётчика её результат затирал бы новую ленту
    private var newsGeneration = 0

    var catalog: [CatalogItem] = []
    var catalogQuery = ""               // текст в поле поиска
    private(set) var catalogName = "A"  // активный фильтр: буква или поисковый префикс
    var catalogError: String?
    var loadingCatalog = false
    private(set) var catalogKind: TitleKind = .anime
    private(set) var catalogExhausted = false   // последняя страница короче pageSize - дальше пусто
    private var catalogSkip = 0
    private static let pageSize = 50
    // растёт на каждую новую загрузку каталога: устаревший результат после await отбрасываем
    private var catalogGeneration = 0

    /// грузит выбранную категорию-ленту; список очищается, чтобы не мелькала прежняя
    func loadNews(feed: URL) async {
        newsGeneration += 1
        let gen = newsGeneration
        loadingNews = true
        newsError = nil
        news = []
        do {
            let items = try await client.fetchNews(feed: feed, maxAge: APIClient.newsMaxAge)
            guard gen == newsGeneration else { return }   // началась новая загрузка
            news = items
        } catch {
            guard gen == newsGeneration, !isCancellation(error) else { return }
            newsError = friendly(error)
        }
        guard gen == newsGeneration else { return }
        loadingNews = false
    }

    /// грузит каталог по фильтру name (буква из алфавита или поисковый префикс)
    func loadCatalog(kind: TitleKind, name: String) async {
        catalogGeneration += 1
        let gen = catalogGeneration
        catalogKind = kind
        catalogName = name
        catalogSkip = 0
        loadingCatalog = true
        catalogError = nil
        do {
            let items = try await client.fetchCatalog(kind: kind, name: name, skip: 0,
                                                      list: Self.pageSize,
                                                      maxAge: APIClient.catalogMaxAge)
            guard gen == catalogGeneration else { return }   // началась новая загрузка - наш результат устарел
            catalog = items
            catalogSkip = items.count
            catalogExhausted = items.count < Self.pageSize
        } catch {
            guard gen == catalogGeneration, !isCancellation(error) else { return }
            catalogError = friendly(error)
        }
        guard gen == catalogGeneration else { return }
        loadingCatalog = false
    }

    /// поиск по текущему запросу; пустой запрос возвращает к началу алфавита
    func searchCatalog(kind: TitleKind) async {
        let query = catalogQuery.trimmingCharacters(in: .whitespaces)
        await loadCatalog(kind: kind, name: query.isEmpty ? "A" : query)
    }

    func loadMoreCatalog() async {
        guard !loadingCatalog, !catalogExhausted else { return }
        let gen = catalogGeneration
        loadingCatalog = true
        do {
            let more = try await client.fetchCatalog(kind: catalogKind, name: catalogName,
                                                     skip: catalogSkip, list: Self.pageSize,
                                                     maxAge: APIClient.catalogMaxAge)
            guard gen == catalogGeneration else { return }   // фильтр сменился - дозагрузку прежнего отбрасываем
            catalog.append(contentsOf: more)
            catalogSkip += more.count
            catalogExhausted = more.count < Self.pageSize
        } catch {
            guard gen == catalogGeneration, !isCancellation(error) else { return }
            catalogError = friendly(error)
        }
        guard gen == catalogGeneration else { return }
        loadingCatalog = false
    }

    func title(kind: TitleKind, id: String) async throws -> EncTitle {
        try await client.fetchTitle(kind: kind, id: id, maxAge: APIClient.titleMaxAge)
    }
}
