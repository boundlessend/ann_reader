import SwiftUI
import SwiftData
import WebKit

/// reader-режим: грузит страницу статьи скрыто, по готовности показывает только
/// текст и картинки из div.KonaBody; типографику (размер, шрифт, фон, режим для
/// дислексиков) можно настроить, во время загрузки виден skeleton
/// ponytail: завязка на класс KonaBody хрупка к смене вёрстки ANN ->
/// фоллбэк "Открыть в Safari" всегда под рукой
struct ReaderView: View {
    let url: URL
    let title: String
    let offline: Bool   // открыть сохранённую офлайн-копию из SwiftData вместо сети

    @Environment(\.modelContext) private var context
    @Environment(\.pushRoute) private var pushRoute
    @Query private var saved: [SavedPage]   // только запись текущего url, не вся таблица

    @State private var readerMode = true
    @State private var loading = true
    @State private var loadError: String?
    @State private var reloadToken = UUID()
    @State private var pageHTML: String?   // очищенный html статьи для сохранения
    @State private var displayTitle: String
    @AppStorage("readerFontSize") private var fontSize: Double = 17
    @AppStorage("readerFont") private var font = ReaderFont.system
    @AppStorage("readerTheme") private var theme = ReaderTheme.auto
    @AppStorage("readerDyslexia") private var dyslexia = false

    init(url: URL, title: String, offline: Bool) {
        self.url = url
        self.title = title
        self.offline = offline
        _displayTitle = State(initialValue: title)
        let urlString = url.absoluteString
        _saved = Query(filter: #Predicate<SavedPage> { $0.urlString == urlString })
    }

    private var style: ReaderStyle {
        ReaderStyle(fontSize: fontSize, font: font, theme: theme, dyslexia: dyslexia)
    }

    private var isSaved: Bool { !saved.isEmpty }

    private var offlineHTML: String? {
        offline ? saved.first?.offlineHTML : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ArticleWebView(url: url, offlineHTML: offlineHTML, readerMode: readerMode,
                               style: style,
                               onReady: { loading = false },
                               onHTML: { handleExtracted($0) },
                               onTitle: { handleTitle($0) },
                               onError: { loadError = $0; loading = false },
                               onPush: { pushRoute(.article(url: $0, title: Self.slugTitle($0),
                                                            offline: false)) })
                    .id(reloadToken)
                    .opacity(loading || loadError != nil ? 0 : 1)   // не показываем сырую страницу до очистки
                if let loadError {
                    ContentUnavailableView {
                        Label("Could not load the article", systemImage: "wifi.slash")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Retry") { retry() }
                        Button("Open in Safari") { NSWorkspace.shared.open(url) }
                    }
                } else if loading {
                    ReaderSkeleton().transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: loading)
            attribution
        }
        // переключение reader перезагружает страницу: показываем skeleton и плавно
        // перетекаем через него, иначе контент сменяется рывком
        .onChange(of: readerMode) { _, _ in loading = true }
        .navigationTitle(displayTitle)
        .toolbar {
            Toggle("Reader", systemImage: "doc.plaintext", isOn: $readerMode)
            typographyMenu.disabled(!readerMode)
            Button(isSaved ? "Remove from saved" : "Save",
                   systemImage: isSaved ? "bookmark.fill" : "bookmark") { toggleSaved() }
                .symbolEffect(.bounce, value: isSaved)
            Button("Safari", systemImage: "safari") { NSWorkspace.shared.open(url) }
        }
    }

