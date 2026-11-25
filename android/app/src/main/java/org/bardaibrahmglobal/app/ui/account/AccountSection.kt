package org.bardaibrahmglobal.app.ui.account

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import org.bardaibrahmglobal.app.R
import org.bardaibrahmglobal.app.data.membership.ApplicationForm
import org.bardaibrahmglobal.app.data.membership.ChapterOption
import org.bardaibrahmglobal.app.data.membership.MyApplication
import org.bardaibrahmglobal.app.data.membership.QueueItem
import org.bardaibrahmglobal.app.data.membership.ReviewDecision
import org.bardaibrahmglobal.app.ui.theme.BanyanGreen
import org.bardaibrahmglobal.app.ui.theme.Navy

/** Actions the account UI can trigger; implemented by [AccountViewModel]. */
interface AccountActions {
    fun signIn(email: String, password: String)
    fun signUp(email: String, password: String, repeat: String)
    fun resendConfirmation()
    fun backToSignIn()
    fun signOut()
    fun refresh()
    fun submit(form: ApplicationForm, consent: Boolean)
    fun resubmit(form: ApplicationForm)
    fun withdraw()
    fun review(applicationId: String, decision: ReviewDecision, note: String)
    fun clearMessages()
}

fun AccountViewModel.asActions(): AccountActions = object : AccountActions {
    override fun signIn(email: String, password: String) = this@asActions.signIn(email, password)
    override fun signUp(email: String, password: String, repeat: String) = this@asActions.signUp(email, password, repeat)
    override fun resendConfirmation() = this@asActions.resendConfirmation()
    override fun backToSignIn() = this@asActions.backToSignIn()
    override fun signOut() = this@asActions.signOut()
    override fun refresh() = this@asActions.refresh()
    override fun submit(form: ApplicationForm, consent: Boolean) = this@asActions.submit(form, consent)
    override fun resubmit(form: ApplicationForm) = this@asActions.resubmit(form)
    override fun withdraw() = this@asActions.withdraw()
    override fun review(applicationId: String, decision: ReviewDecision, note: String) =
        this@asActions.review(applicationId, decision, note)
    override fun clearMessages() = this@asActions.clearMessages()
}

@Composable
private fun isGujarati(): Boolean =
    LocalConfiguration.current.locales.get(0)?.language == "gu"

@Composable
fun AccountSection(state: AccountUiState, actions: AccountActions) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(stringResource(R.string.account_title), style = MaterialTheme.typography.titleLarge, color = Navy)
            if (state.busy || state.phase == Phase.Loading) LinearProgressIndicator(Modifier.fillMaxWidth())
            Messages(state)
            when (state.phase) {
                Phase.NotConfigured -> Text(stringResource(R.string.account_not_configured))
                Phase.Loading -> Unit
                Phase.SignedOut -> SignInForm(state, actions)
                Phase.AwaitingConfirmation -> AwaitingConfirmation(state, actions)
                Phase.SignedIn -> SignedIn(state, actions)
            }
        }
    }
}

@Composable
private fun Messages(state: AccountUiState) {
    state.notice?.let { Text(stringResource(noticeText(it)), color = BanyanGreen, style = MaterialTheme.typography.bodyMedium) }
    state.error?.let { Text(stringResource(errorText(it)), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium) }
}

@Composable
private fun SignInForm(state: AccountUiState, actions: AccountActions) {
    var creating by rememberSaveable { mutableStateOf(false) }
    var email by rememberSaveable { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var repeat by remember { mutableStateOf("") }

    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        FilterChip(selected = !creating, onClick = { creating = false; actions.clearMessages() },
            label = { Text(stringResource(R.string.account_sign_in)) })
        FilterChip(selected = creating, onClick = { creating = true; actions.clearMessages() },
            label = { Text(stringResource(R.string.account_create)) })
    }
    OutlinedTextField(
        value = email, onValueChange = { email = it }, singleLine = true,
        label = { Text(stringResource(R.string.account_email)) },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
        modifier = Modifier.fillMaxWidth(),
    )
    OutlinedTextField(
        value = password, onValueChange = { password = it }, singleLine = true,
        label = { Text(stringResource(R.string.account_password)) },
        supportingText = { if (creating) Text(stringResource(R.string.account_password_hint)) },
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        modifier = Modifier.fillMaxWidth(),
    )
    if (creating) {
        OutlinedTextField(
            value = repeat, onValueChange = { repeat = it }, singleLine = true,
            label = { Text(stringResource(R.string.account_password_repeat)) },
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            modifier = Modifier.fillMaxWidth(),
        )
    }
    Button(
        enabled = !state.busy,
        onClick = { if (creating) actions.signUp(email, password, repeat) else actions.signIn(email, password) },
        modifier = Modifier.fillMaxWidth(),
    ) { Text(stringResource(if (creating) R.string.account_create else R.string.account_sign_in)) }
}

