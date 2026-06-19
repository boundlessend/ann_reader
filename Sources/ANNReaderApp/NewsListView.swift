import SwiftUI
import ANNKit

struct NewsListView: View {
    let feed: URL
    let title: LocalizedStringKey
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let err = model.newsError {
                ContentUnavailableView("Could not load news", systemImage: "wifi.slash",
                                       description: Text(err))
            } else {
                ScrollView {
                    LazyVStack(spacing: 18) {
                        if model.loadingNews && model.news.isEmpty {
                            ForEach(0..<4, id: \.self) { _ in NewsCardSkeleton() }
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
                    .padding(20)
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
                .animation(.easeOut(duration: 0.25), value: model.news.map(\.id))
            }
        }
        .navigationTitle(title)
        .task(id: feed) { await model.loadNews(feed: feed) }
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.loadNews(feed: feed) } }
        }
    }
}

/// карточка новости с крупным превью и мягким подъёмом при наведении
private struct NewsCard: View {
    let item: NewsItem
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            preview
            Text(item.title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let date = item.published {
                Text(date, format: .dateTime.weekday(.wide).day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.separator.opacity(0.5)))
        .shadow(color: .black.opacity(hovering ? 0.16 : 0.06),
                radius: hovering ? 14 : 6, y: hovering ? 7 : 3)
        .scaleEffect(hovering ? 1.008 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hovering)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var preview: some View {
        if let img = item.imageURL {
            AsyncImage(url: img, transaction: Transaction(animation: .easeOut(duration: 0.3))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder(icon: "photo")
                default:
                    placeholder(icon: nil)
                }
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(radius: 4)
                    .padding(10)
                    .opacity(hovering ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: hovering)
            }
        }
    }

    private func placeholder(icon: String?) -> some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let icon { Image(systemName: icon).font(.largeTitle).foregroundStyle(.tertiary) }
            else { ProgressView() }
        }
    }
}

/// скелет карточки на время первой загрузки ленты
private struct NewsCardSkeleton: View {
    @State private var dim = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 12).fill(.quaternary).frame(height: 220)
            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(height: 20)
            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 160, height: 14)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
        .opacity(dim ? 0.5 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}
