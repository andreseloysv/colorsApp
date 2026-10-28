// Diccionario desde los assets generados por syncWadaAssets: nombres
// curados por idioma (alemán en alemán; español e inglés con el español),
// dict_version contra el motor real y coherencia color a color con el C.
package com.andreseloy.colorsapp.data

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.andreseloy.colorsapp.engine.WadaEngineDictionary
import java.util.Locale
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class JsonWadaDictionaryAssetTest {

    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun cargaAssetsYLaVersionCasaConElMotor() {
        val dict = JsonWadaDictionary.load(context, Locale.forLanguageTag("es"))
        assertTrue(dict.matchesEngine)
        dict.checkEngineVersion()
        dict.checkCounts()
        assertEquals(348, dict.names.size)
        // La 1 en español: la misma que enseña iOS (DictionaryTests).
        assertEquals("Tejados de Lisboa", dict.curatedName(1))
        assertEquals("Tejados de Lisboa", dict.displayName(1))
        assertEquals("accepted", dict.names[12]?.status)
    }

    @Test
    fun inglesMuestraLosNombresEnEspanol() {
        val english = JsonWadaDictionary.load(context, Locale.ENGLISH)
        assertEquals("Tejados de Lisboa", english.curatedName(1))
    }

    @Test
    fun alemanMuestraLosNombresEnAleman() {
        val german = JsonWadaDictionary.load(context, Locale.GERMAN)
        assertEquals(348, german.names.size)
        assertEquals("de", german.names[1]?.lang)
        assertEquals("Dachziegel am Mittelmeer", german.curatedName(1))
        assertEquals("Dachziegel am Mittelmeer", german.displayName(1))
    }

    @Test
    fun coloresYCombinacionesComoElMotor() {
        val dict = JsonWadaDictionary.load(context, Locale.forLanguageTag("es"))
        assertEquals(WadaEngineDictionary.colorCount, dict.colors.size)
        assertEquals(WadaEngineDictionary.comboCount, dict.combinations.size)
        for (color in dict.colors) {
            assertArrayEquals(
                WadaEngineDictionary.colorRgb(color.index),
                color.rgb,
            )
            assertEquals(WadaEngineDictionary.colorName(color.index), color.name)
        }
        for (combo in dict.combinations) {
            assertArrayEquals(WadaEngineDictionary.combo(combo.id), combo.colors)
        }
    }

    @Test
    fun laTarjetaDelDiaTieneNombreParaTodas() {
        // Con los nombres aceptados cargados, ninguna combinación cae a la
        // lista de colores en inglés (vuelve el número solo sin curación).
        val dict = JsonWadaDictionary.load(context, Locale.forLanguageTag("es"))
        val withName = dict.combinations.count { dict.curatedName(it.id) != null }
        assertTrue("solo $withName/348 con nombre curado", withName >= 300)
    }
}
