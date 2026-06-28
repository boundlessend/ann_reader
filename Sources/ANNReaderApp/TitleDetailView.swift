import SwiftUI
import SwiftData
import ANNKit

/// детальная страница тайтла: постер слева, вся информация (тип, поля, озвучка,
/// команда) справа; добавление в избранное из тулбара
struct TitleDetailView: View {
    let kind: TitleKind
    let id: String
    let name: String

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query private var favorites: [Favorite]

    @State private var title: EncTitle?
    @State private var error: String?

    private var encURL: URL {
        URL(string: "https://www.animenewsnetwork.com/encyclopedia/\(kind.rawValue).php?id=\(id)")!
    }
    private var isFavorite: Bool { favorites.contains { $0.id == id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let t = title {
                    // среднее превью слева, вся информация справа
                    HStack(alignment: .top, spacing: 24) {
                        poster(t)
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(t.name).font(.largeTitle.bold())
                                Text(t.titleType).font(.title3).foregroundStyle(.secondary)
                            }
                            infoSection(t)
                            peopleSection("Cast", t.cast.map { "\($0.role): \($0.personName)" })
                            peopleSection("Staff", t.staff.map { "\($0.task): \($0.personName)" })
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if let error {
                    ContentUnavailableView("Could not load", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
                attribution
            }
            .padding()
        }
        .navigationTitle(name)
        .toolbar {
            Button(isFavorite ? "In favorites" : "Add to favorites",
                   systemImage: isFavorite ? "star.fill" : "star") { toggleFavorite() }
        }
        .task(id: id) { await load() }
    }

    // среднее постер-превью слева; портретные постеры ANN масштабируем по ширине
    @ViewBuilder
    private func poster(_ t: EncTitle) -> some View {
        if let pic = t.pictureURL {
            AsyncImage(url: pic) { $0.resizable().scaledToFit() } placeholder: {
                RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                    .frame(height: 320).overlay { ProgressView() }
            }
            .frame(width: 240)
            .clipShape(.rect(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .accessibilityLabel(t.name)
        } else {
            RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                .frame(width: 240, height: 320)
                .overlay {
                    Image(systemName: kind == .anime ? "tv" : "book")
                        .font(.largeTitle).foregroundStyle(.tertiary)
                }
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func infoSection(_ t: EncTitle) -> some View {
        ForEach(t.info.keys.sorted(), id: \.self) { key in
            VStack(alignment: .leading, spacing: 2) {
                Text(key).font(.headline)
                Text(t.info[key]!.joined(separator: ", ")).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func peopleSection(_ label: LocalizedStringKey, _ rows: [String]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.headline)
                ForEach(rows, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
            }
        }
    }

    private var attribution: some View {
        HStack {
            Text("Data: Anime News Network")
            Spacer()
            Link("Open in ANN encyclopedia", destination: encURL)
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity)
        .glassEffect()
    }

    private func load() async {
        do { title = try await model.title(kind: kind, id: id) }
        catch { self.error = model.friendly(error) }
    }

    private func toggleFavorite() {
        if let existing = favorites.first(where: { $0.id == id }) {
            context.delete(existing)
        } else {
            context.insert(Favorite(id: id, kindRaw: kind.rawValue, name: name, addedAt: Date()))
        }
    }
}
