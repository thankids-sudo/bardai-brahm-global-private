package org.bardaibrahmglobal.app.ui.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.booleanResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import org.bardaibrahmglobal.app.R
import org.bardaibrahmglobal.app.data.UiState
import org.bardaibrahmglobal.app.i18n.AppLanguage
import org.bardaibrahmglobal.app.ui.theme.Gold
import org.bardaibrahmglobal.app.ui.theme.GoldSoft
import org.bardaibrahmglobal.app.ui.theme.Navy

/** Persistent strip that makes the preview status obvious on every screen. */
@Composable
fun PreviewBanner(modifier: Modifier = Modifier, connected: Boolean = false) {
    Text(
        text = stringResource(if (connected) R.string.preview_banner_connected else R.string.preview_banner),
        style = MaterialTheme.typography.labelMedium,
        color = Navy,
        textAlign = TextAlign.Center,
        modifier = modifier
            .fillMaxWidth()
            .background(GoldSoft)
            .padding(horizontal = 12.dp, vertical = 6.dp),
    )
}

/**
 * Full emblem, scaled with ContentScale.Fit so it is never cropped.
 * While the supplied logo is not yet installed, a placeholder frame with a caption is shown.
 */
@Composable
fun Emblem(size: Dp, modifier: Modifier = Modifier) {
    val placeholder = booleanResource(R.bool.emblem_is_placeholder)
    Box(modifier = modifier.size(size), contentAlignment = Alignment.Center) {
        Image(
            painter = painterResource(R.drawable.emblem),
            contentDescription = stringResource(R.string.emblem_description),
            contentScale = ContentScale.Fit,
            modifier = Modifier.size(size),
        )
        if (placeholder) {
            Text(
                text = stringResource(R.string.emblem_pending),
                style = MaterialTheme.typography.labelMedium,
                color = Navy,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = size / 5),
            )
        }
    }
}

@Composable
fun SectionCard(
    title: String,
    body: String,
    modifier: Modifier = Modifier,
    trailing: (@Composable () -> Unit)? = null,
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium,
                    color = Navy,
                    modifier = Modifier
                        .weight(1f)
                        .semantics { heading() },
                )
                trailing?.invoke()
            }
            Spacer(Modifier.height(4.dp))
            Text(text = body, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
fun PreviewTag() {
    Text(
        text = stringResource(R.string.preview_tag),
        style = MaterialTheme.typography.labelMedium,
        color = Navy,
        modifier = Modifier
            .background(Gold.copy(alpha = 0.35f), RoundedCornerShape(8.dp))
            .padding(horizontal = 8.dp, vertical = 2.dp),
    )
}

@Composable
fun ScreenTitle(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.headlineMedium,
        color = Navy,
        modifier = Modifier.semantics { heading() },
    )
}

@Composable
fun EmptyState(message: String, modifier: Modifier = Modifier) {
    Text(
        text = message,
        style = MaterialTheme.typography.bodyLarge,
        textAlign = TextAlign.Center,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 24.dp),
    )
}

/** Renders loading / empty / error / content for a [UiState]. */
@Composable
fun <T> StateContent(
    state: UiState<T>,
    emptyMessage: String,
    onRetry: () -> Unit,
    content: @Composable (List<T>) -> Unit,
) {
    when (state) {
        UiState.Loading -> Column(
            Modifier
                .fillMaxWidth()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            CircularProgressIndicator(color = Navy)
            Spacer(Modifier.height(8.dp))
            Text(stringResource(R.string.state_loading))
        }
        UiState.Empty -> EmptyState(emptyMessage)
        is UiState.Error -> Column(
            Modifier
                .fillMaxWidth()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(stringResource(R.string.state_error), style = MaterialTheme.typography.bodyLarge)
            Spacer(Modifier.height(8.dp))
            Button(onClick = onRetry) { Text(stringResource(R.string.state_retry)) }
        }
        is UiState.Content -> content(state.items)
    }
}

@Composable
fun LanguageSelector(
    selected: AppLanguage,
    onSelect: (AppLanguage) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        FilterChip(
            selected = selected == AppLanguage.GUJARATI,
            onClick = { onSelect(AppLanguage.GUJARATI) },
            label = { Text(stringResource(R.string.language_gujarati)) },
        )
        FilterChip(
            selected = selected == AppLanguage.ENGLISH,
            onClick = { onSelect(AppLanguage.ENGLISH) },
            label = { Text(stringResource(R.string.language_english)) },
        )
    }
}
