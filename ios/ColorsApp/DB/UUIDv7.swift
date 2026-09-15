// UUIDv7 (RFC 9562 §5.7): 48 bits de milisegundos Unix + ver 7 + 12 bits de
// contador (método 1 de §6.2: monotonía dentro del mismo milisegundo) +
// variante 10 + 62 bits aleatorios. Ids ordenables por tiempo, generados en el
// cliente: son la clave primaria de `scans` y `feedback` (sync-ready).
import Foundation

enum UUIDv7 {
    private struct State {
        var lastMs: UInt64 = 0
        var counter: UInt16 = 0
    }

    private final class Generator: @unchecked Sendable {
        private let lock = NSLock()
        private var state = State()

        /// Devuelve (ms, contador de 12 bits) estrictamente crecientes entre llamadas.
        func next(nowMs: UInt64) -> (ms: UInt64, counter: UInt16) {
            lock.lock()
            defer { lock.unlock() }
            var ms = max(nowMs, state.lastMs) // reloj hacia atrás: no retrocede
            if ms == state.lastMs {
                if state.counter == 0x0FFF {
                    ms += 1 // desbordamiento del contador: siguiente milisegundo
                    state.counter = UInt16.random(in: 0...0x07FF)
                } else {
                    state.counter += 1
                }
            } else {
                // Semilla aleatoria con el bit alto a 0: deja margen para incrementos.
                state.counter = UInt16.random(in: 0...0x07FF)
            }
            state.lastMs = ms
            return (ms, state.counter)
        }
    }

    private static let generator = Generator()

    /// Milisegundos Unix (48 bits) de una fecha.
    static func milliseconds(_ date: Date) -> UInt64 {
        let ms = (date.timeIntervalSince1970 * 1000).rounded(.down)
        return UInt64(max(0, ms)) & 0x0000_FFFF_FFFF_FFFF
    }

    /// Genera un UUIDv7 monotónico (proceso-local) para el instante `now`.
    /// Si `now` es anterior al último id generado, se usa el último milisegundo
    /// (+ contador): la monotonía manda sobre el reloj.
    static func generate(now: Date = Date()) -> UUID {
        let (ms, counter) = generator.next(nowMs: milliseconds(now))
        return make(milliseconds: ms, counter: counter)
    }

    /// Construye el UUIDv7 de `milliseconds` (48 bits) y `counter` (12 bits)
    /// con cola aleatoria; sin pasar por el generador monotónico.
    static func make(milliseconds ms: UInt64, counter: UInt16) -> UUID {
        var b = [UInt8](repeating: 0, count: 16)
        b[0] = UInt8((ms >> 40) & 0xFF)
        b[1] = UInt8((ms >> 32) & 0xFF)
        b[2] = UInt8((ms >> 24) & 0xFF)
        b[3] = UInt8((ms >> 16) & 0xFF)
        b[4] = UInt8((ms >> 8) & 0xFF)
        b[5] = UInt8(ms & 0xFF)
        b[6] = 0x70 | UInt8((counter >> 8) & 0x0F) // versión 7 + rand_a alto
        b[7] = UInt8(counter & 0xFF)
        b[8] = 0x80 | UInt8.random(in: 0...0x3F) // variante 10xx
        for i in 9..<16 { b[i] = UInt8.random(in: 0...255) }
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    /// Representación canónica en minúsculas (la que va a la base de datos).
    static func string(now: Date = Date()) -> String {
        generate(now: now).uuidString.lowercased()
    }

    static func isV7(_ uuid: UUID) -> Bool {
        let u = uuid.uuid
        return (u.6 >> 4) == 7 && (u.8 & 0xC0) == 0x80
    }

    /// Instante codificado en los 48 bits altos; nil si no es v7.
    static func timestamp(of uuid: UUID) -> Date? {
        guard isV7(uuid) else { return nil }
        let u = uuid.uuid
        let ms = (UInt64(u.0) << 40) | (UInt64(u.1) << 32) | (UInt64(u.2) << 24)
            | (UInt64(u.3) << 16) | (UInt64(u.4) << 8) | UInt64(u.5)
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }
}
