package org.bardaibrahmglobal.app.ui

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Face
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Place
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import org.bardaibrahmglobal.app.R
import org.bardaibrahmglobal.app.data.ChapterRepository
import org.bardaibrahmglobal.app.data.EventRepository
import org.bardaibrahmglobal.app.i18n.AppLanguage
import org.bardaibrahmglobal.app.ui.components.PreviewBanner
import org.bardaibrahmglobal.app.ui.screens.ChaptersScreen
import org.bardaibrahmglobal.app.ui.screens.EventsScreen
import org.bardaibrahmglobal.app.ui.screens.FamilyScreen
import org.bardaibrahmglobal.app.ui.screens.HomeScreen
import org.bardaibrahmglobal.app.ui.screens.ProfileScreen
import org.bardaibrahmglobal.app.ui.screens.SurveyScreen
import org.bardaibrahmglobal.app.ui.screens.WelcomeScreen
import org.bardaibrahmglobal.app.ui.theme.Gold
import org.bardaibrahmglobal.app.ui.theme.Navy
import org.bardaibrahmglobal.app.ui.theme.WarmWhite

enum class Destination(val route: String, @StringRes val label: Int, val icon: ImageVector) {
    HOME("home", R.string.nav_home, Icons.Filled.Home),
    FAMILY("family", R.string.nav_family, Icons.Filled.Face),
    CHAPTERS("chapters", R.string.nav_chapters, Icons.Filled.Place),
    EVENTS("events", R.string.nav_events, Icons.Filled.DateRange),
    SURVEY("survey", R.string.nav_survey, Icons.AutoMirrored.Filled.List),
    PROFILE("profile", R.string.nav_profile, Icons.Filled.AccountCircle),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BardaiApp(
    language: AppLanguage,
    onLanguageSelected: (AppLanguage) -> Unit,
    chapterRepository: ChapterRepository,
    eventRepository: EventRepository,
    versionName: String,
    backendConnected: Boolean,
    account: @Composable () -> Unit,
) {
    var welcomed by rememberSaveable { mutableStateOf(false) }
    if (!welcomed) {
        Scaffold { padding ->
            Column(Modifier.padding(padding)) {
                PreviewBanner(connected = backendConnected)
                WelcomeScreen(language, onLanguageSelected) { welcomed = true }
            }
        }
        return
    }

    val navController = rememberNavController()
    val backStack by navController.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route
    val current = Destination.entries.firstOrNull { it.route == currentRoute } ?: Destination.HOME

    fun navigate(destination: Destination) {
        navController.navigate(destination.route) {
            popUpTo(navController.graph.findStartDestination().id) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        stringResource(R.string.app_name),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Navy,
                    titleContentColor = WarmWhite,
                ),
            )
        },
        bottomBar = {
            NavigationBar(containerColor = Navy) {
                Destination.entries.forEach { destination ->
                    NavigationBarItem(
                        selected = destination == current,
                        onClick = { navigate(destination) },
                        icon = { Icon(destination.icon, contentDescription = null) },
                        label = {
                            Text(
                                stringResource(destination.label),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = Navy,
                            selectedTextColor = Gold,
                            indicatorColor = Gold,
                            unselectedIconColor = WarmWhite,
                            unselectedTextColor = WarmWhite,
                        ),
                    )
                }
            }
        },
    ) { padding ->
        Column(Modifier.padding(padding)) {
            PreviewBanner(connected = backendConnected)
            NavHost(navController = navController, startDestination = Destination.HOME.route) {
                composable(Destination.HOME.route) { HomeScreen(onOpenSurvey = { navigate(Destination.SURVEY) }) }
                composable(Destination.FAMILY.route) { FamilyScreen() }
                composable(Destination.CHAPTERS.route) { ChaptersScreen(chapterRepository) }
                composable(Destination.EVENTS.route) { EventsScreen(eventRepository) }
                composable(Destination.SURVEY.route) { SurveyScreen() }
                composable(Destination.PROFILE.route) {
                    ProfileScreen(language, onLanguageSelected, versionName, account)
                }
            }
        }
    }
}
