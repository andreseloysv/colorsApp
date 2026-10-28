// UUIDv7 (RFC 9562 §5.7): espejo de ios/ColorsApp/DB/UUIDv7.swift.
// 48 bits de milisegundos Unix + ver 7 + 12 bits de contador (método 1 de
// §6.2: monotonía dentro del mismo milisegundo) + variante 10 + 62 bits
// aleatorios. Ids ordenables por tiempo, generados en el cliente: son la
// clave primaria de `scans` y `feedback` (sync-ready).
package com.andreseloy.colorsapp.data

import java.security.SecureRandom
import java.util.UUID

object UuidV7 {
    private val random = SecureRandom()
    private val lock = Any()
    private var lastMs = 0L
    private var counter = 0

    /**
     * Devuelve (ms, contador de 12 bits) estrictamente crecientes entre
     * llamadas. Si el reloj va hacia atrás se usa el último milisegundo:
     * la monotonía manda sobre el reloj, como en iOS.
     */
    private fun next(nowMs: Long): Pair<Long, Int> = synchronized(lock) {
        var ms = maxOf(nowMs, lastMs)
        if (ms == lastMs) {
            if (counter == 0x0FFF) {
                ms += 1 // desbordamiento del contador: siguiente milisegundo
                counter = random.nextInt(0x0800)
            } else {
                counter += 1
            }
        } else {
            // Semilla aleatoria con el bit alto a 0: deja margen para incrementos.
            counter = random.nextInt(0x0800)
        }
        lastMs = ms
        ms to counter
    }

    /** Genera un UUIDv7 monotónico (proceso-local) para el instante [nowMs]. */
    fun generate(nowMs: Long = System.currentTimeMillis()): UUID {
        val (ms, cnt) = next(milliseconds(nowMs))
        return make(ms, cnt)
    }

    /** Representación canónica en minúsculas (la que va a la base de datos). */
    fun string(nowMs: Long = System.currentTimeMillis()): String = generate(nowMs).toString()

    /** Milisegundos Unix recortados a 48 bits, nunca negativos. */
    fun milliseconds(nowMs: Long): Long = maxOf(0L, nowMs) and 0x0000_FFFF_FFFF_FFFFL

    /**
     * Construye el UUIDv7 de [milliseconds] (48 bits) y [counter] (12 bits)
     * con cola aleatoria; sin pasar por el generador monotónico.
     * [tail] son los 8 bytes bajos antes de fijar la variante (tests).
     */
    fun make(milliseconds: Long, counter: Int, tail: ByteArray? = null): UUID {
        val ms = milliseconds(milliseconds)
        val low = ByteArray(8).also { random.nextBytes(it) }
        if (tail != null) {
            require(tail.size == 8) { "la cola del UUIDv7 son 8 bytes" }
            tail.copyInto(low)
        }
        val msb = (ms shl 16) or (0x7000L or (counter.toLong() and 0x0FFFL))
        var lsb = 0L
        for (i in 0 until 8) {
            val b = if (i == 0) {
                0x80L or (low[0].toLong() and 0x3FL) // variante 10xx
            } else {
                low[i].toLong() and 0xFFL
            }
            lsb = lsb or (b shl (56 - 8 * i))
        }
        return UUID(msb, lsb)
    }

    fun isV7(uuid: UUID): Boolean = uuid.version() == 7 && uuid.variant() == 2

    fun isV7(value: String): Boolean =
        runCatching { isV7(UUID.fromString(value)) }.getOrDefault(false)

    /** Instante (ms Unix) codificado en los 48 bits altos; null si no es v7. */
    fun timestampMs(uuid: UUID): Long? =
        if (isV7(uuid)) uuid.mostSignificantBits ushr 16 else null

    fun timestampMs(value: String): Long? =
        runCatching { timestampMs(UUID.fromString(value)) }.getOrNull()
}
