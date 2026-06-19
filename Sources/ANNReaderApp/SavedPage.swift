import Foundation
import SwiftData

/// сохранённая страница: любая статья или ссылка, открывается в читалке
@Model
final class SavedPage {
    @Attribute(.unique) var urlString: String
    var title: String
    var savedAt: Date
    // самодостаточный html статьи с встроенными картинками: открывается без сети
    var offlineHTML: String?

    init(urlString: String, title: String, savedAt: Date, offlineHTML: String?) {
        self.urlString = urlString
        self.title = title
        self.savedAt = savedAt
        self.offlineHTML = offlineHTML
    }

    var url: URL? { URL(string: urlString) }
}
