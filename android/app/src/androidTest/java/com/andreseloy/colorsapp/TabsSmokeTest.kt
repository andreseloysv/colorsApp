// Humo de UI en el emulador: la app arranca, enseña las cuatro pestañas en
// español y navega entre ellas. No sustituye la inspección visual (capturas
// en harness/out/android). El idioma se fija a español por-app (API 33+) para
// no depender del idioma del emulador que ejecute el test.
package com.andreseloy.colorsapp

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.platform.app.InstrumentationRegistry
import com.andreseloy.colorsapp.app.MainActivity
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class TabsSmokeTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Before
    fun fijarEspanol() {
        // Idioma por aplicación: recrea la actividad con values/ (español).
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(
            "cmd locale set-app-locales com.andreseloy.colorsapp --locales es-ES",
        ).close()
        composeRule.waitForIdle()
    }

    @Test
    fun cuatroPestanasVisiblesYNavegables() {
        composeRule.onNodeWithText("Feed").assertIsDisplayed()
        composeRule.onNodeWithText("Extraer").assertIsDisplayed()
        composeRule.onNodeWithText("Rejilla").assertIsDisplayed()
        composeRule.onNodeWithText("Jardín").assertIsDisplayed()
        composeRule.onNodeWithText("COMBINACIÓN DEL DÍA").assertIsDisplayed()

        composeRule.onNodeWithContentDescription("Rejilla").performClick()
        composeRule.onNodeWithText("REJILLA").assertIsDisplayed()

        composeRule.onNodeWithContentDescription("Jardín").performClick()
        composeRule.onNodeWithText("JARDÍN").assertIsDisplayed()

        composeRule.onNodeWithContentDescription("Extraer").performClick()
        composeRule.onNodeWithText("EXTRAER").assertIsDisplayed()

        composeRule.onNodeWithContentDescription("Feed").performClick()
        composeRule.onNodeWithText("COMBINACIÓN DEL DÍA").assertIsDisplayed()
    }
}
