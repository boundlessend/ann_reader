import Foundation

/// тип тайтла в энциклопедии ANN
public enum TitleKind: String, Sendable {
    case anime
    case manga
}

/// роль в озвучке: персонаж и актёр
public struct CastEntry: Sendable, Identifiable {
    public let id: String
    public let role: String
    public let personName: String
}

/// производственная роль: задача и человек
public struct StaffEntry: Sendable, Identifiable {
    public let id: String
    public let task: String
    public let personName: String
}

/// один тайтл с деталями из api.xml
public struct EncTitle: Sendable, Identifiable {
    public let id: String
    public let kind: TitleKind
    public let name: String
    public let titleType: String
    public let pictureURL: URL?
    public let info: [String: [String]]
    public let cast: [CastEntry]
    public let staff: [StaffEntry]
}

/// новостная запись из списка статей ANN с превью-картинкой
public struct NewsItem: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let link: URL
    public let published: Date?
    public let imageURL: URL?
}
