import SwiftUI
import SwiftData

struct FavoritesView: View {
    @Query(sort: \Favorite.addedAt, order: .reverse) private var favorites: [Favorite]
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            if favorites.isEmpty {
                ContentUnavailableView("No favorites", systemImage: "star",
                                       description: Text("Add titles with the star button"))
            } else {
                List {
                    ForEach(favorites) { fav in
                        NavigationLink(value: Route.title(kind: fav.kind, id: fav.id, name: fav.name)) {
                            VStack(alignment: .leading) {
                                Text(fav.name).font(.headline)
                                Text(fav.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { idx in idx.map { favorites[$0] }.forEach(context.delete) }
                }
            }
        }
        .navigationTitle("Favorites")
    }
}
