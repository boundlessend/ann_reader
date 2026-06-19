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

// ядро Фазы 1: N запросов должны растягиваться минимум на (N-1)*interval
@Test func throttleSerializesSlots() async throws {
    let interval = 0.05
    let n = 20
    let client = APIClient(minInterval: interval, session: stubSession())
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
    let items = try HeraldParser.parse(Data(html.utf8))
    let item = try #require(items.first)
    #expect(item.id == "238699")
    #expect(item.title == "'Sample & Co' Anime Reveals Cast")
    #expect(item.link.absoluteString == "https://www.animenewsnetwork.com/news/2026-06-19/sample-anime-reveals-cast/.238699")
    #expect(item.imageURL?.absoluteString == "https://www.animenewsnetwork.com/thumbnails/crop348x200gH8/youtube/Gq5ps9WFkhM.jpg")
    #expect(item.published != nil)
}
