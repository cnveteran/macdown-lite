import Foundation

/// Minimal ZIP writer producing a **stored** (uncompressed) archive.
///
/// Word's `.docx` is just a ZIP container, and the parts we put in it are XML
/// (tiny) plus images that are already compressed, so deflate would buy us
/// almost nothing. Storing avoids a compression dependency entirely — the only
/// thing that must be exactly right is the CRC-32 and the record layout.
struct ZipWriter {

    private struct Entry {
        let name: [UInt8]
        let data: Data
        let crc: UInt32
        let offset: UInt32
    }

    private var entries: [Entry] = []
    private var payload = Data()

    /// Adds a file. `name` uses forward slashes, e.g. `word/document.xml`.
    mutating func add(_ name: String, _ data: Data) {
        let nameBytes = Array(name.utf8)
        let crc = ZipWriter.crc32(data)
        let offset = UInt32(payload.count)
        payload.append(ZipWriter.localHeader(nameBytes, crc: crc, size: UInt32(data.count)))
        payload.append(data)
        entries.append(Entry(name: nameBytes, data: data, crc: crc, offset: offset))
    }

    mutating func add(_ name: String, _ text: String) {
        add(name, Data(text.utf8))
    }

    func archive() -> Data {
        var out = payload
        let centralStart = UInt32(out.count)

        for e in entries {
            out.append(ZipWriter.centralHeader(e.name, crc: e.crc,
                                               size: UInt32(e.data.count), offset: e.offset))
        }

        let centralSize = UInt32(out.count) - centralStart
        out.append(ZipWriter.endOfCentralDirectory(count: UInt16(entries.count),
                                                   size: centralSize,
                                                   offset: centralStart))
        return out
    }

    // MARK: - Records

    private static func localHeader(_ name: [UInt8], crc: UInt32, size: UInt32) -> Data {
        var d = Data()
        d.append(uint32: 0x0403_4b50)      // local file header signature
        d.append(uint16: 20)               // version needed
        d.append(uint16: 0x0800)           // flags: UTF-8 names
        d.append(uint16: 0)                // method: stored
        d.append(uint16: dosTime())
        d.append(uint16: dosDate())
        d.append(uint32: crc)
        d.append(uint32: size)             // compressed size
        d.append(uint32: size)             // uncompressed size
        d.append(uint16: UInt16(name.count))
        d.append(uint16: 0)                // extra length
        d.append(contentsOf: name)
        return d
    }

    private static func centralHeader(_ name: [UInt8], crc: UInt32,
                                      size: UInt32, offset: UInt32) -> Data {
        var d = Data()
        d.append(uint32: 0x0201_4b50)      // central directory signature
        d.append(uint16: 20)               // version made by
        d.append(uint16: 20)               // version needed
        d.append(uint16: 0x0800)           // flags: UTF-8 names
        d.append(uint16: 0)                // method: stored
        d.append(uint16: dosTime())
        d.append(uint16: dosDate())
        d.append(uint32: crc)
        d.append(uint32: size)
        d.append(uint32: size)
        d.append(uint16: UInt16(name.count))
        d.append(uint16: 0)                // extra
        d.append(uint16: 0)                // comment
        d.append(uint16: 0)                // disk number start
        d.append(uint16: 0)                // internal attributes
        d.append(uint32: 0)                // external attributes
        d.append(uint32: offset)
        d.append(contentsOf: name)
        return d
    }

    private static func endOfCentralDirectory(count: UInt16, size: UInt32,
                                              offset: UInt32) -> Data {
        var d = Data()
        d.append(uint32: 0x0605_4b50)
        d.append(uint16: 0)                // this disk
        d.append(uint16: 0)                // disk with central directory
        d.append(uint16: count)
        d.append(uint16: count)
        d.append(uint32: size)
        d.append(uint32: offset)
        d.append(uint16: 0)                // comment length
        return d
    }

    private static func dosTime() -> UInt16 {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
        return UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | ((c.second ?? 0) / 2))
    }

    private static func dosDate() -> UInt16 {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        // MS-DOS dates store "years since 1980" in 7 bits; clamp into range so
        // the shift can never overflow UInt16.
        let yearsSince1980 = min(127, max(0, (c.year ?? 1980) - 1980))
        let month = min(12, max(1, c.month ?? 1))
        let day = min(31, max(1, c.day ?? 1))
        return UInt16(yearsSince1980 << 9 | month << 5 | day)
    }

    // MARK: - CRC-32

    private static let crcTable: [UInt32] = {
        (0...255).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append(uint16 v: UInt16) {
        append(UInt8(v & 0xFF)); append(UInt8((v >> 8) & 0xFF))
    }
    mutating func append(uint32 v: UInt32) {
        append(UInt8(v & 0xFF)); append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF)); append(UInt8((v >> 24) & 0xFF))
    }
}
