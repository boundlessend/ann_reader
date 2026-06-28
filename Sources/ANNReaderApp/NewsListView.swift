import SwiftUI
import ANNKit

/// лента категории: карточки статей в адаптивном гриде, число колонок растёт
/// с шириной окна с плавной анимацией
struct NewsListView: View {
    let feed: URL
    let title: LocalizedStringKey
    @Environment(AppModel.self) private var model

    private let spacing: CGFloat = 16
    private let pad: CGFloat = 20
    private let target: CGFloat = 226   // желаемая ширина ячейки с учётом spacing

    // число колонок от ширины: считаем сами, чтобы плавно анимировать появление
    // новой колонки при расширении окна (адаптивный GridItem перестраивается рывком)
    private func columnCount(for width: CGFloat) -> Int {
        max(1, Int((width - 2 * pad + spacing) / target))
    }

    var body: some View {
        Group {
            if let err = model.newsError {
                ContentUnavailableView("Could not load news", systemImage: "wifi.slash",
                                       description: Text(err))
            } else {
                GeometryReader { geo in
                    let count = columnCount(for: geo.size.width)
                    let columns = Array(repeating: GridItem(.flexible(maximum: 280), spacing: spacing),
                                        count: count)
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: spacing) {
                            if model.loadingNews && model.news.isEmpty {
                                ForEach(0..<9, id: \.self) { _ in NewsCardSkeleton() }
                            } else {
                                ForEach(model.news) { item in
                                    NavigationLink {
                                        ReaderView(url: item.link, title: item.title, offlineHTML: nil)
                                    } label: {
                                        NewsCard(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(pad)
                        .animation(.smooth(duration: 0.3), value: count)
                        .animation(.easeOut(duration: 0.25), value: model.news.map(\.id))
                    }
                }
            }
        }
        .navigationTitle(title)
        .task(id: feed) { await model.loadNews(feed: feed) }
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.loadNews(feed: feed) } }
        }
    }
}

/// карточка новости: превью 16:9 (родное соотношение - без обрезки) и текст под ним
private struct NewsCard: View {
    let item: NewsItem
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview
            Text(item.title)
                .font(.headline)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let date = item.published {
                Text(date, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator.opacity(0.5)))
        .shadow(color: .black.opacity(hovering ? 0.16 : 0.05),
                radius: hovering ? 12 : 5, y: hovering ? 6 : 2)
        .scaleEffect(hovering ? 1.012 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hovering)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var preview: some View {
        if let img = item.imageURL {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay { CachedThumbnail(url: img) }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(radius: 4)
                        .padding(8)
                        .opacity(hovering ? 1 : 0)
                        .animation(.easeOut(duration: 0.2), value: hovering)
                }
                .accessibilityHidden(true)   // превью декоративно, заголовок карточки озвучивается
        }
    }
}

/// превью из дискового кэша на 15 дней (ImageCache), с плавным появлением
private struct CachedThumbnail: View {
    let url: URL
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else if failed {
                Rectangle().fill(.quaternary)
                    .overlay { Image(systemName: "photo").font(.title).foregroundStyle(.tertiary) }
            } else {
                Rectangle().fill(.quaternary).overlay { ProgressView().controlSize(.small) }
            }
        }
        .task(id: url) {
            failed = false
            image = nil
            if let data = await ImageCache.shared.data(for: url), let img = NSImage(data: data) {
                withAnimation(.easeOut(duration: 0.25)) { image = img }
            } else {
                failed = true
            }
        }
    }
}

/// скелет карточки на время первой загрузки ленты
private struct NewsCardSkeleton: View {
    @State private var dim = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay { RoundedRectangle(cornerRadius: 10).fill(.quaternary) }
            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(height: 16)
            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 120, height: 12)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .opacity(dim ? 0.5 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}