    private var typographyMenu: some View {
        Menu {
            Button("Smaller text", systemImage: "textformat.size.smaller") {
                fontSize = max(11, fontSize - 2)
            }
            Button("Larger text", systemImage: "textformat.size.larger") {
                fontSize = min(28, fontSize + 2)
            }
            Picker("Font", selection: $font) {
                ForEach(ReaderFont.allCases) { Text(verbatim: $0.displayName).tag($0) }
            }
            Picker("Theme", selection: $theme) {
                ForEach(ReaderTheme.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Dyslexia-friendly", isOn: $dyslexia)
        } label: {
            Label("Text settings", systemImage: "textformat")
        }
    }

    private func retry() {
        loadError = nil
        loading = true
        reloadToken = UUID()   // пересоздаёт webview, загрузка начинается заново
    }

    // заголовок пушнутой ссылки до загрузки - слаг из url, после didFinish
    // подставляем настоящий document.title без хвоста сайта
    private func handleTitle(_ raw: String) {
        let cleaned = raw.replacingOccurrences(of: " - Anime News Network", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty { displayTitle = cleaned }
    }

    // очищенный html приходит после каждой загрузки (в обоих режимах читалки);
    // если статья сохранена без офлайн-копии (сохранили до извлечения), дозаполняем
    private func handleExtracted(_ html: String) {
        pageHTML = html
        if let page = saved.first, page.offlineHTML == nil {
            page.offlineHTML = Self.wrap(html)
            inlineImages(into: html)
        }
    }

    // мгновенно переключаем закладку, офлайн-html со встроенными картинками
    // дозагружаем фоном и дописываем в ту же запись
    private func toggleSaved() {
        if let existing = saved.first {
            context.delete(existing)
            return
        }
        let cleaned = pageHTML
        let page = SavedPage(urlString: url.absoluteString, title: displayTitle,
                             savedAt: Date(), offlineHTML: cleaned.map(Self.wrap))
        context.insert(page)
        if let cleaned { inlineImages(into: cleaned) }
    }

    // встраивание картинок идёт фоном; по завершении перечитываем запись по url,
    // потому что закладку могли снять, пока шёл инлайн
    private func inlineImages(into cleaned: String) {
        let urlString = url.absoluteString
        let context = context
        Task {
            let inlined = await ImageInliner.inline(html: cleaned)
            let match = FetchDescriptor<SavedPage>(
                predicate: #Predicate { $0.urlString == urlString })
            if let page = try? context.fetch(match).first {
                page.offlineHTML = Self.wrap(inlined)
            }
        }
    }

    // человекочитаемый заголовок из слага: /news/2026-06-19/foo-bar/.123 -> "foo bar"
    private static func slugTitle(_ url: URL) -> String {
        let slug = url.pathComponents.last { !$0.hasPrefix(".") && $0 != "/" } ?? url.absoluteString
        return slug.replacingOccurrences(of: "-", with: " ")
    }

    // оборачиваем очищенное тело в минимальный документ с KonaBody,
    // чтобы reader-извлечение и стили работали и для сохранённой копии
    private static func wrap(_ body: String) -> String {
        "<!doctype html><html><head><meta charset=\"utf-8\"></head><body>\(body)</body></html>"
    }

    private var attribution: some View {
        HStack {
            Text("Source: Anime News Network")
            Spacer()
            Link("Open original", destination: url)
        }
        .font(.caption)
        .padding(8)
        .frame(maxWidth: .infinity)
        .glassEffect()
        .padding(8)
    }
}

/// шрифт читалки; популярные для чтения гарнитуры, доступные в macOS
enum ReaderFont: String, CaseIterable, Identifiable {
    case system, newYork, georgia, charter, iowan, palatino, helvetica, verdana

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .newYork: "New York"
        case .georgia: "Georgia"
        case .charter: "Charter"
        case .iowan: "Iowan Old Style"
        case .palatino: "Palatino"
        case .helvetica: "Helvetica"
        case .verdana: "Verdana"
        }
    }

    var cssStack: String {
        switch self {
        case .system: "-apple-system,system-ui,sans-serif"
        case .newYork: "ui-serif,'New York',Georgia,serif"
        case .georgia: "Georgia,serif"
        case .charter: "Charter,'Bitstream Charter',Georgia,serif"
        case .iowan: "'Iowan Old Style',Palatino,serif"
        case .palatino: "Palatino,'Palatino Linotype',serif"
        case .helvetica: "'Helvetica Neue',Helvetica,sans-serif"
        case .verdana: "Verdana,Geneva,sans-serif"
        }
    }
}

/// цветовая тема читалки
enum ReaderTheme: String, CaseIterable, Identifiable {
    case auto, light, sepia, dark

    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .auto: "Auto"
        case .light: "Light"
        case .sepia: "Sepia"
        case .dark: "Dark"
        }
    }
}

/// собранные настройки типографики, переводятся в CSS для страницы статьи
struct ReaderStyle: Equatable {
    let fontSize: Double
    let font: ReaderFont
    let theme: ReaderTheme
    let dyslexia: Bool

    // дислексик-режим: ясный рубленый шрифт и увеличенные интервалы помогают читать
    private var stack: String {
        dyslexia ? "'Comic Sans MS','Trebuchet MS',Verdana,sans-serif" : font.cssStack
    }

    private var spacing: String {
        dyslexia
            ? "letter-spacing:0.05em;word-spacing:0.18em;line-height:2;text-align:left;"
            : "line-height:1.6;"
    }

