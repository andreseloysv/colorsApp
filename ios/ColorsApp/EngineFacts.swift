// Datos que la UI del stub toma del motor C a través del wrapper Swift.
import ColorEngine

enum EngineFacts {
    /// Versión del motor C (`ce_version()`).
    static var engineVersion: String {
        colorEngineVersion
    }

    /// Par 1 del test set de Sharma, Wu y Dalal (2005): ΔE00 esperado 2.0425.
    static let sharmaPair1 = (
        Lab(L: 50.0000, a: 2.6772, b: -79.7751),
        Lab(L: 50.0000, a: 0.0000, b: -82.7485)
    )

    /// ΔE2000 del par 1 de Sharma calculado por el motor.
    static var sharmaPair1DeltaE: Double {
        deltaE2000(sharmaPair1.0, sharmaPair1.1)
    }
}
