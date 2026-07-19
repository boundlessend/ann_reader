import Testing
import Foundation
@testable import ANNKit

// стаб: мгновенно отдаёт 200 с фиксированным телом, без сети
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data("<ann/>".utf8)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: StubProtocol.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func stubSession() -> URLSession {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [StubProtocol.self]
    return URLSession(configuration: cfg)
}

// временный каталог кэша на тест: не пишем в реальный пользовательский Caches
private func tempCacheDir() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ANNKitTests-\(UUID().uuidString)", isDirectory: true)
}

// ядро Фазы 1: N запросов должны растягиваться минимум на (N-1)*interval
@Test func throttleSerializesSlots() async throws {
    let interval = 0.05
    let n = 20
    let client = APIClient(minInterval: interval, session: stubSession(), cacheDir: tempCacheDir())
    let url = URL(string: "https://example.com/a")!

    let start = Date()
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<n {
            group.addTask {
                // разные URL -> кэш не короткозамыкает
                _ = try? await client.fetchData(url.appending(queryItems: [.init(name: "i", value: "\(i)")]),
                                                 maxAge: 0)
            }
        }
    }
    let elapsed = Date().timeIntervalSince(start)
    #expect(elapsed >= Double(n - 1) * interval)
}

// стаб со сценарием: отдаёт ответы из очереди по порядку
final class ScriptedProtocol: URLProtocol {
    nonisolated(unsafe) static var script: [(code: Int, body: Data)] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let step = Self.script.isEmpty ? (code: 200, body: Data()) : Self.script.removeFirst()
        let resp = HTTPURLResponse(url: request.url!, statusCode: step.code,
                                   httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: step.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

// делят static-очередь ScriptedProtocol, поэтому выполняются последовательно
@Suite(.serialized) struct FetchRetryTests {
    private func scriptedClient() -> APIClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [ScriptedProtocol.self]
        return APIClient(minInterval: 0.01, session: URLSession(configuration: cfg),
                         cacheDir: tempCacheDir())
    }

    @Test func retriesTransientErrorsUntilSuccess() async throws {
        ScriptedProtocol.script = [(500, Data()), (503, Data()), (200, Data("ok".utf8))]
        let client = scriptedClient()
        let data = try await client.fetchData(URL(string: "https://example.com/r")!, maxAge: 0)
        #expect(data == Data("ok".utf8))
        #expect(ScriptedProtocol.script.isEmpty)
    }

    @Test func fallsBackToStaleCacheWhenAttemptsExhausted() async throws {
        let client = scriptedClient()
        let url = URL(string: "https://example.com/s")!
        ScriptedProtocol.script = [(200, Data("good".utf8))]
        _ = try await client.fetchData(url, maxAge: 0)   // кладёт копию в кэш
        ScriptedProtocol.script = [(500, Data()), (500, Data()), (500, Data())]
        let stale = try await client.fetchData(url, maxAge: 0)
        #expect(stale == Data("good".utf8))
        #expect(ScriptedProtocol.script.isEmpty)   // все три попытки исчерпаны
    }
}

@Test func parsesEncyclopediaTitle() throws {
    let xml = """
    <ann>
      <anime id="4658" name="Cowboy Bebop" type="TV">
        <info type="Picture" src="https://cdn.example/pic.jpg"/>
        <info type="Genres">action</info>
        <info type="Genres">drama</info>
        <cast lang="JA">
          <role>Spike</role>
          <person id="11">Koichi Yamadera</person>
        </cast>
        <staff>
          <task>Director</task>
          <person id="22">Shinichiro Watanabe</person>
        </staff>
      </anime>
    </ann>
    """
    let titles = try EncyclopediaParser().parse(Data(xml.utf8))
    let t = try #require(titles.first)
    #expect(t.id == "4658")
    #expect(t.name == "Cowboy Bebop")
    #expect(t.kind == .anime)
    #expect(t.pictureURL?.absoluteString == "https://cdn.example/pic.jpg")
    #expect(t.info["Genres"] == ["action", "drama"])
    #expect(t.cast.first?.personName == "Koichi Yamadera")
    #expect(t.cast.first?.role == "Spike")
    #expect(t.staff.first?.task == "Director")
}

@Test func parsesCatalogReport() throws {
    let xml = """
    <report skipped="0" listed="2"><args><type>anime</type></args>
      <item><id>32539</id><gid>1</gid><type>TV</type><name>ZENSHU.</name><precision>TV</precision><vintage>2025-01-05</vintage></item>
      <item><id>38280</id><gid>2</gid><type>movie</type><name>ZERO RISE</name><precision>movie</precision></item>
    </report>
    """
    let items = try ReportParser(kind: .anime).parse(Data(xml.utf8))
    #expect(items.count == 2)
    #expect(items[0].name == "ZENSHU.")
    #expect(items[0].type == "TV")
    #expect(items[0].vintage == "2025-01-05")
    #expect(items[1].vintage == nil)
    #expect(items[1].kind == .anime)
}

@Test func parsesHeraldListing() throws {
    // фрагмент реального html-листинга ANN: блок статьи с превью
    let html = """
    <div class="herald box news t-news" data-topics="article238699 news anime">
      <div class="thumbnail lazyload" data-src="/thumbnails/crop348x200gH8/youtube/Gq5ps9WFkhM.jpg">
        <a href="/news/2026-06-19/sample-anime-reveals-cast/.238699"></a>
      </div>
      <div class="wrap"><div><h3>
        <a href="/news/2026-06-19/sample-anime-reveals-cast/.238699">'<cite>Sample &amp; Co</cite>' Anime Reveals Cast</a>
      </h3>
      <div class="byline"><time datetime="2026-06-19T11:03:20+00:00">Jun 19</time></div>
      </div></div>
    </div>
    """
    // обзор: путь без даты - проверяем, что он тоже парсится (ловится по id)
    let review = """
    <div class="herald box reviews t-review" data-topics="article238365 reviews live-action">
      <div class="thumbnail lazyload" data-src="/thumbnails/crop348x200gJA/cms/review.2/238365/poster.jpg">
        <a href="/review/uncanny-counter-season-1/live-action-series/.238365"></a>
      </div>
      <div class="wrap"><div><h3>
        <a href="/review/uncanny-counter-season-1/live-action-series/.238365"><cite>Uncanny Counter</cite> Season 1 Review</a>
      </h3>
      <div class="byline"><time datetime="2026-06-17T16:00:00+00:00">Jun 17</time></div>
      </div></div>
    </div>
    """
    let items = try HeraldParser.parse(Data((html + review).utf8))
    let item = try #require(items.first)
    #expect(item.id == "238699")
    #expect(item.title == "'Sample & Co' Anime Reveals Cast")
    #expect(item.link.absoluteString == "https://www.animenewsnetwork.com/news/2026-06-19/sample-anime-reveals-cast/.238699")
    #expect(item.imageURL?.absoluteString == "https://www.animenewsnetwork.com/thumbnails/crop348x200gH8/youtube/Gq5ps9WFkhM.jpg")
    #expect(item.published != nil)

    let rev = try #require(items.first { $0.id == "238365" })
    #expect(rev.title == "Uncanny Counter Season 1 Review")
    #expect(rev.link.absoluteString == "https://www.animenewsnetwork.com/review/uncanny-counter-season-1/live-action-series/.238365")
    #expect(rev.imageURL != nil)
}

// &amp; декодируется последним: литеральный "&amp;lt;" остаётся "&lt;", не "<"
@Test func decodesEntitiesSinglePass() throws {
    let html = """
    <div class="herald box news" data-topics="article1 news">
      <h3><a href="/news/2026-01-01/x/.1">A &amp;lt;tag&amp;gt; &amp; &#8217;quote&#8217;</a></h3>
    </div>
    """
    let item = try #require(try HeraldParser.parse(Data(html.utf8)).first)
    #expect(item.title == "A &lt;tag&gt; & \u{2019}quote\u{2019}")
}
