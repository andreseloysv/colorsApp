// Diccionario de Sanzo Wada cargado desde el bundle: data/wada/dictionary.json
// (159 colores, 348 combinaciones, solo sRGB8) y data/wada/names.es.json
// (nombres curados en español; hoy todos `pending`). La versión del diccionario
// del bundle se cruza con la del motor (`ce_dict_version()`): si difieren, el
// match del motor y las fichas de la UI hablarían de diccionarios distintos.
import Foundation
import ColorEngine

/// Un color de Wada tal como está en dictionary.json. `name` es el nombre en
/// inglés (Ridgway) y se muestra tal cual; `index` es el índice 0-based que
/// usa el motor (`dictionaryColorRGB(index:)`).
struct WadaColor: Codable, Hashable, Sendable, Identifiable {
    let index: Int
    let name: String
    let hex: String
    let rgb: [Int]
    let cmyk: [Int]
    let swatch: Int

    var id: Int { index }
}

/// Una combinación (1...348). `colors` son índices de `WadaColor` ascendentes;
/// `collection` es la colección curada (nil hasta que el usuario la nombre).
struct WadaCombo: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let size: Int
    let colors: [Int]
    let collection: String?
}

/// Entrada de names.es.json (curación del usuario; ruta protegida, solo lectura).
struct WadaName: Codable, Hashable, Sendable {
    static let acceptedStatus = "accepted"

    let id: Int
    let lang: String
    let name: String
    let notes: String
    let status: String

    /// Nombre curado y aceptado por el usuario; nil si sigue pendiente o vacío.
    var acceptedName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return status == Self.acceptedStatus && !trimmed.isEmpty ? trimmed : nil
    }
}

/// Colección para "Explorar": curada (campo `collection` de las combinaciones)
/// o automática por tamaño (2, 3 y 4 colores).
struct WadaCollection: Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        case bySize(Int)
        case curated(String)
    }

    let id: String
    let title: String
    let kind: Kind
    let comboIds: [Int]
}

enum WadaDictionaryError: Error, Equatable, Sendable {
    /// Falta un recurso del bundle (dictionary.json o names.es.json).
    case resourceMissing(String)
    /// `dict_version` del bundle distinto de `ce_dict_version()` del motor.
    case versionMismatch(bundle: String, engine: String)
    /// Recuento distinto de 159 colores / 348 combinaciones.
    case unexpectedCounts(colors: Int, combinations: Int)
}

/// Diccionario completo, inmutable y Sendable: se carga una vez en
/// `AppEnvironment` y se pasa por valor.
struct WadaDictionary: Sendable {
    static let dictionaryResource = "dictionary"
    static let namesResource = "names.es"
    static let expectedColorCount = 159
    static let expectedComboCount = 348

    let schema: Int
    let source: String
    let dictVersion: String
    let status: String
    let colors: [WadaColor]
    let combinations: [WadaCombo]
    /// Nombres de names.es.json indexados por id de combinación.
    let names: [Int: WadaName]

    private let comboPosition: [Int: Int]
    private let colorPosition: [Int: Int]

    /// Fichero dictionary.json (claves en snake_case).
    private struct File: Decodable {
        let schema: Int
        let source: String
        let dictVersion: String
        let status: String
        let colors: [WadaColor]
        let combinations: [WadaCombo]

        enum CodingKeys: String, CodingKey {
            case schema, source, status, colors, combinations
            case dictVersion = "dict_version"
        }
    }

