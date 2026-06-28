import Foundation

public enum ANNError: Error, Sendable {
    case rateLimited           // 503 от nodelay-эндпоинта
    case http(Int)
    case parseFailure(String)
    case badURL
}

/// клиент ANN: дросселирует запросы до 1 req/сек на IP (требование API)
/// и кэширует ответы на диск
public actor APIClient {
    public static let detailsBase = "https://cdn.animenewsnetwork.com/encyclopedia/api.xml"
    public static let reportsBase = "https://www.animenewsnetwork.com/encyclopedia/reports.xml"

    // описательный User-Agent: вежливо к API и устойчивее дефолта URLSession
    public static let userAgent = "ANNReader/1.1 (+https://github.com/boundlessend/ann_reader)"
    private static let maxAttempts = 3

    // свежесть кэша по типу данных: ленту новостей всегда берём из сети (кэш - только
    // офлайн-фоллбэк), иначе пропускали бы свежие статьи; каталог и детали почти
    // статичны - держим их 15 дней
    public static let newsMaxAge: TimeInterval = 0
    public static let catalogMaxAge: TimeInterval = 15 * 86_400
    public static let titleMaxAge: TimeInterval = 15 * 86_400

    private let session: URLSession
    private let cacheDir: URL
    private let minInterval: TimeInterval
    private var nextSlot = Date.distantPast

    public init(minInterval: TimeInterval = 1.0, session: URLSession = .shared) {
        self.minInterval = minInterval
        self.session = session
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = base.appendingPathComponent("ANNReader", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // резервирует следующий слот без await до присваивания, поэтому гонок нет
    private func throttle() async {
        let now = Date()
        let slot = max(now, nextSlot)
        nextSlot = slot.addingTimeInterval(minInterval)
        let delay = slot.timeIntervalSince(now)
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private func cachePath(_ url: URL) -> URL {
        cacheFilePath(dir: cacheDir, url: url, ext: "xml")
    }

    // транзиентные сбои стоит повторить; "нет сети" и отмену - нет
    private func isTransient(_ error: Error) -> Bool {
        switch error {
        case ANNError.rateLimited: return true
        case ANNError.http(let code): return code >= 500
        case let u as URLError: return u.code != .notConnectedToInternet
        default: return false
        }
    }

    /// отдаёт свежий кэш, иначе тянет из сети с повтором транзиентных сбоев;
    /// исчерпав попытки, возвращает последнюю удачную копию, если она есть
    public func fetchData(_ url: URL, maxAge: TimeInterval) async throws -> Data {
        let path = cachePath(url)
        if maxAge > 0, cacheIsFresh(path, ttl: maxAge), let fresh = try? Data(contentsOf: path) {
            return fresh
        }
        var req = URLRequest(url: url)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        var lastError: Error?
        for attempt in 0..<Self.maxAttempts {
            do {
                await throttle()
                let (data, response) = try await session.data(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw http.statusCode == 503 ? ANNError.rateLimited : ANNError.http(http.statusCode)
                }
                try? data.write(to: path)
                return data
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                lastError = error
                guard isTransient(error), attempt < Self.maxAttempts - 1 else { break }
                // короткий экспоненциальный бэкофф перед повтором (0.5с, затем 1с)
                try? await Task.sleep(nanoseconds: UInt64(0.5 * pow(2, Double(attempt)) * 1_000_000_000))
            }
        }
        if let stale = try? Data(contentsOf: path) { return stale }
        throw lastError ?? ANNError.badURL
    }

    // id в энциклопедии ANN всегда числовой - отсекаем мусор до построения URL
    private func validID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy(\.isNumber)
    }

    /// детали одного тайтла (аниме или манга)
    public func fetchTitle(kind: TitleKind, id: String, maxAge: TimeInterval) async throws -> EncTitle {
        guard validID(id) else { throw ANNError.badURL }
        guard let url = URL(string: "\(Self.detailsBase)?\(kind.rawValue)=\(id)") else { throw ANNError.badURL }
        let data = try await fetchData(url, maxAge: maxAge)
        guard let title = try EncyclopediaParser().parse(data).first else {
            throw ANNError.parseFailure("no \(kind.rawValue) with id \(id)")
        }
        return title
    }

    /// каталог из reports.xml: фильтр по первой букве name и пагинация
    public func fetchCatalog(kind: TitleKind, name: String, skip: Int, list: Int,
                             maxAge: TimeInterval) async throws -> [CatalogItem] {
        var comps = URLComponents(string: Self.reportsBase)!
        comps.queryItems = [
            .init(name: "id", value: "155"),   // 155 - отчёт-листинг энциклопедии в reports.xml
            .init(name: "type", value: kind.rawValue),
            .init(name: "nskip", value: "\(skip)"),
            .init(name: "nlist", value: "\(list)"),
            .init(name: "name", value: name),
        ]
        guard let url = comps.url else { throw ANNError.badURL }
        let data = try await fetchData(url, maxAge: maxAge)
        return try ReportParser(kind: kind).parse(data)
    }

    /// лента статей категории из html-листинга ANN (с превью-картинками)
    public func fetchNews(feed: URL, maxAge: TimeInterval) async throws -> [NewsItem] {
        let data = try await fetchData(feed, maxAge: maxAge)
        return try HeraldParser.parse(data)
    }
}
