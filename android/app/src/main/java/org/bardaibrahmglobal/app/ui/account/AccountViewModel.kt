package org.bardaibrahmglobal.app.ui.account

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.time.Year
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.bardaibrahmglobal.app.data.auth.AuthRepository
import org.bardaibrahmglobal.app.data.auth.SignUpOutcome
import org.bardaibrahmglobal.app.data.membership.ApplicationForm
import org.bardaibrahmglobal.app.data.membership.ChapterOption
import org.bardaibrahmglobal.app.data.membership.FormRules
import org.bardaibrahmglobal.app.data.membership.MembershipRepository
import org.bardaibrahmglobal.app.data.membership.MyApplication
import org.bardaibrahmglobal.app.data.membership.MyStatus
import org.bardaibrahmglobal.app.data.membership.QueueItem
import org.bardaibrahmglobal.app.data.membership.ReviewDecision
import org.bardaibrahmglobal.app.data.membership.RoleAssignment
import org.bardaibrahmglobal.app.data.remote.BackendError

enum class Phase { NotConfigured, Loading, SignedOut, AwaitingConfirmation, SignedIn }

enum class UiError {
    Network, InvalidCredentials, EmailNotConfirmed, WeakPassword, RateLimited, NotAllowed,
    InvalidInput, AlreadyExists, WrongState, NotFound, Unknown,
    InvalidEmail, PasswordTooShort, PasswordMismatch, ReasonRequired, IncompleteForm, ConsentRequired,
}

enum class Notice { ConfirmationSent, ConfirmationResent, Submitted, Resubmitted, Withdrawn, Decided, SignedOut, EmailConfirmed }

data class AccountUiState(
    val phase: Phase = Phase.Loading,
    val busy: Boolean = false,
    val error: UiError? = null,
    val notice: Notice? = null,
    val pendingEmail: String? = null,
    val status: MyStatus? = null,
    val application: MyApplication? = null,
    val roles: List<RoleAssignment> = emptyList(),
    val chapters: List<ChapterOption> = emptyList(),
    val queue: List<QueueItem> = emptyList(),
    val invalidFields: List<String> = emptyList(),
) {
    val isSecretary: Boolean get() = roles.any { it.role == "chapter_secretary" }
    /** Applying is possible with no application, or after withdrawal. */
    val canApply: Boolean get() = status?.membershipStatus == null && (application == null || application.status == "withdrawn")
}

