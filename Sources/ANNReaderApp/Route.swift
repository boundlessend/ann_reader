import SwiftUI
import ANNKit

/// назначение перехода в стеке раздела; value-based, чтобы path переживал
/// переключение вкладок и позволял программный пуш из читалки
enum Route: Hashable {
    /// статья в читалке; offline - открыть сохранённую копию из SwiftData
    case article(url: URL, title: String, offline: Bool)
    /// карточка тайтла энциклопедии
    case title(kind: TitleKind, id: String, name: String)
}

extension EnvironmentValues {
    /// пуш маршрута в стек текущего раздела: нужен читалке, где переход
    /// инициирует webview-колбэк, а не NavigationLink
    @Entry var pushRoute: (Route) -> Void = { _ in }
}

/// общий резолвер маршрутов: вешается на корень каждого NavigationStack
struct RouteDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { route in
            switch route {
            case let .article(url, title, offline):
                ReaderView(url: url, title: title, offline: offline)
            case let .title(kind, id, name):
                TitleDetailView(kind: kind, id: id, name: name)
            }
        }
    }
}
