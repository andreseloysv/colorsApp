// Contrato del escaneo del carrete (día 0, PLAN §7.6). La implementación real
// es `PhotoKitScanRunner` (PHFetchOptions con fetchLimit, PHImageManager a
// 256 px, TaskGroup de 3 con un ce_ctx por llamada, unlocks + scans en la base
// de datos); `NoopScanRunner` queda como runner inerte para tests y previews.
import Foundation

/// Progreso del escaneo; `AppEnvironment.scanProgress` lo publica para la UI.
struct ScanProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case requestingAccess
        case fetching
        case analyzing
        case finished
        case failed
    }

    var phase: Phase = .idle
    /// Fotos ya analizadas (o descartadas): avanza hasta `total`.
    var processed: Int = 0
    /// Fotos que se van a analizar (0 hasta conocerlo).
    var total: Int = 0
    /// Fotos omitidas (p. ej. solo en iCloud: isNetworkAccessAllowed = false).
    var skipped: Int = 0
    /// Combinaciones desbloqueadas hasta ahora en este escaneo.
    var unlocked: Int = 0
    /// Instante en que empezó el escaneo (nil en `idle`), para mostrar el tiempo.
    var startedAt: Date? = nil

    static let idle = ScanProgress()

    /// 0...1 (0 si `total` es 0).
    var fraction: Double { total > 0 ? Double(processed) / Double(total) : 0 }

    /// Segundos transcurridos desde `startedAt` (0 si no ha empezado).
    func elapsed(now: Date = Date()) -> TimeInterval {
        startedAt.map { now.timeIntervalSince($0) } ?? 0
    }
}

/// Recuento de una combinación en el escaneo (para el resumen tipo Wrapped).
struct ComboCount: Equatable, Hashable, Sendable {
    let comboId: Int
    let count: Int
}

/// Recuento de un color del diccionario (índice 0-based) en los top-1 del escaneo.
struct ColorCount: Equatable, Hashable, Sendable {
    let colorIndex: Int
    let count: Int
}

/// Resumen del escaneo del carrete.
struct ScanSummary: Equatable, Sendable {
    /// Fotos analizadas con éxito.
    var scanned: Int
    /// Fotos omitidas (no disponibles sin red, formato no soportado...).
    var skipped: Int
    /// Fotos en las que el motor falló.
    var failed: Int
    /// Combinaciones desbloqueadas por primera vez en este escaneo.
    var newUnlocks: [Int]
    /// Total de combinaciones desbloqueadas tras el escaneo (contador 41/348).
    var totalUnlocked: Int
    /// Combinaciones más frecuentes (top-1 de cada foto), descendente.
    var topCombos: [ComboCount]
    var startedAt: Date
    var finishedAt: Date
    /// Colores del diccionario más frecuentes en los top-1 (descendente, desempate por índice).
    var topColors: [ColorCount] = []
    /// Color firma: el color del diccionario más frecuente en los top-1 (nil sin fotos).
    var signatureColorIndex: Int? = nil
    /// Acceso limitado a Fotos: no se pudo enumerar el carrete y la UI debe
    /// ofrecer PhotosPicker (PLAN §7.6); el resto del resumen está vacío.
    var needsPicker: Bool = false

    var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }

    /// Resumen sin fotos (acceso limitado o carrete vacío).
    static func empty(needsPicker: Bool = false, totalUnlocked: Int = 0,
                      startedAt: Date = Date(), finishedAt: Date = Date()) -> ScanSummary {
        ScanSummary(scanned: 0, skipped: 0, failed: 0, newUnlocks: [], totalUnlocked: totalUnlocked,
                    topCombos: [], startedAt: startedAt, finishedAt: finishedAt, needsPicker: needsPicker)
    }
}

enum ScanError: Error, Equatable, Sendable {
    /// Sin implementación (NoopScanRunner).
    case notImplemented
    /// El usuario negó el acceso a Fotos.
    case accessDenied
    /// Acceso limitado: la UI debe caer al PhotosPicker (PLAN §7.6).
    case limitedAccess
    case cancelled
}

/// Ejecuta el escaneo del carrete. Aislado al MainActor: el trabajo pesado se
/// lanza dentro (Task.detached / TaskGroup) y `progress` se actualiza en el
/// MainActor; `onProgress` lo engancha `AppEnvironment`.
@MainActor
protocol ScanRunning: AnyObject {
    var progress: ScanProgress { get }
    var onProgress: (@MainActor (ScanProgress) -> Void)? { get set }
    /// Analiza las últimas `limit` fotos del carrete y registra scans y unlocks.
    func runInitialScan(limit: Int) async throws -> ScanSummary
}

/// Runner inerte (tests, previews): no escanea nada.
@MainActor
final class NoopScanRunner: ScanRunning {
    private(set) var progress: ScanProgress = .idle
    var onProgress: (@MainActor (ScanProgress) -> Void)?

    init() {}

    func runInitialScan(limit: Int) async throws -> ScanSummary {
        progress = ScanProgress(phase: .failed)
        onProgress?(progress)
        throw ScanError.notImplemented
    }
}
