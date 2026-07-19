import SwiftUI
import ANNKit

private let letters = (65...90).map { String(UnicodeScalar($0)!) }  // A..Z

/// каталог энциклопедии (аниме или манга): поиск по названию, фильтр по первой
/// букве и подгрузка следующих страниц
struct CatalogView: View {
    let kind: TitleKind
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            searchField($model.catalogQuery)
            letterBar
            content
        }
        .navigationTitle(kind == .anime ? "Anime" : "Manga")
        .task(id: kind) {
            // task перезапускается и при возврате из карточки тайтла: если каталог
            // этого раздела уже загружен, не сбрасываем поиск и позицию
            if model.catalogKind == kind, !model.catalog.isEmpty { return }
            model.catalogQuery = ""
            await model.loadCatalog(kind: kind, name: "A")
        }
    }

    private func searchField(_ query: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(kind == .anime ? "Search anime" : "Search manga", text: query)
                .textFieldStyle(.plain)
                .onSubmit { Task { await model.searchCatalog(kind: kind) } }
            if !query.wrappedValue.isEmpty {
                Button {
                    query.wrappedValue = ""
                    Task { await model.loadCatalog(kind: kind, name: "A") }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .glassEffect(in: .rect(cornerRadius: 12))
        .padding([.horizontal, .top], 8)
    }

    private var letterBar: some View {
        GlassEffectContainer {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(letters, id: \.self) { l in
                        Button(l) {
                            model.catalogQuery = ""
                            Task { await model.loadCatalog(kind: kind, name: l) }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(isActive(l) ? Color.accentColor.opacity(0.3) : .clear, in: .capsule)
                    }
                }
                .padding(8)
            }
            .glassEffect(in: .rect(cornerRadius: 16))
        }
        .padding(8)
    }

    private func isActive(_ letter: String) -> Bool {
        model.catalogQuery.isEmpty && model.catalogName == letter
    }

    @ViewBuilder
    private var content: some View {
        if let err = model.catalogError {
            ContentUnavailableView("Catalog error", systemImage: "exclamationmark.triangle", description: Text(err))
        } else {
            List {
                ForEach(model.catalog) { item in
                    NavigationLink(value: Route.title(kind: item.kind, id: item.id, name: item.name)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.headline)
                            HStack(spacing: 8) {
                                Text(item.type).foregroundStyle(.secondary)
                                if let v = item.vintage { Text(v).foregroundStyle(.tertiary) }
                            }
                            .font(.caption)
                        }
                    }
                }
                if !model.catalog.isEmpty, !model.catalogExhausted {
                    Button("Load more") { Task { await model.loadMoreCatalog() } }
                        .frame(maxWidth: .infinity)
                }
            }
            .overlay {
                if model.loadingCatalog && model.catalog.isEmpty { ProgressView() }
                else if model.catalog.isEmpty { ContentUnavailableView.search }
            }
        }
    }
}