class AccountViewModel(
    private val configured: Boolean,
    private val auth: AuthRepository,
    private val membership: MembershipRepository,
    private val currentYear: () -> Int = { Year.now().value },
) : ViewModel() {

    private val _state = MutableStateFlow(AccountUiState(phase = if (configured) Phase.Loading else Phase.NotConfigured))
    val state: StateFlow<AccountUiState> = _state.asStateFlow()

    init {
        if (configured) launchAction(showBusy = false) {
            if (auth.restore()) loadSignedIn() else _state.update { it.copy(phase = Phase.SignedOut) }
        }
    }

    fun clearMessages() = _state.update { it.copy(error = null, notice = null, invalidFields = emptyList()) }

    fun signIn(email: String, password: String) {
        if (!FormRules.isEmail(email)) return fail(UiError.InvalidEmail)
        launchAction {
            auth.signIn(email, password)
            loadSignedIn()
        }
    }

    fun signUp(email: String, password: String, repeat: String) {
        when {
            !FormRules.isEmail(email) -> return fail(UiError.InvalidEmail)
            !FormRules.isStrongEnough(password) -> return fail(UiError.PasswordTooShort)
            password != repeat -> return fail(UiError.PasswordMismatch)
        }
        launchAction {
            when (auth.signUp(email, password)) {
                SignUpOutcome.ConfirmationSent -> _state.update {
                    it.copy(phase = Phase.AwaitingConfirmation, pendingEmail = email.trim(), notice = Notice.ConfirmationSent)
                }
                SignUpOutcome.SignedIn -> loadSignedIn()
            }
        }
    }

    fun resendConfirmation() {
        val email = _state.value.pendingEmail ?: return
        launchAction {
            auth.resendConfirmation(email)
            _state.update { it.copy(notice = Notice.ConfirmationResent) }
        }
    }

    fun backToSignIn() = _state.update { it.copy(phase = Phase.SignedOut, error = null, notice = null) }

    /** Called with the fragment of org.bardaibrahmglobal.app://auth-callback#... from the email link. */
    fun handleAuthCallback(fragment: String?) {
        if (!configured || fragment.isNullOrBlank()) return
        if (fragment.contains("error")) return fail(UiError.Unknown)
        launchAction {
            if (auth.acceptCallbackFragment(fragment)) {
                loadSignedIn()
                _state.update { it.copy(notice = Notice.EmailConfirmed) }
            }
        }
    }

    fun refresh() = launchAction { loadSignedIn() }

    fun signOut() = launchAction {
        auth.signOut()
        _state.value = AccountUiState(phase = Phase.SignedOut, notice = Notice.SignedOut)
    }

    fun submit(form: ApplicationForm, consent: Boolean) {
        if (!consent) return fail(UiError.ConsentRequired)
        val problems = FormRules.problems(form, currentYear())
        if (problems.isNotEmpty()) {
            _state.update { it.copy(error = UiError.IncompleteForm, invalidFields = problems) }
            return
        }
        launchAction {
            membership.submit(form)
            loadSignedIn()
            _state.update { it.copy(notice = Notice.Submitted) }
        }
    }

    fun resubmit(form: ApplicationForm) {
        val app = _state.value.application ?: return
        val problems = FormRules.problems(form.copy(chapterId = app.chapterId), currentYear())
        if (problems.isNotEmpty()) {
            _state.update { it.copy(error = UiError.IncompleteForm, invalidFields = problems) }
            return
        }
        launchAction {
            membership.resubmit(app.id, form)
            loadSignedIn()
            _state.update { it.copy(notice = Notice.Resubmitted) }
        }
    }

    fun withdraw() {
        val app = _state.value.application ?: return
        launchAction {
            membership.withdraw(app.id)
            loadSignedIn()
            _state.update { it.copy(notice = Notice.Withdrawn) }
        }
    }

    fun review(applicationId: String, decision: ReviewDecision, note: String) {
        if (decision != ReviewDecision.APPROVE && note.isBlank()) return fail(UiError.ReasonRequired)
        launchAction {
            membership.review(applicationId, decision, note)
            loadSignedIn()
            _state.update { it.copy(notice = Notice.Decided) }
        }
    }

    private suspend fun loadSignedIn() {
        val status = membership.myStatus()
        val application = membership.myApplication()
        val roles = membership.myRoles()
        val needChapters = status.membershipStatus == null &&
            (application == null || application.status in setOf("withdrawn", "correction_requested"))
        val chapters = if (needChapters) membership.chapters() else emptyList()
        val queue = if (roles.any { it.role == "chapter_secretary" }) membership.reviewQueue() else emptyList()
        _state.update {
            it.copy(phase = Phase.SignedIn, status = status, application = application, roles = roles,
                chapters = chapters, queue = queue, pendingEmail = null)
        }
    }

    private fun fail(error: UiError) = _state.update { it.copy(error = error, notice = null) }

    private fun launchAction(showBusy: Boolean = true, block: suspend () -> Unit) {
        viewModelScope.launch {
            _state.update { it.copy(busy = showBusy, error = null, notice = null, invalidFields = emptyList()) }
            try {
                block()
            } catch (e: BackendError.NotSignedIn) {
                _state.value = AccountUiState(phase = Phase.SignedOut)
            } catch (e: BackendError.NotConfigured) {
                _state.value = AccountUiState(phase = Phase.NotConfigured)
            } catch (e: BackendError) {
                val error = toUiError(e)
                _state.update {
                    val phase = if (it.phase == Phase.Loading) Phase.SignedOut else it.phase
                    it.copy(error = error, phase = phase)
                }
            } finally {
                _state.update { it.copy(busy = false) }
            }
        }
    }

    companion object {
        fun toUiError(e: BackendError): UiError = when (e) {
            is BackendError.Network -> UiError.Network
            is BackendError.InvalidCredentials -> UiError.InvalidCredentials
            is BackendError.EmailNotConfirmed -> UiError.EmailNotConfirmed
            is BackendError.WeakPassword -> UiError.WeakPassword
            is BackendError.RateLimited, is BackendError.LimitReached -> UiError.RateLimited
            is BackendError.NotAllowed -> UiError.NotAllowed
            is BackendError.InvalidInput -> UiError.InvalidInput
            is BackendError.AlreadyExists -> UiError.AlreadyExists
            is BackendError.WrongState -> UiError.WrongState
            is BackendError.NotFound -> UiError.NotFound
            else -> UiError.Unknown
        }
    }
}
