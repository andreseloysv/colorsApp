// ZIP mínimo sin dependencias (PKZIP 2.0): entradas "deflate" (RFC 1951 crudo
// vía Compression, que es lo que espera el método 8) o "stored" como respaldo,
// CRC-32, cabeceras locales, directorio central y EOCD. "Exportar diagnóstico"
// (Ajustes) produce con esto un .zip que ShareLink/AirDrop entregan tal cual.
// El lector lo usan los tests y la verificación del zip recién escrito.
import Foundation
import Compression

struct ZipEntry: Equatable, Sendable {
    let name: String
    let data: Data

    init(name: String, data: Data) {
        self.name = name
        self.data = data
    }

    init(name: String, text: String) {
        self.init(name: name, data: Data(text.utf8))
    }

    var text: String { String(decoding: data, as: UTF8.self) }
}

enum ZipError: Error, Equatable, Sendable {
    case notAZip
    case truncated
    case unsupportedMethod(UInt16)
    case badCRC(String)
    case badDeflate(String)
}

enum Zip {
    static let methodStored: UInt16 = 0
    static let methodDeflate: UInt16 = 8
    private static let localSignature: UInt32 = 0x0403_4B50
    private static let centralSignature: UInt32 = 0x0201_4B50
    private static let eocdSignature: UInt32 = 0x0605_4B50
    /// Bit 11 de las flags: nombres en UTF-8.
    private static let utf8Flag: UInt16 = 0x0800

    // MARK: CRC-32 (polinomio reflejado 0xEDB88320, el de PKZIP)

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in data {
            c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFF_FFFF
    }

    // MARK: Deflate (COMPRESSION_ZLIB de Compression = DEFLATE crudo sin cabecera zlib)

    /// nil si no comprime (vacío, o el resultado no es más corto): se guarda "stored".
    static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacity = data.count
        var out = [UInt8](repeating: 0, count: capacity)
        let n = data.withUnsafeBytes { src -> Int in
            guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return out.withUnsafeMutableBufferPointer { dst -> Int in
                guard let dstBase = dst.baseAddress else { return 0 }
                return compression_encode_buffer(dstBase, capacity, srcBase, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0, n < data.count else { return nil }
        return Data(out.prefix(n))
    }

    static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        guard !data.isEmpty else { return nil }
        var out = [UInt8](repeating: 0, count: expectedSize)
        let n = data.withUnsafeBytes { src -> Int in
            guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return out.withUnsafeMutableBufferPointer { dst -> Int in
                guard let dstBase = dst.baseAddress else { return 0 }
                return compression_decode_buffer(dstBase, expectedSize, srcBase, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n == expectedSize else { return nil }
        return Data(out)
    }

    // MARK: Escritura

    /// Archivo ZIP con las entradas en el orden dado (fecha DOS de `date`).
    static func archive(_ entries: [ZipEntry], date: Date = Date(), compress: Bool = true) -> Data {
        var out = Data()
        var central = Data()
        let (dosTime, dosDate) = dosDateTime(date)
        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let compressed = compress ? deflate(entry.data) : nil
            let method = compressed == nil ? methodStored : methodDeflate
            let payload = compressed ?? entry.data
            let offset = UInt32(out.count)

            out.append(le32(localSignature))
            out.append(le16(20))
            out.append(le16(utf8Flag))
            out.append(le16(method))
            out.append(le16(dosTime))
            out.append(le16(dosDate))
            out.append(le32(crc))
            out.append(le32(UInt32(payload.count)))
            out.append(le32(UInt32(entry.data.count)))
            out.append(le16(UInt16(name.count)))
            out.append(le16(0))
            out.append(name)
            out.append(payload)

            central.append(le32(centralSignature))
            central.append(le16(20))
            central.append(le16(20))
            central.append(le16(utf8Flag))
            central.append(le16(method))
            central.append(le16(dosTime))
            central.append(le16(dosDate))
            central.append(le32(crc))
            central.append(le32(UInt32(payload.count)))
            central.append(le32(UInt32(entry.data.count)))
            central.append(le16(UInt16(name.count)))
            central.append(le16(0)) // extra
            central.append(le16(0)) // comentario
            central.append(le16(0)) // disco
            central.append(le16(0)) // atributos internos
            central.append(le32(0)) // atributos externos
            central.append(le32(offset))
            central.append(name)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(eocdSignature))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(UInt16(entries.count)))
        out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(central.count)))
        out.append(le32(centralOffset))
        out.append(le16(0))
        return out
    }

    // MARK: Lectura (directorio central; solo métodos 0 y 8)

    static func entries(in data: Data) throws -> [ZipEntry] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw ZipError.notAZip }
        var eocd = -1
        var i = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 65_535)
        while i >= lowest {
            if read32(bytes, i) == eocdSignature {
                eocd = i
                break
            }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }
        let count = Int(read16(bytes, eocd + 10))
        var pos = Int(read32(bytes, eocd + 16))
        var result: [ZipEntry] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            guard pos + 46 <= bytes.count, read32(bytes, pos) == centralSignature else { throw ZipError.truncated }
            let method = read16(bytes, pos + 10)
            let crc = read32(bytes, pos + 16)
            let compressedSize = Int(read32(bytes, pos + 20))
            let size = Int(read32(bytes, pos + 24))
            let nameLength = Int(read16(bytes, pos + 28))
            let extraLength = Int(read16(bytes, pos + 30))
            let commentLength = Int(read16(bytes, pos + 32))
            let localOffset = Int(read32(bytes, pos + 42))
            guard pos + 46 + nameLength <= bytes.count else { throw ZipError.truncated }
            let name = String(decoding: bytes[(pos + 46)..<(pos + 46 + nameLength)], as: UTF8.self)
            guard localOffset + 30 <= bytes.count, read32(bytes, localOffset) == localSignature else { throw ZipError.truncated }
            let localNameLength = Int(read16(bytes, localOffset + 26))
            let localExtraLength = Int(read16(bytes, localOffset + 28))
            let start = localOffset + 30 + localNameLength + localExtraLength
            guard start + compressedSize <= bytes.count else { throw ZipError.truncated }
            let payload = Data(bytes[start..<(start + compressedSize)])
            let content: Data
            switch method {
            case methodStored:
                content = payload
            case methodDeflate:
                guard let inflated = inflate(payload, expectedSize: size) else { throw ZipError.badDeflate(name) }
                content = inflated
            default:
                throw ZipError.unsupportedMethod(method)
            }
            guard crc32(content) == crc else { throw ZipError.badCRC(name) }
            result.append(ZipEntry(name: name, data: content))
            pos += 46 + nameLength + extraLength + commentLength
        }
        return result
    }

    // MARK: Utilidades

    private static func le16(_ v: UInt16) -> Data {
        Data([UInt8(v & 0xFF), UInt8(v >> 8)])
    }

    private static func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)])
    }

    private static func read16(_ b: [UInt8], _ i: Int) -> UInt16 {
        UInt16(b[i]) | UInt16(b[i + 1]) << 8
    }

    private static func read32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }

    /// Fecha y hora en formato MS-DOS (resolución de 2 s; años 1980...2107).
    static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = min(max((c.year ?? 1980) - 1980, 0), 127)
        let dosDate = UInt16(year << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
        let dosTime = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        return (dosTime, dosDate)
    }
}
