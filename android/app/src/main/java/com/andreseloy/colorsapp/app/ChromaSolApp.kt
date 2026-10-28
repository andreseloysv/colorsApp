// Navegación raíz: las cuatro pestañas de RootTabView (Feed · Extraer ·
// Rejilla · Jardín) con NavHost y la barra propia SolarTabBar. Cada pestaña
// conserva su estado (saveState/restoreState), como en iOS, donde las
// pestañas abiertas siguen vivas. Ajustes es una ruta secundaria del Feed.
package com.andreseloy.colorsapp.app

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.andreseloy.colorsapp.R
import com.andreseloy.colorsapp.design.BrandCreature
import com.andreseloy.colorsapp.design.LightMotes
import com.andreseloy.colorsapp.design.SolarIconDrop
import com.andreseloy.colorsapp.design.SolarIconGrid
import com.andreseloy.colorsapp.design.SolarIconLeaf
import com.andreseloy.colorsapp.design.SolarIconSun
import com.andreseloy.colorsapp.design.SolarTabBar
import com.andreseloy.colorsapp.design.SolarTabItem
import com.andreseloy.colorsapp.design.SolarTheme
import com.andreseloy.colorsapp.feature.extract.ExtractScreen
import com.andreseloy.colorsapp.feature.feed.FeedScreen
import com.andreseloy.colorsapp.feature.garden.W4GardenScreen
import com.andreseloy.colorsapp.feature.grid.W4GridScreen
import com.andreseloy.colorsapp.feature.layers.LayersScreen
import com.andreseloy.colorsapp.feature.settings.AboutScreen
import com.andreseloy.colorsapp.feature.settings.FontLicensesScreen
import com.andreseloy.colorsapp.feature.settings.W4SettingsScreen
import com.andreseloy.colorsapp.scan.ScanProgress

/** Rutas de la app (AppTab de iOS + secundarias). */
object Routes {
    const val FEED = "feed"
    const val EXTRACT = "extract"
    const val GRID = "grid"
    const val GARDEN = "garden"
    const val SETTINGS = "settings"
    const val LICENSES = "licenses"
    const val ABOUT = "about"
    const val LAYERS = "layers"
    val TABS = listOf(FEED, EXTRACT, GRID, GARDEN)
}

@Composable
fun ChromaSolApp(
    container: AppContainer,
    navController: NavHostController = rememberNavController(),
) {
    val backStack by navController.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route
    val scanProgress by container.scanProgress.collectAsState()
    val colors = SolarTheme.colors

    fun selectTab(route: String) {
        if (route == currentRoute) return
        navController.navigate(route) {
            popUpTo(navController.graph.findStartDestination().id) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }

    // Insignia de Extraer durante el escaneo (RootTabContainer.scanBadge).
    val scanBadge = when (scanProgress.phase) {
        ScanProgress.Phase.ANALYZING -> scanProgress.processed.toString()
        ScanProgress.Phase.REQUESTING_ACCESS, ScanProgress.Phase.FETCHING -> "…"
        else -> null
    }

    Scaffold(
        containerColor = colors.surface,
        contentWindowInsets = WindowInsets(0),
        bottomBar = {
            if (currentRoute in Routes.TABS || currentRoute == null) {
                Column(Modifier.background(colors.surface)) {
                    Box(Modifier.windowInsetsPadding(WindowInsets.navigationBars)) {
                        SolarTabBar(
                            items = listOf(
                                SolarTabItem(Routes.FEED, stringResource(R.string.tab_feed), SolarIconSun,
                                    creature = BrandCreature.SEED),
                                SolarTabItem(
                                    Routes.EXTRACT, stringResource(R.string.tab_extract), SolarIconDrop,
                                    badge = scanBadge, creature = BrandCreature.DRAGONFLY,
                                ),
                                SolarTabItem(Routes.GRID, stringResource(R.string.tab_grid), SolarIconGrid,
                                    creature = BrandCreature.DEWDROP),
                                SolarTabItem(Routes.GARDEN, stringResource(R.string.tab_garden), SolarIconLeaf,
                                    creature = BrandCreature.SPROUT),
                            ),
                            selectedRoute = currentRoute ?: Routes.FEED,
                            onSelect = { selectTab(it.route) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        Box(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .background(colors.surface),
        ) {
        NavHost(
            navController = navController,
            startDestination = Routes.FEED,
            modifier = Modifier.fillMaxSize(),
        ) {
            composable(Routes.FEED) {
                // W3: Feed real. Ajustes cuelga del Jardin como en iOS (W4 pone
                // su boton; la ruta SETTINGS queda registrada abajo).
                FeedScreen(
                    container = container,
                    onAnalyzePhoto = { selectTab(Routes.EXTRACT) },
                    onOpenGarden = { selectTab(Routes.GARDEN) },
                    onShowGridFromScan = { selectTab(Routes.GRID) },
                    onOpenLayers = { navController.navigate(Routes.LAYERS) },
                )
            }
            composable(Routes.EXTRACT) {
                ExtractScreen(
                    container = container,
                    onOpenGarden = { selectTab(Routes.GARDEN) },
                    onShowGridFromScan = { selectTab(Routes.GRID) },
                    onOpenLayers = { navController.navigate(Routes.LAYERS) },
                )
            }
            composable(Routes.GRID) {
                W4GridScreen(container = container, onOpenLayers = { navController.navigate(Routes.LAYERS) })
            }
            composable(Routes.GARDEN) {
                W4GardenScreen(
                    container = container,
                    onOpenLayers = { navController.navigate(Routes.LAYERS) },
                    onOpenSettings = { navController.navigate(Routes.SETTINGS) },
                )
            }
            composable(Routes.SETTINGS) {
                W4SettingsScreen(
                    container = container,
                    onBack = { navController.popBackStack() },
                    onOpenLicenses = { navController.navigate(Routes.LICENSES) },
                    onOpenAbout = { navController.navigate(Routes.ABOUT) },
                    onOpenLayers = { navController.navigate(Routes.LAYERS) },
                )
            }
            composable(Routes.LICENSES) {
                FontLicensesScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Routes.ABOUT) {
                AboutScreen(
                    container = container,
                    onBack = { navController.popBackStack() },
                    onOpenLicenses = { navController.navigate(Routes.LICENSES) },
                )
            }
            composable(Routes.LAYERS) {
                LayersScreen(container = container, onBack = { navController.popBackStack() })
            }
        }
        // Motas de luz del marco (FIDELITY §1.3): derivan sobre el fondo;
        // no reciben toques. En iOS van por pantalla y respetan los pocillos.
        LightMotes(Modifier.fillMaxSize())
        }
    }
}