    func css() -> String {
        let body = "body{max-width:720px;margin:24px auto;padding:0 16px;"
            + "font-size:\(Int(fontSize))px;font-family:\(stack);\(spacing)\(colors)}"
        let common = "img{max-width:100%;height:auto;border-radius:8px;}a{color:\(linkColor);}"
        // auto - доводим до системной темы media query, остальные темы жёсткие
        let autoDark = theme == .auto
            ? "@media (prefers-color-scheme: dark){body{background:#1c1c1e;color:#e5e5e7;}a{color:#6ab0ff;}}"
            : ""
        return body + common + autoDark
    }

    private var colors: String {
        switch theme {
        case .auto, .light: "color:#1a1a1a;background:#fff;"
        case .sepia: "color:#5b4636;background:#f4ecd8;"
        case .dark: "color:#e5e5e7;background:#1c1c1e;"
        }
    }

    private var linkColor: String { theme == .dark ? "#6ab0ff" : "#0a66c2" }
}

/// заглушка-скелет на время загрузки статьи
private struct ReaderSkeleton: View {
    @State private var dim = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            block(height: 30).frame(maxWidth: 420)
            block(height: 220)
            ForEach(0..<7, id: \.self) { _ in block(height: 14) }
            block(height: 14).frame(maxWidth: 260)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: 760, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor))
        .opacity(dim ? 0.55 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
    }

    private func block(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.gray.opacity(0.25))
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// WKWebView, который не навязывает окну свой размер: иначе окно скачет под контент
private final class FixedWebView: WKWebView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

