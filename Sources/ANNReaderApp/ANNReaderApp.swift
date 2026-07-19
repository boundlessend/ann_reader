import SwiftUI
import SwiftData

@main
struct ANNReaderApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        .modelContainer(for: [Favorite.self, SavedPage.self])

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