    init(schema: Int, source: String, dictVersion: String, status: String,
         colors: [WadaColor], combinations: [WadaCombo], names: [WadaName]) {
        self.schema = schema
        self.source = source
        self.dictVersion = dictVersion
        self.status = status
        self.colors = colors
        self.combinations = combinations
        self.names = Dictionary(names.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.comboPosition = Dictionary(combinations.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.colorPosition = Dictionary(colors.enumerated().map { ($1.index, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Carga

    /// Decodifica dictionary.json y names.es.json (opcional: sin nombres todo cae
    /// al "Nº 012"). No comprueba la versión del motor: ver `checkEngineVersion`.
    static func decode(dictionaryData: Data, namesData: Data?) throws -> WadaDictionary {
        let decoder = JSONDecoder()
        let file = try decoder.decode(File.self, from: dictionaryData)
        let names = try namesData.map { try decoder.decode([WadaName].self, from: $0) } ?? []
        return WadaDictionary(schema: file.schema, source: file.source, dictVersion: file.dictVersion,
                              status: file.status, colors: file.colors, combinations: file.combinations,
                              names: names)
    }

    /// Carga desde el bundle (recursos `dictionary.json` y `names.es.json`) y
    /// comprueba recuentos y versión del motor.
    static func load(from bundle: Bundle = .main) throws -> WadaDictionary {
        guard let dictURL = bundle.url(forResource: dictionaryResource, withExtension: "json") else {
            throw WadaDictionaryError.resourceMissing("\(dictionaryResource).json")
        }
        guard let namesURL = bundle.url(forResource: namesResource, withExtension: "json") else {
            throw WadaDictionaryError.resourceMissing("\(namesResource).json")
        }
        let dict = try decode(dictionaryData: Data(contentsOf: dictURL), namesData: Data(contentsOf: namesURL))
        try dict.checkCounts()
        try dict.checkEngineVersion()
        return dict
    }

    /// Versión del diccionario embebido en el motor C (`ce_dict_version()`).
    static var engineDictVersion: String { dictionaryVersion }

    var matchesEngine: Bool { dictVersion == Self.engineDictVersion }

    func checkEngineVersion() throws {
        guard matchesEngine else {
            throw WadaDictionaryError.versionMismatch(bundle: dictVersion, engine: Self.engineDictVersion)
        }
    }

    func checkCounts() throws {
        guard colors.count == Self.expectedColorCount, combinations.count == Self.expectedComboCount else {
            throw WadaDictionaryError.unexpectedCounts(colors: colors.count, combinations: combinations.count)
        }
    }

    // MARK: Acceso

    func combo(id: Int) -> WadaCombo? {
        comboPosition[id].map { combinations[$0] }
    }

    func color(index: Int) -> WadaColor? {
        colorPosition[index].map { colors[$0] }
    }

    /// Colores de una combinación en el orden del diccionario (índices ascendentes).
    func colors(of combo: WadaCombo) -> [WadaColor] {
        combo.colors.compactMap { color(index: $0) }
    }

    func colors(ofComboId id: Int) -> [WadaColor] {
        combo(id: id).map(colors(of:)) ?? []
    }

    /// Combinaciones que contienen el color `index`, por id ascendente.
    func combos(containingColor index: Int) -> [WadaCombo] {
        combinations.filter { $0.colors.contains(index) }
    }

    // MARK: Nombres

    /// "Nº 012" (tres dígitos, ordinal º).
    static func numberLabel(_ id: Int) -> String {
        String(format: "Nº %03d", id)
    }

    /// Nombre curado (status accepted) de la combinación; nil si no lo hay.
    func curatedName(id: Int) -> String? {
        names[id]?.acceptedName
    }

    /// Nombre para la UI: el curado si está aceptado, si no "Nº 012".
    func displayName(id: Int) -> String {
        curatedName(id: id) ?? Self.numberLabel(id)
    }

    // MARK: Colecciones

    /// Colecciones curadas (por nombre, orden alfabético) seguidas de las
    /// automáticas por tamaño (2, 3, 4 colores).
    var collections: [WadaCollection] {
        var curated: [String: [Int]] = [:]
        for c in combinations {
            if let name = c.collection, !name.isEmpty {
                curated[name, default: []].append(c.id)
            }
        }
        let curatedCollections = curated.keys.sorted().map { name in
            WadaCollection(id: "curated:\(name)", title: name, kind: .curated(name), comboIds: curated[name] ?? [])
        }
        return curatedCollections + collectionsBySize
    }

    /// Colecciones automáticas: "Combinaciones de N colores" para cada tamaño presente.
    var collectionsBySize: [WadaCollection] {
        let sizes = Set(combinations.map(\.size)).sorted()
        return sizes.map { size in
            WadaCollection(id: "size:\(size)", title: "Combinaciones de \(size) colores", kind: .bySize(size),
                           comboIds: combinations.filter { $0.size == size }.map(\.id))
        }
    }
}