private struct ArticleWebView: NSViewRepresentable {
    let url: URL
    let offlineHTML: String?
    let readerMode: Bool
    let style: ReaderStyle
    let onReady: () -> Void
    let onHTML: (String) -> Void
    let onTitle: (String) -> Void
    let onError: (String) -> Void
    let onPush: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, readerMode: readerMode, style: style, onReady: onReady,
                    onHTML: onHTML, onTitle: onTitle, onError: onError, onPush: onPush)
    }

    func makeNSView(context: Context) -> WKWebView {
        let web = FixedWebView()
        web.navigationDelegate = context.coordinator
        let coord = context.coordinator
        // сохранённая офлайн-копия > свежий кэш (мгновенно) > сеть
        if let offlineHTML {
            coord.localHTML = offlineHTML
            web.loadHTMLString(offlineHTML, baseURL: url)
        } else if let cached = PageCache.shared.html(for: url) {
            coord.localHTML = cached
            web.loadHTMLString(cached, baseURL: url)
        } else {
            web.load(URLRequest(url: url))
        }
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let coord = context.coordinator
        let modeChanged = coord.readerMode != readerMode
        let styleChanged = coord.style != style
        coord.readerMode = readerMode
        coord.style = style

        if modeChanged {
            // локальный контент перезагружаем той же строкой: reload() у страницы
            // из loadHTMLString ушёл бы в сеть за baseURL и офлайн ломался бы
            if let html = coord.localHTML {
                web.loadHTMLString(html, baseURL: url)
            } else {
                web.reload()   // didFinish сам решит: чистить статью или показать целиком
            }
        } else if styleChanged && readerMode {
            web.evaluateJavaScript(Coordinator.styleJS(style))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let url: URL
        var localHTML: String?   // офлайн-копия или кэш: в PageCache повторно не кладём
        var readerMode: Bool
        var style: ReaderStyle
        let onReady: () -> Void
        let onHTML: (String) -> Void
        let onTitle: (String) -> Void
        let onError: (String) -> Void
        let onPush: (URL) -> Void

        init(url: URL, readerMode: Bool, style: ReaderStyle,
             onReady: @escaping () -> Void, onHTML: @escaping (String) -> Void,
             onTitle: @escaping (String) -> Void, onError: @escaping (String) -> Void,
             onPush: @escaping (URL) -> Void) {
            self.url = url
            self.readerMode = readerMode
            self.style = style
            self.onReady = onReady
            self.onHTML = onHTML
            self.onTitle = onTitle
            self.onError = onError
            self.onPush = onPush
        }

        // собирает очищенную копию статьи (текст, картинки, видео YouTube) и
        // возвращает её html; replace - ещё и заменить ею страницу. выкидывает
        // скрипты и рекламу, видео-iframes делает адаптивными 16:9, прочие
        // iframes удаляет, чистит пустые контейнеры, разворачивает lazy-картинки
        static func extractJS(_ style: ReaderStyle, replace: Bool) -> String {
            """
            (function(){
              var body = document.querySelector('.KonaBody');
              if(!body) return null;
              var clone = body.cloneNode(true);
              clone.querySelectorAll('script, ins, .ad, .ADSYSTEM, .related-link').forEach(function(e){e.remove();});
              clone.querySelectorAll('iframe').forEach(function(f){
                var src = f.getAttribute('src') || '';
                if(/youtube(-nocookie)?\\.com\\/embed/.test(src)){
                  f.removeAttribute('width'); f.removeAttribute('height');
                  f.style.cssText='display:block;width:100%;aspect-ratio:16/9;height:auto;border:0;border-radius:8px;';
                  var p=f.parentElement;
                  if(p){ p.style.cssText='position:static;width:100%;height:auto;padding:0;margin:16px 0;'; }
                } else { f.remove(); }
              });
              clone.querySelectorAll('div, aside, section, p').forEach(function(e){
                if(!e.querySelector('img, iframe') && !e.textContent.trim()){ e.remove(); }
              });
              clone.querySelectorAll('img[data-src]').forEach(function(img){img.src = img.getAttribute('data-src');});
              \(replace ? "document.body.innerHTML = clone.outerHTML;" : "")
              \(replace ? styleJS(style) : "")
              return clone.outerHTML;
            })();
            """
        }

        // обновляет только таблицу стилей, не трогая уже извлечённый текст
        static func styleJS(_ style: ReaderStyle) -> String {
            let css = style.css().replacingOccurrences(of: "'", with: "\\'")
            return """
            (function(){
              var s = document.getElementById('reader-style') || document.createElement('style');
              s.id = 'reader-style';
              s.textContent = '\(css)';
              document.head.appendChild(s);
            })();
            """
        }

        // клики по ссылкам ANN пушат новый экран читалки (навигация внутри webview
        // портила бы кэш и сохранение и не имела кнопки "назад"), остальные клики
        // уводим в браузер; для встроенного контента пропускаем только ANN и
        // видео-хосты (YouTube-плееру нужен их JS), прочие фреймы глушим молча
        // ponytail: JS контента включён - без него не играет встроенное видео;
        // защита держится на белом списке хостов и уводе внешних кликов в Safari
        private static let videoHosts = ["youtube.com", "youtube-nocookie.com", "ytimg.com",
                                         "googlevideo.com", "ggpht.com", "google.com"]

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     preferences: WKWebpagePreferences,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            let target = action.request.url
            guard let host = target?.host else {
                // наши loadHTMLString/about:/data: пропускаем, прочие схемы (javascript:, file:) режем
                let scheme = target?.scheme?.lowercased()
                let benign = scheme == nil || ["about", "data"].contains(scheme!)
                decisionHandler(benign ? .allow : .cancel, preferences)
                return
            }
            let isANN = host.hasSuffix("animenewsnetwork.com")
            if action.navigationType == .linkActivated {
                if isANN, let target {
                    onPush(target)
                } else if let target {
                    NSWorkspace.shared.open(target)
                }
                decisionHandler(.cancel, preferences)
            } else {
                let isVideo = Self.videoHosts.contains { host == $0 || host.hasSuffix("." + $0) }
                decisionHandler(isANN || isVideo ? .allow : .cancel, preferences)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // сырой html сетевой загрузки кладём в кэш для мгновенного повторного
            // открытия; локальный контент не перекладываем: повторная запись
            // обновляла бы mtime и продлевала 15-дневный ttl бесконечно
            if localHTML == nil {
                webView.evaluateJavaScript("document.documentElement.outerHTML") { [url] html, _ in
                    if let raw = html as? String { PageCache.shared.store(raw, for: url) }
                }
                webView.evaluateJavaScript("document.title") { [onTitle] t, _ in
                    if let t = t as? String { onTitle(t) }
                }
            }
            // очищенное тело отдаём наверх в обоих режимах - его сохраняем для офлайна
            webView.evaluateJavaScript(Coordinator.extractJS(style, replace: readerMode)) { [onReady, onHTML] cleaned, _ in
                onReady()
                if let cleaned = cleaned as? String { onHTML(cleaned) }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            report(error)
        }

        // -999 и WebKit 102 - последствия наших же .cancel-решений (внешние ссылки,
        // пуш статьи), а не сбой загрузки
        private func report(_ error: Error) {
            let e = error as NSError
            if e.code == NSURLErrorCancelled { return }
            if e.domain == "WebKitErrorDomain" && e.code == 102 { return }
            onError(e.localizedDescription)
        }
    }
}
