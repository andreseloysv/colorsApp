// Lógica pura del Feed (docs/design/DESIGN_SYSTEM.md §5.1), sin vistas ni base de datos:
// filtros, combinación del día, nombre de una combinación, textos de la publicación
// (origen, fecha, persona y recorte) y conversión de un scan guardado a los datos que
// pintan los componentes. Sin lógica de color: el nombre de Wada más cercano y su ΔE
// vienen del motor (`PaletteColor.namedByNearestWada`).
import Foundation
import SubjectKit

// MARK: - Filtros

/// Chips del Feed: todo, por tamaño de la combinación ganadora, guardadas y por votar.
enum FeedFilter: String, CaseIterable, Identifiable, Sendable {
    case all, two, three, four, saved, unvoted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Todo"
        case .two: "2 colores"
        case .three: "3 colores"
        case .four: "4 colores"
        case .saved: "Guardadas"
        case .unvoted: "Por votar"
        }
    }

    /// Solo «Todo» lleva icono (como el chip activo del ejemplo); sin puntos de color de datos.
    var systemImage: String? {
        self == .all ? "sun.max.fill" : nil
    }

    /// Tamaño de combinación que exige el filtro (nil = cualquiera).
    var comboSize: Int? {
        switch self {
        case .two: 2
        case .three: 3
        case .four: 4
        default: nil
        }
    }

    /// ¿Entra la publicación? `top1Size` = colores de la combinación ganadora (nil sin resultado).
    func includes(top1Size: Int?, verdict: FeedbackVerdict?, isSaved: Bool) -> Bool {
        switch self {
        case .all: true
        case .two, .three, .four: top1Size == comboSize
        case .saved: isSaved
        case .unvoted: verdict == nil
        }
    }

    /// Texto del estado vacío cuando el filtro no deja ninguna publicación.
    var emptyText: String {
        switch self {
        case .all: "Todavía no has analizado ninguna foto."
        case .two, .three, .four: "Ninguna foto se parece a una combinación de \(comboSize ?? 0) colores."
        case .saved: "Aún no has guardado ninguna publicación. Toca «Guardar» para llevarla a tu jardín."
        case .unvoted: "Has votado todas tus fotos. ¡Gracias!"
        }
    }
}

// MARK: - Combinación del día

