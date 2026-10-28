// Diccionario desde dictionary.json del repo: los mismos casos que
// DictionaryTests de iOS (recuentos, colecciones, nombres curados),
// sin motor nativo (su versión se inyecta).
package com.andreseloy.colorsapp.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

class JsonWadaDictionaryTest {

    private val dictionaryJson: String = run {
        // El directorio de trabajo de los tests JVM es el módulo :app.
        val candidates = listOf(
            File("../../data/wada/dictionary.json"),
            File("data/wada/dictionary.json"),
        )
        candidates.first { it.isFile }.readText()
    }

    private fun load(names: List<WadaName> = emptyList()): JsonWadaDictionary {
        val base = JsonWadaDictionary.decode(dictionaryJson, namesJson = null, engineDictVersion = "x")
        return JsonWadaDictionary.decode(
            dictionaryJson,
            namesJson = namesJsonOf(names),
            engineDictVersion = base.dictVersion,
        )
    }

    private fun namesJsonOf(names: List<WadaName>): String? {
        if (names.isEmpty()) return null
        return names.joinToString(prefix = "[", postfix = "]") { n ->
            "{\"id\":${n.id},\"lang\":\"${n.lang}\",\"name\":\"${n.name}\"," +
                "\"notes\":\"${n.notes}\",\"status\":\"${n.status}\"}"
        }
    }

    @Test
    fun recuentosYEstructura() {
        val d = load()
        d.checkCounts()
        assertEquals(159, d.colors.size)
        assertEquals(348, d.combinations.size)
        assertEquals(1, d.schema)
        assertEquals((1..348).toList(), d.combinations.map { it.id })
        assertEquals(
            mapOf(2 to 120, 3 to 120, 4 to 108),
            d.combinations.groupingBy { it.size }.eachCount(),
        )
        assertEquals((0 until 159).toList(), d.colors.map { it.index })
        assertEquals(12, d.dictVersion.length)
        assertTrue(d.matchesEngine)
    }

    @Test
    fun versionDistintaSeDetecta() {
        val d = JsonWadaDictionary.decode(dictionaryJson, null, engineDictVersion = "000000000000")
        assertFalse(d.matchesEngine)
        try {
            d.checkEngineVersion()
            fail("debía lanzar VersionMismatch")
        } catch (e: WadaDictionaryException.VersionMismatch) {
            assertEquals("000000000000", e.engine)
            assertEquals(d.dictVersion, e.bundle)
        }
    }

    @Test
    fun coloresYCombinaciones() {
        val d = load()
        for (c in d.colors) {
            assertEquals("#%02x%02x%02x".format(c.rgb[0], c.rgb[1], c.rgb[2]), c.hex)
            assertEquals(4, c.cmyk.size)
        }
        for (combo in d.combinations) {
            assertEquals(combo.colors.size, combo.size)
            assertEquals(combo.size, d.colorsOf(combo.id).size)
        }
        assertEquals(listOf(52, 106, 109, 151), d.combo(348)?.colors?.toList())
        assertNull(d.combo(349))
        assertNull(d.color(159))
        assertEquals("Hermosa Pink", d.color(0)?.name)
        assertEquals(listOf(249, 193, 206), d.color(0)?.rgb?.toList())
    }

    @Test
    fun nombreSinCurarEsElNumero() {
        val d = load()
        assertEquals("Nº 001", d.displayName(1))
        assertEquals("Nº 012", d.displayName(12))
        assertEquals("Nº 348", d.displayName(348))
        assertNull(d.curatedName(1))
        assertEquals("Nº 007", d.displayName(7) { "Nº %03d".format(it) })
    }

    @Test
    fun nombreCuradoSoloSiAceptado() {
        val d = load(
            listOf(
                WadaName(1, "es", "Tejados de Lisboa", "", "accepted"),
                WadaName(2, "es", "Propuesta sin aceptar", "", "pending"),
                WadaName(3, "es", "   ", "", "accepted"),
            ),
        )
        assertEquals("Tejados de Lisboa", d.displayName(1))
        assertEquals("Nº 002", d.displayName(2))
        assertEquals("Nº 003", d.displayName(3))
        assertEquals("Nº 004", d.displayName(4))
    }

    @Test
    fun ficheroDeNombresPorIdioma() {
        assertEquals("names.de.json", JsonWadaDictionary.namesAssetFor("de"))
        assertEquals("names.de.json", JsonWadaDictionary.namesAssetFor("de-DE"))
        assertEquals("names.es.json", JsonWadaDictionary.namesAssetFor("es"))
        // El inglés muestra los nombres en español, como en iOS.
        assertEquals("names.es.json", JsonWadaDictionary.namesAssetFor("en"))
        assertEquals("names.es.json", JsonWadaDictionary.namesAssetFor(null as String?))
    }

    @Test
    fun coleccionesPorTamanoYCuradas() {
        val d = load()
        val collections = d.collections()
        // Hoy no hay colecciones curadas en el JSON: solo las automáticas.
        assertEquals(listOf("size:2", "size:3", "size:4"), collections.map { it.id })
        assertEquals(listOf(120, 120, 108), collections.map { it.comboIds.size })
        assertEquals("Combinaciones de 2 colores", collections[0].title)
        assertEquals(348, collections.flatMap { it.comboIds }.toSet().size)
        // Colección curada sintética (EngineWadaDictionary no la trae: se
        // comprueba la agrupación con un diccionario mínimo a mano).
        val fake = object : WadaDictionary {
            override val dictVersion = "x"
            override val colors = emptyList<WadaColor>()
            override val combinations = listOf(
                WadaCombo(1, intArrayOf(0, 1), "Japón"),
                WadaCombo(2, intArrayOf(0, 1), "Japón"),
                WadaCombo(3, intArrayOf(0, 1, 2), null),
            )
            override fun curatedName(id: Int): String? = null
        }
        assertEquals("curated:Japón", fake.collections().first().id)
        assertEquals(listOf(1, 2), fake.collections().first().comboIds)
        assertEquals(3, fake.collections().size)
    }

    @Test
    fun combinacionesQueContienenUnColor() {
        val d = load()
        val black = d.colors.first { it.name == "Black" }
        val combos = d.combosContaining(black.index)
        assertEquals(23, combos.size)
        assertTrue(combos.all { black.index in it.colors })
    }

    @Test
    fun hexSeParseaComoEnIos() {
        assertEquals(listOf(249, 193, 206), parseHexRGB("#f9c1ce")?.toList())
        assertEquals(listOf(249, 193, 206), parseHexRGB("F9C1CE")?.toList())
        assertNull(parseHexRGB("#zz0000"))
        assertNull(parseHexRGB("#fff"))
    }
}