@Composable
private fun AwaitingConfirmation(state: AccountUiState, actions: AccountActions) {
    Text(stringResource(R.string.account_check_email_title), style = MaterialTheme.typography.titleMedium, color = Navy)
    Text(stringResource(R.string.account_check_email_body, state.pendingEmail.orEmpty()))
    Button(onClick = actions::backToSignIn, enabled = !state.busy, modifier = Modifier.fillMaxWidth()) {
        Text(stringResource(R.string.account_back_to_sign_in))
    }
    TextButton(onClick = actions::resendConfirmation, enabled = !state.busy) { Text(stringResource(R.string.account_resend)) }
}

@Composable
private fun SignedIn(state: AccountUiState, actions: AccountActions) {
    val gu = isGujarati()
    val status = state.status
    val app = state.application

    when {
        status?.membershipStatus == "approved" -> {
            Text(stringResource(R.string.account_status_approved), color = BanyanGreen, style = MaterialTheme.typography.titleMedium)
            status?.memberCode?.let { Text(stringResource(R.string.account_member_code, it)) }
        }
        status?.membershipStatus == "suspended" -> Text(stringResource(R.string.account_status_suspended))
        app != null && app.status == "pending" -> {
            Text(stringResource(R.string.account_status_pending, if (gu) app.chapterNameGu else app.chapterNameEn))
            OutlinedButton(onClick = actions::withdraw, enabled = !state.busy) { Text(stringResource(R.string.account_withdraw)) }
        }
        app != null && app.status == "correction_requested" -> {
            Text(stringResource(R.string.account_status_correction), style = MaterialTheme.typography.titleMedium)
            Text(app.reviewerNote.orEmpty(), color = Navy)
            ApplicationFormFields(
                title = R.string.account_resubmit_title, button = R.string.account_resubmit,
                chapters = emptyList(), initial = app, askConsent = false, state = state,
                onSend = { form, _ -> actions.resubmit(form) },
            )
            OutlinedButton(onClick = actions::withdraw, enabled = !state.busy) { Text(stringResource(R.string.account_withdraw)) }
        }
        app != null && app.status == "rejected" -> {
            Text(stringResource(R.string.account_status_rejected))
            Text(app.reviewerNote.orEmpty(), color = Navy)
        }
        state.canApply -> {
            Text(stringResource(R.string.account_status_none))
            ApplicationFormFields(
                title = R.string.account_apply_title, button = R.string.account_submit,
                chapters = state.chapters, initial = null, askConsent = true, state = state,
                onSend = actions::submit,
            )
        }
    }

    state.roles.filter { it.role == "chapter_secretary" }.forEach {
        Text(stringResource(R.string.account_role_secretary, (if (gu) it.chapterNameGu else it.chapterNameEn).orEmpty()),
            style = MaterialTheme.typography.labelLarge, color = Navy)
    }
    if (state.isSecretary) ReviewQueue(state, actions)

    HorizontalDivider()
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(onClick = actions::refresh, enabled = !state.busy) { Text(stringResource(R.string.account_refresh)) }
        TextButton(onClick = actions::signOut, enabled = !state.busy) { Text(stringResource(R.string.account_sign_out)) }
    }
}

@Composable
private fun ApplicationFormFields(
    title: Int,
    button: Int,
    chapters: List<ChapterOption>,
    initial: MyApplication?,
    askConsent: Boolean,
    state: AccountUiState,
    onSend: (ApplicationForm, Boolean) -> Unit,
) {
    val gu = isGujarati()
    var chapterId by rememberSaveable { mutableStateOf(initial?.chapterId) }
    var given by rememberSaveable { mutableStateOf(initial?.givenName.orEmpty()) }
    var surname by rememberSaveable { mutableStateOf(initial?.surname.orEmpty()) }
    var year by rememberSaveable { mutableStateOf(initial?.birthYear?.toString().orEmpty()) }
    var village by rememberSaveable { mutableStateOf(initial?.ancestralVillage.orEmpty()) }
    var city by rememberSaveable { mutableStateOf(initial?.presentCity.orEmpty()) }
    var country by rememberSaveable { mutableStateOf(initial?.presentCountry.orEmpty()) }
    var consent by rememberSaveable { mutableStateOf(false) }
    val bad = state.invalidFields

    Spacer(Modifier.height(4.dp))
    Text(stringResource(title), style = MaterialTheme.typography.titleMedium, color = Navy)
    if (chapters.isNotEmpty()) {
        Text(stringResource(R.string.account_chapter), style = MaterialTheme.typography.labelLarge,
            color = if ("chapter" in bad) MaterialTheme.colorScheme.error else Navy)
        chapters.forEach { c ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .selectable(selected = chapterId == c.id, onClick = { chapterId = c.id }, role = Role.RadioButton),
            ) {
                RadioButton(selected = chapterId == c.id, onClick = null)
                Text(
                    (if (gu) c.nameGu else c.nameEn) +
                        if (!c.hasSecretary) " " + stringResource(R.string.account_chapter_no_secretary) else "",
                    modifier = Modifier.padding(start = 8.dp),
                )
            }
        }
    }
    FormField(given, { given = it }, R.string.account_given_name, "givenName" in bad)
    FormField(surname, { surname = it }, R.string.account_surname, "surname" in bad)
    FormField(year, { year = it.filter(Char::isDigit).take(4) }, R.string.account_birth_year, "birthYear" in bad, KeyboardType.Number)
    FormField(village, { village = it }, R.string.account_village, "ancestralVillage" in bad)
    FormField(city, { city = it }, R.string.account_city, "presentCity" in bad)
    FormField(country, { country = it.filter(Char::isLetter).take(2).uppercase() }, R.string.account_country, "presentCountry" in bad)
    if (askConsent) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(checked = consent, onCheckedChange = { consent = it })
            Text(stringResource(R.string.account_consent), style = MaterialTheme.typography.bodyMedium)
        }
    }
    Button(
        enabled = !state.busy,
        onClick = { onSend(ApplicationForm(chapterId ?: initial?.chapterId, given, surname, year, village, city, country), consent) },
        modifier = Modifier.fillMaxWidth(),
    ) { Text(stringResource(button)) }
}

