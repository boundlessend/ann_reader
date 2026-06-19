import SwiftUI

private let feedBase = "https://www.animenewsnetwork.com/"

// раздел приложения; rawValue - стабильный id, заголовок локализуется отдельно
enum Tab: String, CaseIterable, Identifiable {
    case all, news, interest, reviews, features, columns
    case anime, manga, favorites, saved

    var id: String { rawValue }

    // категории-ленты в группе «Read»
    static let feeds: [Tab] = [.all, .news, .interest, .reviews, .features, .columns]

    // html-листинг категории: содержит превью-картинки (в отличие от rss-фида)
    var feedURL: URL? {
        switch self {
        case .all: URL(string: feedBase + "all/")
        case .news: URL(string: feedBase + "news/")
        case .interest: URL(string: feedBase + "interest/")
        case .reviews: URL(string: feedBase + "review/")
        case .features: URL(string: feedBase + "feature/")
        case .columns: URL(string: feedBase + "column/")
        default: nil
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .news: "News"
        case .interest: "Interest"
        case .reviews: "Reviews"
        case .features: "Features"
        case .columns: "Columns"
        case .anime: "Anime"
        case .manga: "Manga"
        case .favorites: "Favorites"
        case .saved: "Saved"
        }
    }

    var icon: String {
        switch self {
        case .all: "tray.full"
        case .news: "newspaper"
        case .interest: "sparkles"
        case .reviews: "star.bubble"
        case .features: "doc.richtext"
        case .columns: "text.justify.left"
        case .anime: "tv"
        case .manga: "book"
        case .favorites: "star"
        case .saved: "bookmark"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .all

    var body: some View {
        NavigationSplitView {
            List(selection: $tab) {
                Section("Read") {
                    ForEach(Tab.feeds) { t in Label(t.title, systemImage: t.icon).tag(t) }
                }
                Section("Encyclopedia") {
                    Label(Tab.anime.title, systemImage: Tab.anime.icon).tag(Tab.anime)
                    Label(Tab.manga.title, systemImage: Tab.manga.icon).tag(Tab.manga)
                }
                Label(Tab.favorites.title, systemImage: Tab.favorites.icon).tag(Tab.favorites)
                Label(Tab.saved.title, systemImage: Tab.saved.icon).tag(Tab.saved)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            VStack(spacing: 0) {
                if model.isOffline { offlineBanner }
                // явный стек на раздел: неявная навигация detail-колонки
                // рассинхронизируется после возврата из внешнего браузера
                NavigationStack {
                    sectionView
                }
                .id(tab)
            }
        }
    }

    @ViewBuilder
    private var sectionView: some View {
        switch tab {
        case .anime: CatalogView(kind: .anime)
        case .manga: CatalogView(kind: .manga)
        case .favorites: FavoritesView()
        case .saved: SavedPagesView()
        default:
            if let url = tab.feedURL { NewsListView(feed: url, title: tab.title) }
        }
    }

    private var offlineBanner: some View {
        Label("Offline - showing cached data", systemImage: "wifi.slash")
            .font(.callout)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.orange.opacity(0.25))
    }
}
