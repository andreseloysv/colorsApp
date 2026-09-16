// Versión de la política de análisis de un scan: qué reglas de motor y de recorte se usaron
// para calcular su paleta y su match. Un scan guardado con una política vieja puede seguir
// mostrando un resultado que hoy no saldría (CONTEXT §11 y §13: la tarjeta del tranvía decía
// Nº 067 porque se guardó antes de quitar la hipótesis de iluminante), así que la app tiene que
// poder RE-ANALIZAR los scans viejos al abrirlos.
//
// La columna `scans.engine_policy_version` (migración v4) guarda `AnalysisPolicy.current` en el
// momento del análisis. `needsReanalysis` compara esa versión, la del motor (`engine_version`)
// y la del diccionario (`dict_version`) con las actuales. La lógica de re-análisis en las vistas
// (cuándo se dispara, qué se le enseña al usuario) la hace el equipo de interfaz; aquí solo está
// el criterio, para que sea el mismo en todas las pantallas.
import Foundation
import ColorEngine

enum AnalysisPolicy {
    /// Versión actual. Se SUBE cuando cambia algo que altera el resultado de un scan sin cambiar
    /// la versión del motor: valores por defecto del match, la cadena de máscaras de SubjectKit o
    /// el camino de paleta (clásico / por prenda).
    ///
    /// - 1 (2026-09-16): match sin hipótesis de iluminante (`illuminant_search` = 0, ADR-009),
    ///   recorte por defecto persona más grande + solo ropa + piel adaptativa con piel en sombra
    ///   (ADR-010) y paleta POR PRENDA con el mapa de regiones de la pose cuando lo hay
    ///   (`SubjectMaskResult.garmentRegions`, ADR-011); sin pose, camino clásico.
    ///
    /// nil en la base de datos = scan anterior a la migración v4: se re-analiza.
    static let current = 1

    /// true si `scan` se analizó con una política, un motor o un diccionario distintos de los de
    /// esta build (o antes de que existiera la columna) y hay que volver a analizarlo.
    /// Los scans manuales (sin foto) no tienen nada que re-analizar.
    static func needsReanalysis(_ scan: ScanRecord, engineVersion: String = colorEngineVersion,
                                dictVersion: String = dictionaryVersion, policyVersion: Int = current) -> Bool {
        guard scan.source != .manual else { return false }
        guard let version = scan.enginePolicyVersion else { return true }
        return version != policyVersion || scan.engineVersion != engineVersion || scan.dictVersion != dictVersion
    }
}
