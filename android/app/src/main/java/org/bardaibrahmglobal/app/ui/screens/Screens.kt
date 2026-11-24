package org.bardaibrahmglobal.app.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import org.bardaibrahmglobal.app.R
import org.bardaibrahmglobal.app.data.Chapter
import org.bardaibrahmglobal.app.data.ChapterRepository
import org.bardaibrahmglobal.app.data.CommunityEvent
import org.bardaibrahmglobal.app.data.EventRepository
import org.bardaibrahmglobal.app.data.UiState
import org.bardaibrahmglobal.app.data.loadState
import org.bardaibrahmglobal.app.i18n.AppLanguage
import org.bardaibrahmglobal.app.ui.components.Emblem
import org.bardaibrahmglobal.app.ui.components.LanguageSelector
import org.bardaibrahmglobal.app.ui.components.PreviewTag
import org.bardaibrahmglobal.app.ui.components.ScreenTitle
import org.bardaibrahmglobal.app.ui.components.SectionCard
import org.bardaibrahmglobal.app.ui.components.StateContent
import org.bardaibrahmglobal.app.ui.theme.Gold
import org.bardaibrahmglobal.app.ui.theme.Navy

@Composable
private fun ScreenColumn(content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        content = content,
    )
}

// ---------------------------------------------------------------- Welcome

@Composable
fun WelcomeScreen(
    language: AppLanguage,
    onLanguageSelected: (AppLanguage) -> Unit,
    onContinue: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Spacer(Modifier.height(8.dp))
        Emblem(size = 220.dp)
        Text(
            text = stringResource(R.string.foundation_name),
            style = MaterialTheme.typography.headlineMedium,
            color = Navy,
            textAlign = TextAlign.Center,
        )
        Text(
            text = stringResource(R.string.foundation_name_alt),
            style = MaterialTheme.typography.titleMedium,
            color = Navy.copy(alpha = 0.8f),
            textAlign = TextAlign.Center,
        )
        Text(stringResource(R.string.welcome_body), textAlign = TextAlign.Center)
        Text(
            stringResource(R.string.welcome_status),
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(stringResource(R.string.choose_language), style = MaterialTheme.typography.titleMedium)
        LanguageSelector(selected = language, onSelect = onLanguageSelected)
        Button(
            onClick = onContinue,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 52.dp),
        ) { Text(stringResource(R.string.welcome_continue)) }
    }
}

// ---------------------------------------------------------------- Home

@Composable
fun HomeScreen(onOpenSurvey: () -> Unit) = ScreenColumn {
    ScreenTitle(stringResource(R.string.home_greeting))
    Text(stringResource(R.string.home_intro))
    listOf(
        R.string.home_module_membership to R.string.home_module_membership_desc,
        R.string.home_module_family to R.string.home_module_family_desc,
        R.string.home_module_directory to R.string.home_module_directory_desc,
        R.string.home_module_survey to R.string.home_module_survey_desc,
        R.string.home_module_events to R.string.home_module_events_desc,
    ).forEach { (title, body) ->
        SectionCard(stringResource(title), stringResource(body), trailing = { PreviewTag() })
    }
    // Deliberately no numbers: registration has not opened, so any total would be invented.
    SectionCard(stringResource(R.string.home_stats_title), stringResource(R.string.home_stats_none))
    OutlinedButton(onClick = onOpenSurvey, modifier = Modifier.fillMaxWidth()) {
        Text(stringResource(R.string.open_survey_preview))
    }
}

// ---------------------------------------------------------------- Family

