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
import com.andreseloy.colorsapp.design.SolarIconDrop
import com.andreseloy.colorsapp.design.SolarIconGrid
import com.andreseloy.colorsapp.design.SolarIconLeaf
import com.andreseloy.colorsapp.design.SolarIconSun
import com.andreseloy.colorsapp.design.SolarTabBar
import com.andreseloy.colorsapp.design.SolarTabItem
import com.andreseloy.colorsapp.design.SolarTheme
import com.andreseloy.colorsapp.feature.ExtractScreen
import com.andreseloy.colorsapp.feature.FeedScreen
import com.andreseloy.colorsapp.feature.GardenScreen
import com.andreseloy.colorsapp.feature.GridScreen
import com.andreseloy.colorsapp.feature.SettingsScreen
import com.andreseloy.colorsapp.scan.ScanProgress

/** Rutas de la app (AppTab de iOS + secundarias). */
object Routes {
    const val FEED = "feed"
    const val EXTRACT = "extract"
    const val GRID = "grid"
    const val GARDEN = "garden"
    const val SETTINGS = "settings"
    const val LICENSES = "licenses"
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
                                SolarTabItem(Routes.FEED, stringResource(R.string.tab_feed), SolarIconSun),
                                SolarTabItem(
                                    Routes.EXTRACT, stringResource(R.string.tab_extract), SolarIconDrop,
                                    badge = scanBadge,
                                ),
                                SolarTabItem(Routes.GRID, stringResource(R.string.tab_grid), SolarIconGrid),
                                SolarTabItem(Routes.GARDEN, stringResource(R.string.tab_garden), SolarIconLeaf),
                            ),
                            selectedRoute = currentRoute ?: Routes.FEED,
                            onSelect = { selectTab(it.route) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = Routes.FEED,
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(colors.surface),
        ) {
            composable(Routes.FEED) {
                FeedScreen(
                    container = container,
                    onAnalyzePhoto = { selectTab(Routes.EXTRACT) },
                    onOpenSettings = { navController.navigate(Routes.SETTINGS) },
                )
            }
            composable(Routes.EXTRACT) {
                ExtractScreen(container = container)
            }
            composable(Routes.GRID) {
                GridScreen(container = container)
            }
            composable(Routes.GARDEN) {
                GardenScreen(container = container)
            }
            composable(Routes.SETTINGS) {
                SettingsScreen(
                    container = container,
                    onBack = { navController.popBackStack() },
                    onOpenLicenses = { navController.navigate(Routes.LICENSES) },
                )
            }
            composable(Routes.LICENSES) {
                com.andreseloy.colorsapp.feature.LicensesScreen(
                    onBack = { navController.popBackStack() },
                )
            }
        }
    }
}
