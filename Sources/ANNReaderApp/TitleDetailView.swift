import SwiftUI
import SwiftData
import ANNKit

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
                    header(t)
                    infoSection(t)
                    peopleSection("Cast", t.cast.map { "\($0.role): \($0.personName)" })
                    peopleSection("Staff", t.staff.map { "\($0.task): \($0.personName)" })
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

    private func header(_ t: EncTitle) -> some View {
        HStack(alignment: .top, spacing: 16) {
            if let pic = t.pictureURL {
                AsyncImage(url: pic) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                    .frame(width: 160, height: 180)
                    .clipShape(.rect(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(t.name).font(.title.bold())
                Text(t.titleType).foregroundStyle(.secondary)
            }
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
