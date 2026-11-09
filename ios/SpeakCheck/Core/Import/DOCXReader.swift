import Compression
import Foundation

/// Минимальный безопасный читатель DOCX: ZIP central directory → word/document.xml → текст.
/// Защита: лимит распакованного размера и коэффициента сжатия (zip-bomb), без внешних зависимостей.
enum DOCXReader {
    static let maxUncompressed = 30 * 1024 * 1024
    static let maxRatio = 200

    static func text(from data: Data) throws -> String {
        let xml = try ZipArchive(data: data).extract(path: "word/document.xml",
                                                     maxSize: maxUncompressed, maxRatio: maxRatio)
        let parser = DocumentXMLText(data: xml)
        return try parser.parse()
    }
}

struct ZipArchive {
    struct Entry {
        var name: String
        var method: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
    }

    let bytes: [UInt8]
    let entries: [Entry]

    init(data: Data) throws {
        bytes = [UInt8](data)
        entries = try Self.readCentralDirectory(bytes)
    }

    func extract(path: String, maxSize: Int, maxRatio: Int) throws -> Data {
        guard let entry = entries.first(where: { $0.name == path }) else { throw ImportError.unreadable }
        guard entry.uncompressedSize <= maxSize,
              entry.compressedSize > 0,
              entry.uncompressedSize / max(entry.compressedSize, 1) <= maxRatio else {
            throw ImportError.tooLarge
        }
        let h = entry.localHeaderOffset
        guard h + 30 <= bytes.count, u32(h) == 0x0403_4B50 else { throw ImportError.unreadable }
        let nameLen = Int(u16(h + 26)), extraLen = Int(u16(h + 28))
        let start = h + 30 + nameLen + extraLen
        let end = start + entry.compressedSize
        guard end <= bytes.count else { throw ImportError.unreadable }
        let payload = Array(bytes[start..<end])

        switch entry.method {
        case 0:
            return Data(payload)
        case 8:
            return try inflate(payload, expected: entry.uncompressedSize)
        default:
            throw ImportError.unsupported
        }
    }

    /// Raw DEFLATE через Apple Compression (COMPRESSION_ZLIB = raw deflate без заголовка).
    private func inflate(_ input: [UInt8], expected: Int) throws -> Data {
        let capacity = expected + 64
        var output = [UInt8](repeating: 0, count: capacity)
        let written = input.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(dst.baseAddress!, capacity, src.baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0, written <= expected else { throw ImportError.unreadable }
        return Data(output.prefix(written))
    }

    private static func readCentralDirectory(_ b: [UInt8]) throws -> [Entry] {
        // End of central directory: сигнатура 0x06054b50 в последних 64 КБ.
        guard b.count >= 22 else { throw ImportError.unreadable }
        var eocd = -1
        var i = b.count - 22
        let lower = max(0, b.count - 65_557)
        while i >= lower {
            if b[i] == 0x50, b[i + 1] == 0x4B, b[i + 2] == 0x05, b[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ImportError.unreadable }
        let count = Int(le16(b, eocd + 10))
        var offset = Int(le32(b, eocd + 16))
        guard count < 5_000 else { throw ImportError.unreadable }

        var entries: [Entry] = []
        for _ in 0..<count {
            guard offset + 46 <= b.count, le32(b, offset) == 0x0201_4B50 else { throw ImportError.unreadable }
            let method = le16(b, offset + 10)
            let compressed = Int(le32(b, offset + 20))
            let uncompressed = Int(le32(b, offset + 24))
            let nameLen = Int(le16(b, offset + 28))
            let extraLen = Int(le16(b, offset + 30))
            let commentLen = Int(le16(b, offset + 32))
            let local = Int(le32(b, offset + 42))
            guard offset + 46 + nameLen <= b.count else { throw ImportError.unreadable }
            let name = String(decoding: b[(offset + 46)..<(offset + 46 + nameLen)], as: UTF8.self)
            entries.append(Entry(name: name, method: method, compressedSize: compressed,
                                 uncompressedSize: uncompressed, localHeaderOffset: local))
            offset += 46 + nameLen + extraLen + commentLen
        }
        return entries
    }

    private func u16(_ o: Int) -> UInt16 { Self.le16(bytes, o) }
    private func u32(_ o: Int) -> UInt32 { Self.le32(bytes, o) }
    private static func le16(_ b: [UInt8], _ o: Int) -> UInt16 { UInt16(b[o]) | UInt16(b[o + 1]) << 8 }
    private static func le32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
}

/// Достаёт текст из WordprocessingML: <w:t>, <w:tab/>, <w:br/>, конец абзаца </w:p>.
final class DocumentXMLText: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var output = ""
    private var inText = false

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
        parser.shouldResolveExternalEntities = false // XXE-защита
    }

    func parse() throws -> String {
        guard parser.parse() else { throw ImportError.unreadable }
        return output
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "w:t": inText = true
        case "w:tab": output += " "
        case "w:br", "w:cr": output += "\n"
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "w:t": inText = false
        case "w:p": output += "\n\n"
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { output += string }
    }
}
