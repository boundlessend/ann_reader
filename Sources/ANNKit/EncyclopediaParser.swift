import Foundation

/// парсер ответа api.xml энциклопедии ANN в EncTitle
final class EncyclopediaParser: NSObject, XMLParserDelegate {
    private var titles: [EncTitle] = []

    // состояние текущего тайтла
    private var curKind: TitleKind?
    private var curID = ""
    private var curName = ""
    private var curType = ""
    private var curPicture: URL?
    private var curInfo: [String: [String]] = [:]
    private var curCast: [CastEntry] = []
    private var curStaff: [StaffEntry] = []

    // состояние внутри cast/staff
    private var inCast = false
    private var inStaff = false
    private var pendingRole = ""
    private var pendingTask = ""

    // буфер текста и тип текущего info
    private var text = ""
    private var curInfoType = ""
    private var entryCounter = 0

    func parse(_ data: Data) throws -> [EncTitle] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw ANNError.parseFailure(parser.parserError?.localizedDescription ?? "xml parse failed")
        }
        return titles
    }

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?, attributes attr: [String: String]) {
        text = ""
        switch name {
        case "anime", "manga":
            curKind = name == "anime" ? .anime : .manga
            curID = attr["id"] ?? ""
            curName = attr["name"] ?? ""
            curType = attr["type"] ?? ""
            curPicture = nil
            curInfo = [:]
            curCast = []
            curStaff = []
        case "info":
            curInfoType = attr["type"] ?? ""
            if curInfoType == "Picture", let src = attr["src"] { curPicture = URL(string: src) }
        case "cast":
            inCast = true
            pendingRole = ""
        case "staff":
            inStaff = true
            pendingTask = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String,
                namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "info":
            if curInfoType != "Picture", !value.isEmpty {
                curInfo[curInfoType, default: []].append(value)
            }
        case "role":
            pendingRole = value
        case "task":
            pendingTask = value
        case "person":
            entryCounter += 1
            if inCast {
                curCast.append(CastEntry(id: "\(curID)-c\(entryCounter)", role: pendingRole, personName: value))
            } else if inStaff {
                curStaff.append(StaffEntry(id: "\(curID)-s\(entryCounter)", task: pendingTask, personName: value))
            }
        case "cast":
            inCast = false
        case "staff":
            inStaff = false
        case "anime", "manga":
            guard let kind = curKind else { return }
            titles.append(EncTitle(id: curID, kind: kind, name: curName, titleType: curType,
                                   pictureURL: curPicture, info: curInfo, cast: curCast, staff: curStaff))
            curKind = nil
        default:
            break
        }
        text = ""
    }
}
