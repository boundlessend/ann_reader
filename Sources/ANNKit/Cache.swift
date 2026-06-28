import Foundation
import CryptoKit

// общий слой дискового кэша для ANNKit и приложения: один способ строить ключ,
// проверять свежесть и выметать протухшее, без копипасты в каждом кэше

/// путь файла кэша со стабильным ключом: SHA256 от url (hashValue у String
/// рандомизируется между запусками, и кэш бы не переживал перезапуск)
public func cacheFilePath(dir: URL, url: URL, ext: String) -> URL {
    let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
    let key = digest.map { String(format: "%02x", $0) }.joined()
    return dir.appendingPathComponent("\(key).\(ext)")
}

/// файл существует и моложе ttl
public func cacheIsFresh(_ path: URL, ttl: TimeInterval) -> Bool {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
          let mtime = attrs[.modificationDate] as? Date else { return false }
    return Date().timeIntervalSince(mtime) < ttl
}

/// удаляет из dir файлы старше ttl
public func cacheSweep(dir: URL, ttl: TimeInterval) {
    let cutoff = Date().addingTimeInterval(-ttl)
    let files = (try? FileManager.default.contentsOfDirectory(at: dir,
                 includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    for file in files {
        let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let mtime, mtime < cutoff { try? FileManager.default.removeItem(at: file) }
    }
}