@Composable
private fun FormField(value: String, onChange: (String) -> Unit, label: Int, isError: Boolean, type: KeyboardType = KeyboardType.Text) {
    OutlinedTextField(
        value = value, onValueChange = onChange, singleLine = true, isError = isError,
        label = { Text(stringResource(label)) },
        keyboardOptions = KeyboardOptions(keyboardType = type),
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun ReviewQueue(state: AccountUiState, actions: AccountActions) {
    HorizontalDivider()
    Text(stringResource(R.string.account_review_title), style = MaterialTheme.typography.titleMedium, color = Navy)
    if (state.queue.isEmpty()) {
        Text(stringResource(R.string.account_review_empty))
        return
    }
    state.queue.forEach { item -> ReviewCard(item, state.busy, actions) }
}

@Composable
private fun ReviewCard(item: QueueItem, busy: Boolean, actions: AccountActions) {
    var note by rememberSaveable(item.applicationId) { mutableStateOf("") }
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("${item.givenName} ${item.surname}", style = MaterialTheme.typography.titleMedium, color = Navy)
            Text(listOfNotNull(item.birthYear?.toString(), item.ancestralVillage, item.presentCity, item.presentCountry)
                .joinToString(" · "))
            Text(item.chapterNameEn, style = MaterialTheme.typography.labelMedium)
            if (item.possibleDuplicates > 0) {
                Text(stringResource(R.string.account_review_duplicates, item.possibleDuplicates), color = MaterialTheme.colorScheme.error)
            }
            OutlinedTextField(
                value = note, onValueChange = { note = it.take(1000) },
                label = { Text(stringResource(R.string.account_review_note)) }, modifier = Modifier.fillMaxWidth(),
            )
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Button(enabled = !busy, onClick = { actions.review(item.applicationId, ReviewDecision.APPROVE, note) }) {
                    Text(stringResource(R.string.account_approve))
                }
                OutlinedButton(enabled = !busy, onClick = { actions.review(item.applicationId, ReviewDecision.CORRECTION, note) }) {
                    Text(stringResource(R.string.account_request_correction))
                }
            }
            TextButton(enabled = !busy, onClick = { actions.review(item.applicationId, ReviewDecision.REJECT, note) }) {
                Text(stringResource(R.string.account_reject), color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

private fun noticeText(n: Notice): Int = when (n) {
    Notice.ConfirmationSent -> R.string.notice_confirmation_sent
    Notice.ConfirmationResent -> R.string.notice_confirmation_resent
    Notice.Submitted -> R.string.notice_submitted
    Notice.Resubmitted -> R.string.notice_resubmitted
    Notice.Withdrawn -> R.string.notice_withdrawn
    Notice.Decided -> R.string.notice_decided
    Notice.SignedOut -> R.string.notice_signed_out
    Notice.EmailConfirmed -> R.string.notice_email_confirmed
}

private fun errorText(e: UiError): Int = when (e) {
    UiError.Network -> R.string.error_network
    UiError.InvalidCredentials -> R.string.error_invalid_credentials
    UiError.EmailNotConfirmed -> R.string.error_email_not_confirmed
    UiError.WeakPassword -> R.string.error_weak_password
    UiError.RateLimited -> R.string.error_rate_limited
    UiError.NotAllowed -> R.string.error_not_allowed
    UiError.InvalidInput -> R.string.error_invalid_input
    UiError.AlreadyExists -> R.string.error_already_exists
    UiError.WrongState -> R.string.error_wrong_state
    UiError.NotFound -> R.string.error_not_found
    UiError.Unknown -> R.string.error_unknown
    UiError.InvalidEmail -> R.string.error_invalid_email
    UiError.PasswordTooShort -> R.string.error_password_short
    UiError.PasswordMismatch -> R.string.error_password_mismatch
    UiError.ReasonRequired -> R.string.error_reason_required
    UiError.IncompleteForm -> R.string.error_incomplete_form
    UiError.ConsentRequired -> R.string.error_consent_required
}
