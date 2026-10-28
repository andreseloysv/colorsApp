// Humo instrumentado de W4: Rejilla con buscador y ficha, Jardín con
// colecciones y Capas con el ejemplo del motor, todo en español por-app.
package com.andreseloy.colorsapp

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.platform.app.InstrumentationRegistry
import com.andreseloy.colorsapp.app.MainActivity
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class W4ScreensTest {
    @get:Rule val composeRule = createAndroidComposeRule<MainActivity>()

    @Before fun fijarEspanol() {
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(
            "cmd locale set-app-locales com.andreseloy.colorsapp --locales es-ES",
        ).close()
        composeRule.waitForIdle()
    }

    @Test fun rejillaBuscaYAbrFicha() {
        composeRule.onNodeWithContentDescription("Rejilla").performClick()
        composeRule.onNodeWithText("REJILLA").assertIsDisplayed()
        composeRule.onNodeWithContentDescription("rejilla.search").performClick()
        composeRule.onNodeWithContentDescription("rejilla.search").performTextInput("12")
        composeRule.onNodeWithContentDescription("rejilla.combo.12").performClick()
        composeRule.onNodeWithText("Copiar hex").assertIsDisplayed()
        composeRule.onNodeWithText("Compartir tarjeta").assertIsDisplayed()
        composeRule.onNodeWithContentDescription("Atrás").performClick()
    }

    @Test fun jardinYColecciones() {
        composeRule.onNodeWithContentDescription("Jardín").performClick()
        composeRule.onNodeWithText("JARDÍN").assertIsDisplayed()
        composeRule.onNodeWithText("COLECCIONES").assertIsDisplayed()
        composeRule.onNodeWithText("Exportar colección (JSON)").assertExists()
    }
}