enum DayPick {
    /// Días desde 1970-01-01 de la fecha LOCAL (año, mes y día en `calendar`), sin horas.
    static func localDaysSince1970(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let midnight = utc.date(from: DateComponents(year: c.year, month: c.month, day: c.day)) ?? date
        return Int((midnight.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    /// Combinación del día: `(díasDesde1970 × 7919) mod 348 + 1` sobre la fecha local (§5.1).
    static func comboId(for date: Date, calendar: Calendar = .current, count: Int = WadaDictionary.expectedComboCount) -> Int {
        guard count > 0 else { return 1 }
        let days = localDaysSince1970(date, calendar: calendar)
        let product = (days % count) * (7919 % count)
        return ((product % count) + count) % count + 1
    }

    /// Otra combinación al azar distinta de `current` (1...count). Aleatoriedad de interfaz:
    /// el motor no tiene RNG y no interviene.
    static func another<G: RandomNumberGenerator>(than current: Int, count: Int = WadaDictionary.expectedComboCount,
                                                  using generator: inout G) -> Int {
        guard count > 1 else { return 1 }
        let pick = Int.random(in: 1...(count - 1), using: &generator)
        return pick >= current ? pick + 1 : pick
    }

    static func another(than current: Int, count: Int = WadaDictionary.expectedComboCount) -> Int {
        var generator = SystemRandomNumberGenerator()
        return another(than: current, count: count, using: &generator)
    }
}

// MARK: - Nombres

enum FeedComboName {
    /// Nombre de una combinación para la interfaz: curado (names.es.json) → propuesto
    /// (names.suggested.json, vía `ComboNaming` de la Rejilla) → nombres de Wada de sus dos
    /// primeros colores («Warm Gray · Black»), porque el número ya va en el subtítulo.
    /// «Nº 067» si la combinación no existe.
    static func name(_ id: Int, in dictionary: WadaDictionary, naming: ComboNaming = .bundled) -> String {
        let named = naming.name(for: id, in: dictionary)
        if named.kind != .number { return named.text }
        let names = dictionary.colors(ofComboId: id).prefix(2).map(\.name)
        return names.isEmpty ? WadaDictionary.numberLabel(id) : names.joined(separator: " · ")
    }

    /// Resumen del top-1 de un scan para el pie «Se parece a» (nil sin resultado).
    static func match(for scan: ScanRecord, in dictionary: WadaDictionary, naming: ComboNaming = .bundled) -> ComboMatchSummary? {
        guard let top1 = scan.top1, dictionary.combo(id: top1) != nil else { return nil }
        var ambiguity: String?
        if scan.ambiguous, let top2 = scan.top2 {
            ambiguity = "Entre \(WadaDictionary.numberLabel(top1)) y \(WadaDictionary.numberLabel(top2))"
        }
        return ComboMatchSummary(comboId: top1, name: name(top1, in: dictionary, naming: naming),
                                 colors: PaletteColor.combo(top1, in: dictionary), ambiguityText: ambiguity)
    }
}

// MARK: - Publicación

/// Textos y datos de una publicación a partir de un scan guardado.
enum FeedPostText {
    static let spanish = Locale(identifier: "es_ES")

    static func source(_ source: ScanSource) -> PostSource {
        switch source {
        case .library: .library
        case .camera: .camera
        case .picker, .manual: .picked
        }
    }

    /// «14 sept, 10:45» este año y «14 sept 2025, 10:45» en años anteriores (una sola línea en la cabecera).
    static func date(_ date: Date, timeZone: TimeZone = .current, now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        var style = Date.FormatStyle(locale: spanish, calendar: calendar, timeZone: timeZone)
            .day().month(.abbreviated).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        if !sameYear { style = style.year() }
        style.capitalizationContext = .middleOfSentence
        return date.formatted(style)
    }

    /// Persona analizada: «Persona principal de 3», «Persona 2 de 3», «Todas las personas (3)»,
    /// «1 persona», «Foto completa»; nil en scans anteriores al recorte de sujeto.
    static func person(_ scan: ScanRecord) -> String? {
        guard let raw = scan.subjectMode else { return nil }
        let mode = SubjectMode(rawValue: raw)
        let steps = scan.maskStepValues
        let n = scan.peopleCount ?? 0
        if mode == .off || steps.contains(.visionUnavailable) || steps.contains(.noPeople) || n == 0 {
            return "Foto completa"
        }
        if mode == .allPeople {
            return n == 1 ? "1 persona" : "Todas las personas (\(n))"
        }
        if n == 1 { return "1 persona" }
        let index = scan.personIndex ?? 0
        return index == 0 ? "Persona principal de \(n)" : "Persona \(index + 1) de \(n)"
    }

    /// Metadatos de la cabecera: «14 sept, 10:45 · Persona principal de 3».
    static func metadata(_ scan: ScanRecord, timeZone: TimeZone = .current, isExample: Bool = false, now: Date = Date()) -> String {
        var parts: [String] = []
        if isExample { parts.append("Ejemplo") }
        parts.append(date(scan.scannedAt, timeZone: timeZone, now: now))
        if let person = person(scan) { parts.append(person) }
        return parts.joined(separator: " · ")
    }

    /// Aviso corto del recorte sobre la foto (versión breve de `MaskStepsText.notice` a partir
    /// de lo guardado en el scan): «Solo ropa», «Persona completa», «Todas las personas (3)»,
    /// «Foto completa». `isFallback` = la máscara no se aplicó como se pidió.
    static func cropNotice(_ scan: ScanRecord) -> (text: String, isFallback: Bool)? {
        guard let raw = scan.subjectMode else { return nil }
        let mode = SubjectMode(rawValue: raw)
        let region = scan.regionMode.flatMap(RegionMode.init(rawValue:))
        let steps = scan.maskStepValues
        if mode == .off { return ("Foto completa", false) }
        if steps.contains(.visionUnavailable) || steps.contains(.noPeople) || steps.contains(.none) || (scan.maskCoverage ?? 0) <= 0 {
            return ("Foto completa", true)
        }
        if steps.contains(.wholePerson) { return ("Persona completa", true) }
        var text: String
        switch region {
        case .clothing?: text = "Solo ropa"
        case .wholePerson?: text = "Persona completa"
        default: text = "Persona"
        }
        if mode == .allPeople, let n = scan.peopleCount, n >= 2 {
            text = "Todas las personas (\(n)) · " + text.lowercased()
        }
        if steps.contains(.skinExcluded) { text += " · piel excluida" }
        return (text, steps.contains(.skinGuard))
    }

    /// «Paleta de la ropa» con máscara de ropa, «Paleta de la persona» con la persona entera,
    /// «Paleta de la foto» sin máscara.
    static func paletteTitle(_ scan: ScanRecord) -> String {
        guard let raw = scan.subjectMode, SubjectMode(rawValue: raw) != .off, (scan.maskCoverage ?? 0) > 0 else {
            return "Paleta de la foto"
        }
        let steps = scan.maskStepValues
        if steps.contains(.wholePerson) || scan.regionMode == RegionMode.wholePerson.rawValue {
            return "Paleta de la persona"
        }
        return "Paleta de la ropa"
    }

    /// Paleta del scan con el nombre del color de Wada más cercano (motor) y su peso.
    static func palette(_ scan: ScanRecord, in dictionary: WadaDictionary) -> [PaletteColor] {
        scan.palette.enumerated().compactMap { i, entry in
            PaletteColor(id: i, hex: entry.hex, weight: entry.weight)?.namedByNearestWada(in: dictionary)
        }
    }

    static func verdict(_ verdict: FeedbackVerdict?) -> Verdict? {
        switch verdict {
        case .yes?: .yes
        case .no?: .no
        case nil: nil
        }
    }

    /// Texto del toast al copiar: «Copiado #222524» / «Copiados 4 hex».
    static func copiedToast(count: Int, single: String? = nil) -> String {
        if count == 1, let single { return "Copiado \(single)" }
        return "Copiados \(count) hex"
    }

    /// Estado de la tarjeta del día: «4 colores · En tu rejilla» / «4 colores · Bloqueada».
    static func dayStatus(size: Int, unlocked: Bool) -> String {
        "\(size) \(size == 1 ? "color" : "colores") · \(unlocked ? "En tu rejilla" : "Bloqueada")"
    }
}

// MARK: - Escaneo inicial

/// Presentación automática del escaneo del carrete la primera vez que se abre el Feed.
enum FeedOnboarding {
    /// Presentar la hoja: solo si el escaneo inicial no se ha hecho ni saltado, sin atajo de
    /// depuración y fuera de XCTest.
    static func shouldPresent(initialScanDone: Bool, skipped: Bool, debugScreen: Bool, runningTests: Bool) -> Bool {
        !initialScanDone && !skipped && !debugScreen && !runningTests
    }

    /// Tras cerrar la hoja: si el escaneo inicial no se hizo, se marca como saltado.
    static func markDismissed(settings: SettingsRepository) async {
        let done = (try? await settings.bool(.initialScanDone)) ?? false
        if !done {
            try? await settings.setBool(.scanOnboardingSkipped, true)
        }
    }
}