@Composable
private fun PersonBox(label: String, modifier: Modifier = Modifier, highlight: Boolean = false) {
    OutlinedCard(
        modifier = modifier,
        shape = RoundedCornerShape(12.dp),
        border = BorderStroke(if (highlight) 2.dp else 1.dp, if (highlight) Gold else Navy.copy(alpha = 0.4f)),
    ) {
        Column(Modifier.padding(10.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(label, style = MaterialTheme.typography.labelLarge, color = Navy, textAlign = TextAlign.Center)
            Text(
                if (highlight) "" else stringResource(R.string.family_not_added),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ParentBranch(
    sideLabel: String,
    grandfather: String,
    grandmother: String,
    parent: String,
    modifier: Modifier = Modifier,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(sideLabel, style = MaterialTheme.typography.titleMedium, color = Navy)
        PersonBox(grandfather, Modifier.fillMaxWidth())
        PersonBox(grandmother, Modifier.fillMaxWidth())
        PersonBox(parent, Modifier.fillMaxWidth())
    }
}

@Composable
fun FamilyScreen() = ScreenColumn {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) { ScreenTitle(stringResource(R.string.family_title)) }
        PreviewTag()
    }
    Text(stringResource(R.string.family_intro))
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        ParentBranch(
            sideLabel = stringResource(R.string.family_paternal_side),
            grandfather = stringResource(R.string.family_paternal_grandfather),
            grandmother = stringResource(R.string.family_paternal_grandmother),
            parent = stringResource(R.string.family_father),
            modifier = Modifier.weight(1f),
        )
        ParentBranch(
            sideLabel = stringResource(R.string.family_maternal_side),
            grandfather = stringResource(R.string.family_maternal_grandfather),
            grandmother = stringResource(R.string.family_maternal_grandmother),
            parent = stringResource(R.string.family_mother),
            modifier = Modifier.weight(1f),
        )
    }
    PersonBox(stringResource(R.string.family_you), Modifier.fillMaxWidth(), highlight = true)
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        PersonBox(stringResource(R.string.family_spouse), Modifier.weight(1f))
        PersonBox(stringResource(R.string.family_siblings), Modifier.weight(1f))
    }
    PersonBox(stringResource(R.string.family_children), Modifier.fillMaxWidth())
    HorizontalDivider()
    Text(
        stringResource(R.string.family_privacy_note),
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

// ---------------------------------------------------------------- Chapters

@Composable
fun ChaptersScreen(repository: ChapterRepository) = ScreenColumn {
    ScreenTitle(stringResource(R.string.chapters_title))
    Text(stringResource(R.string.chapters_intro))
    listOf(
        R.string.chapter_level_global,
        R.string.chapter_level_country,
        R.string.chapter_level_state,
        R.string.chapter_level_district,
        R.string.chapter_level_city,
    ).forEachIndexed { index, level ->
        Row(verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.width((index * 16).dp))
            Text("•  " + stringResource(level), style = MaterialTheme.typography.bodyLarge, color = Navy)
        }
    }
    HorizontalDivider()
    val state = rememberLoadedState(repository::chapters)
    StateContent(state.value, stringResource(R.string.chapters_empty), onRetry = state.retry) { items: List<Chapter> ->
        items.forEach { SectionCard(it.name, it.level.name) }
    }
}

// ---------------------------------------------------------------- Events

@Composable
fun EventsScreen(repository: EventRepository) = ScreenColumn {
    ScreenTitle(stringResource(R.string.events_title))
    val state = rememberLoadedState(repository::upcomingEvents)
    StateContent(state.value, stringResource(R.string.events_empty), onRetry = state.retry) { items: List<CommunityEvent> ->
        items.forEach { SectionCard(it.title, it.chapterName) }
    }
    SectionCard(stringResource(R.string.events_title), stringResource(R.string.events_planned), trailing = { PreviewTag() })
}

// ---------------------------------------------------------------- Survey

@Composable
fun SurveyScreen() = ScreenColumn {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) { ScreenTitle(stringResource(R.string.survey_title)) }
        PreviewTag()
    }
    Text(stringResource(R.string.survey_intro))
    SectionCard(stringResource(R.string.survey_individual), stringResource(R.string.survey_individual_desc))
    SectionCard(stringResource(R.string.survey_household), stringResource(R.string.survey_household_desc))
    Text(stringResource(R.string.survey_never_asked), style = MaterialTheme.typography.bodyMedium, color = Navy)
    // Disabled on purpose: no survey data may be collected until M2 security exists.
    Button(onClick = {}, enabled = false, modifier = Modifier.fillMaxWidth()) {
        Text(stringResource(R.string.survey_start_disabled), textAlign = TextAlign.Center)
    }
}

// ---------------------------------------------------------------- Profile

@Composable
fun ProfileScreen(
    language: AppLanguage,
    onLanguageSelected: (AppLanguage) -> Unit,
    versionName: String,
) = ScreenColumn {
    ScreenTitle(stringResource(R.string.profile_title))
    Text(stringResource(R.string.profile_not_signed_in), color = MaterialTheme.colorScheme.onSurfaceVariant)
    Text(stringResource(R.string.profile_language), style = MaterialTheme.typography.titleMedium, color = Navy)
    LanguageSelector(selected = language, onSelect = onLanguageSelected)
    HorizontalDivider()
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Emblem(size = 160.dp)
    }
    SectionCard(stringResource(R.string.profile_about), stringResource(R.string.profile_about_body))
    SectionCard(stringResource(R.string.profile_privacy), stringResource(R.string.profile_privacy_body))
    Text(
        stringResource(R.string.profile_version, versionName),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

// ---------------------------------------------------------------- helpers

class LoadedState<T>(val value: UiState<T>, val retry: () -> Unit)

@Composable
private fun <T> rememberLoadedState(load: suspend () -> List<T>): LoadedState<T> {
    var attempt by remember { mutableIntStateOf(0) }
    var state by remember { mutableStateOf<UiState<T>>(UiState.Loading) }
    LaunchedEffect(attempt) {
        state = UiState.Loading
        state = loadState(load)
    }
    return LoadedState(state) { attempt++ }
}
