// UUIDv7 (RFC 9562): mismos casos que la semántica de UUIDv7.swift.
package com.andreseloy.colorsapp.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

class UuidV7Test {

    @Test
    fun versionVarianteYFormato() {
        val id = UuidV7.string(1_700_000_000_000L)
        val uuid = UUID.fromString(id)
        assertTrue(id == id.lowercase())
        assertTrue(UuidV7.isV7(uuid))
        assertTrue(UuidV7.isV7(id))
        assertEquals(7, uuid.version())
        assertEquals(2, uuid.variant())
    }

    @Test
    fun elInstanteVaEnLos48BitsAltos() {
        val ms = 1_700_000_123_456L
        val uuid = UuidV7.make(ms, counter = 0x2AB, tail = ByteArray(8))
        assertEquals(ms, UuidV7.timestampMs(uuid))
        assertEquals(ms, UuidV7.timestampMs(uuid.toString()))
        assertNull(UuidV7.timestampMs(UUID.randomUUID()))
    }

    // El generador es proceso-local y compartido: las aserciones son
    // relativas (ningún test puede fijar el milisegundo absoluto).
    @Test
    fun monotoniaEnElMismoMilisegundo() {
        val ids = (1..2000).map { UuidV7.string(1_700_000_200_000L) }
        assertEquals(ids.sorted(), ids)
        assertEquals(ids.size, ids.toSet().size)
        // El contador de 12 bits trasborda al milisegundo siguiente sin perder el orden.
        assertTrue(ids.zipWithNext().all { (a, b) -> a < b })
    }

    @Test
    fun relojHaciaAtrasNoRetrocede() {
        val primero = UuidV7.string(4_000_000_000_000L)
        val despues = UuidV7.string(1_600_000_000_000L)
        assertTrue(despues > primero)
        assertTrue(UuidV7.timestampMs(despues)!! >= UuidV7.timestampMs(primero)!!)
    }
}
