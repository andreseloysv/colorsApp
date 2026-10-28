// Proyecto Android de ChromaSol (ColorsApp). Raíz del build: solo declara los
// plugins; cada módulo los aplica. Sin red en tiempo de ejecución: la red solo
// la usa Gradle para descargar dependencias de compilación.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.compose) apply false
}
