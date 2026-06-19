import SwiftUI
import SwiftData

struct SavedPagesView: View {
    @Query(sort: \SavedPage.savedAt, order: .reverse) private var pages: [SavedPage]
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            if pages.isEmpty {
                ContentUnavailableView("No saved pages", systemImage: "bookmark",
                                       description: Text("Save articles with the bookmark button"))
            } else {
                List {
                    ForEach(pages) { page in
                        if let url = page.url {
                            NavigationLink {
                                ReaderView(url: url, title: page.title, offlineHTML: page.offlineHTML)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(page.title).font(.headline)
                                    Text(page.savedAt, format: .dateTime.day().month().year())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { idx in idx.map { pages[$0] }.forEach(context.delete) }
                }
            }
        }
        .navigationTitle("Saved")
    }
}
