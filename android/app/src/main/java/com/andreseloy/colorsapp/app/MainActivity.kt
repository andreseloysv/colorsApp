// Actividad única: tema ChromaSol + grafo de navegación de las cuatro
// pestañas (RootTabView de iOS). Sin ajustes de idioma en la app: manda el
// idioma del sistema (values/ = español como respaldo, como
// CFBundleDevelopmentRegion = es en iOS).
package com.andreseloy.colorsapp.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.andreseloy.colorsapp.design.ChromaSolTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val container = (application as ColorsApp).container
        enableEdgeToEdge()
        setContent {
            ChromaSolTheme {
                ChromaSolApp(container = container)
            }
        }
    }
}
