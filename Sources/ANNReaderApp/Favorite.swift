import Foundation
import SwiftData
import ANNKit

/// закладка тайтла; детали тянутся по id из API или кэша при открытии
@Model
final class Favorite {
    @Attribute(.unique) var id: String
    var kindRaw: String
    var name: String
    var addedAt: Date

    init(id: String, kindRaw: String, name: String, addedAt: Date) {
        self.id = id
        self.kindRaw = kindRaw
        self.name = name
        self.addedAt = addedAt
    }

    var kind: TitleKind { TitleKind(rawValue: kindRaw) ?? .anime }
}
