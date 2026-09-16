// Rutas de NavigationStack compartidas por las pestañas (antes en HoyView).
import Foundation

/// Ruta hacia Resultado (Extraer, o «Abrir en Extraer» desde el Feed).
struct ResultRoute: Hashable {
    let outcome: ScanOutcome
    /// "Ver máscara" activado al abrir (atajo de depuración).
    var showMask = false
}

/// Ruta de depuración (-uiScreen ajustes): Ajustes empujado en la pila del Jardín.
struct AjustesRoute: Hashable {}
