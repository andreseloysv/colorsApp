// Wrapper Swift mínimo sobre el motor C (CColorEngine). Solo tipos y llamadas
// directas: toda la matemática vive en C para que iOS y WASM compartan bits.
import CColorEngine

/// Color en CIELAB (D65). `L` en [0, 100].
public struct Lab: Equatable, Hashable, Sendable {
    public var L: Double
    public var a: Double
    public var b: Double

    public init(L: Double, a: Double, b: Double) {
        self.L = L
        self.a = a
        self.b = b
    }

    init(_ c: ce_lab) {
        self.init(L: c.L, a: c.a, b: c.b)
    }

    var cValue: ce_lab {
        ce_lab(L: L, a: a, b: b)
    }
}

/// Versión del motor C.
public var colorEngineVersion: String {
    String(cString: ce_version())
}

/// sRGB de 8 bits -> CIELAB (D65, matriz derivada).
public func srgbToLab(r: UInt8, g: UInt8, b: UInt8) -> Lab {
    Lab(ce_srgb8_to_lab(r, g, b))
}

/// CIELAB -> sRGB de 8 bits (clamp + redondeo).
public func labToSrgb8(_ lab: Lab) -> (r: UInt8, g: UInt8, b: UInt8) {
    var r: UInt8 = 0
    var g: UInt8 = 0
    var b: UInt8 = 0
    ce_lab_to_srgb8(lab.cValue, &r, &g, &b)
    return (r, g, b)
}

/// ΔE00 (CIEDE2000, kL = kC = kH = 1).
public func deltaE2000(_ x: Lab, _ y: Lab) -> Double {
    ce_de2000(x.cValue, y.cValue)
}

/// ΔE00 con factores paramétricos.
public func deltaE2000(_ x: Lab, _ y: Lab, kL: Double, kC: Double, kH: Double) -> Double {
    ce_de2000_k(x.cValue, y.cValue, kL, kC, kH)
}

/// ΔE*ab (CIE 1976).
public func deltaE76(_ x: Lab, _ y: Lab) -> Double {
    ce_de76(x.cValue, y.cValue)
}
