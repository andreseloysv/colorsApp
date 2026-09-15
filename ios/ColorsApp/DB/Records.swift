// Registros GRDB (Codable + FetchableRecord + PersistableRecord) de las cuatro
// tablas de la migración v1. Columnas en snake_case (estrategia de GRDB);
// propiedades en camelCase. Todas llevan las columnas sync-ready
// updated_at / deleted_at / rev / dirty (PLAN §7): los repositorios las
// mantienen; la UI no las toca.
import Foundation
import GRDB
import ColorEngine

/// Origen de un scan / unlock.
enum ScanSource: String, Codable, Sendable, CaseIterable {
    /// Foto tomada con la cámara.
    case camera
    /// Foto elegida con PhotosPicker.
    case picker
    /// Escaneo del carrete (día 0, PhotoKit batch).
    case library
    /// Desbloqueo manual desde Explorar/Rejilla (sin foto).
    case manual
}

/// Veredicto del usuario sobre un resultado ("sí, es eso" / "no").
enum FeedbackVerdict: String, Codable, Sendable, CaseIterable {
    case yes
    case no
}

/// Un swatch serializado en `scans.palette_json`.
struct PaletteEntry: Codable, Hashable, Sendable {
    var hex: String
    var rgb: [Int]
    var lab: [Double]
    var weight: Double

    init(swatch: Swatch) {
        hex = swatch.hex
        rgb = [Int(swatch.r), Int(swatch.g), Int(swatch.b)]
        lab = [swatch.lab.L, swatch.lab.a, swatch.lab.b]
        weight = swatch.weight
    }

    init(hex: String, rgb: [Int], lab: [Double], weight: Double) {
        self.hex = hex
        self.rgb = rgb
        self.lab = lab
        self.weight = weight
    }
}

/// Conformidad común: columnas snake_case en la base de datos.
protocol SyncRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    var rev: Int { get set }
    var dirty: Bool { get set }
}

extension SyncRecord {
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }

    /// Marca el registro como modificado localmente (rev + 1, dirty).
    mutating func touch(now: Date = Date()) {
        updatedAt = now
        rev += 1
        dirty = true
    }
}

// MARK: - scans

struct ScanRecord: SyncRecord, Hashable, Identifiable {
    static let databaseTableName = "scans"

    /// UUIDv7 en minúsculas.
    var id: String
    /// `PHAsset.localIdentifier` cuando la foto viene del carrete.
    var assetLocalId: String?
    var source: ScanSource
    var top1: Int?
    var top2: Int?
    var top3: Int?
    /// JSON `[Double]` con los scores de top1..top3 (mismo orden).
    var scores: String
    /// JSON `[PaletteEntry]` (peso descendente, suma 1).
    var paletteJson: String
    var ambiguous: Bool
    var engineVersion: String
    var dictVersion: String
    var scannedAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var rev: Int
    var dirty: Bool

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let assetLocalId = Column("asset_local_id")
        static let source = Column(CodingKeys.source)
        static let top1 = Column(CodingKeys.top1)
        static let scannedAt = Column("scanned_at")
        static let deletedAt = Column("deleted_at")
    }

    /// Construye el registro a partir del resultado del motor. `id` nuevo (UUIDv7) si no se pasa.
    static func make(from result: AnalysisResult, source: ScanSource, assetLocalId: String? = nil,
                     engineVersion: String = colorEngineVersion, dictVersion: String = dictionaryVersion,
                     now: Date = Date(), id: String? = nil) -> ScanRecord {
        let ids = result.hits.map(\.comboId)
        return ScanRecord(
            id: id ?? UUIDv7.string(now: now),
            assetLocalId: assetLocalId,
            source: source,
            top1: ids.count > 0 ? ids[0] : nil,
            top2: ids.count > 1 ? ids[1] : nil,
            top3: ids.count > 2 ? ids[2] : nil,
            scores: JSONCoding.encode(result.hits.map(\.score)),
            paletteJson: JSONCoding.encode(result.swatches.map(PaletteEntry.init(swatch:))),
            ambiguous: result.ambiguous,
            engineVersion: engineVersion,
            dictVersion: dictVersion,
            scannedAt: now,
            updatedAt: now,
            deletedAt: nil,
            rev: 1,
            dirty: true
        )
    }

    /// Ids del top-3 en orden (los no nulos).
    var topIds: [Int] { [top1, top2, top3].compactMap { $0 } }

    /// Scores decodificados (vacío si el JSON no es válido).
    var scoreValues: [Double] { JSONCoding.decode([Double].self, from: scores) ?? [] }

    /// Paleta decodificada (vacía si el JSON no es válido).
    var palette: [PaletteEntry] { JSONCoding.decode([PaletteEntry].self, from: paletteJson) ?? [] }
}

// MARK: - unlocks

struct UnlockRecord: SyncRecord, Hashable, Identifiable {
    static let databaseTableName = "unlocks"

    var comboId: Int
    var firstSeenAt: Date
    var source: ScanSource
    var assetLocalId: String?
    var scanId: String?
    var updatedAt: Date
    var deletedAt: Date?
    var rev: Int
    var dirty: Bool

    var id: Int { comboId }

    enum Columns {
        static let comboId = Column("combo_id")
        static let firstSeenAt = Column("first_seen_at")
        static let deletedAt = Column("deleted_at")
    }

    init(comboId: Int, firstSeenAt: Date, source: ScanSource, assetLocalId: String? = nil, scanId: String? = nil,
         updatedAt: Date? = nil, deletedAt: Date? = nil, rev: Int = 1, dirty: Bool = true) {
        self.comboId = comboId
        self.firstSeenAt = firstSeenAt
        self.source = source
        self.assetLocalId = assetLocalId
        self.scanId = scanId
        self.updatedAt = updatedAt ?? firstSeenAt
        self.deletedAt = deletedAt
        self.rev = rev
        self.dirty = dirty
    }
}

// MARK: - feedback

struct FeedbackRecord: SyncRecord, Hashable, Identifiable {
    static let databaseTableName = "feedback"

    var id: String
    var scanId: String
    var verdict: FeedbackVerdict
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var rev: Int
    var dirty: Bool

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let scanId = Column("scan_id")
        static let createdAt = Column("created_at")
        static let deletedAt = Column("deleted_at")
    }

    init(id: String? = nil, scanId: String, verdict: FeedbackVerdict, createdAt: Date = Date()) {
        self.id = id ?? UUIDv7.string(now: createdAt)
        self.scanId = scanId
        self.verdict = verdict
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.deletedAt = nil
        self.rev = 1
        self.dirty = true
    }
}

// MARK: - settings

struct SettingRecord: SyncRecord, Hashable, Identifiable {
    static let databaseTableName = "settings"

    var key: String
    var value: String
    var updatedAt: Date
    var deletedAt: Date?
    var rev: Int
    var dirty: Bool

    var id: String { key }

    enum Columns {
        static let key = Column(CodingKeys.key)
        static let value = Column(CodingKeys.value)
        static let deletedAt = Column("deleted_at")
    }

    init(key: String, value: String, now: Date = Date()) {
        self.key = key
        self.value = value
        self.updatedAt = now
        self.deletedAt = nil
        self.rev = 1
        self.dirty = true
    }
}

// MARK: - JSON

/// Codificación JSON compacta y determinista (claves ordenadas) para las
/// columnas `scores` y `palette_json`.
enum JSONCoding {
    static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(string.utf8))
    }
}
