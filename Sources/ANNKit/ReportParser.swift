import Foundation

/// краткая запись каталога из reports.xml для списка (без деталей)
public struct CatalogItem: Sendable, Identifiable {
    public let id: String
    public let kind: TitleKind
    public let name: String
    public let type: String      // TV, movie, ONA...
    public let vintage: String?  // дата/период выхода, может отсутствовать
}

/// парсер reports.xml в список CatalogItem
final class ReportParser: NSObject, XMLParserDelegate {
    private let kind: TitleKind
    private var items: [CatalogItem] = []
    private var inItem = false
    private var id = ""
    private var type = ""
    private var name = ""
    private var vintage = ""
    private var text = ""

    init(kind: TitleKind) {
        self.kind = kind
        super.init()
    }

    func parse(_ data: Data) throws -> [CatalogItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw ANNError.parseFailure(parser.parserError?.localizedDescription ?? "report parse failed")
        }
        return items
    }

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        text = ""
        if name == "item" {
            inItem = true
            id = ""; type = ""; self.name = ""; vintage = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String,
                namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard inItem else { return }
        switch name {
        case "id": id = value
        case "type": type = value
        case "name": self.name = value
        case "vintage": vintage = value
        case "item":
            inItem = false
            items.append(CatalogItem(id: id, kind: kind, name: self.name, type: type,
                                     vintage: vintage.isEmpty ? nil : vintage))
        default:
            break
        }
        text = ""
    }
}
