package org.bardaibrahmglobal.app.data.auth

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import org.bardaibrahmglobal.app.data.remote.BackendError
import org.bardaibrahmglobal.app.data.remote.SupabaseHttp
import org.bardaibrahmglobal.app.data.remote.TokenResponse

private class Session(val accessToken: String, val refreshToken: String, val expiresAt: Long)

sealed interface SignUpOutcome {
    /** Confirmation link emailed; the user must open it before signing in. */
    data object ConfirmationSent : SignUpOutcome
    data object SignedIn : SignUpOutcome
}

/**
 * Holds the signed-in session. Refreshes the access token shortly before expiry and, if the
 * server still rejects it, refreshes once and retries. A failed refresh signs the user out.
 */
class AuthRepository(
    private val http: SupabaseHttp,
    private val store: RefreshTokenStore,
    private val nowSeconds: () -> Long = { System.currentTimeMillis() / 1000 },
) {
    private val mutex = Mutex()
    @Volatile private var session: Session? = null

    val isSignedIn: Boolean get() = session != null

    /** Restores a previous sign-in from the stored refresh token. */
    suspend fun restore(): Boolean = mutex.withLock {
        val token = store.load() ?: return@withLock false
        try {
            adopt(http.refresh(token))
            true
        } catch (e: BackendError.Network) {
            throw e   // keep the token; try again when online
        } catch (e: BackendError) {
            clearLocked()
            false
        }
    }

    suspend fun signUp(email: String, password: String): SignUpOutcome {
        val tokens = http.signUp(email.trim(), password, REDIRECT_URL)
        return if (tokens == null) {
            SignUpOutcome.ConfirmationSent
        } else {
            mutex.withLock { adopt(tokens) }
            SignUpOutcome.SignedIn
        }
    }

    suspend fun signIn(email: String, password: String) {
        val tokens = http.signInWithPassword(email.trim(), password)
        mutex.withLock { adopt(tokens) }
    }

    suspend fun resendConfirmation(email: String) = http.resendConfirmation(email.trim(), REDIRECT_URL)

    suspend fun signOut() {
        val current = mutex.withLock { session.also { clearLocked() } }
        if (current != null) {
            try { http.signOut(current.accessToken) } catch (e: BackendError) { /* already signed out locally */ }
        }
    }

    /**
     * Accepts the tokens from the email-confirmation link
     * (org.bardaibrahmglobal.app://auth-callback#access_token=...&refresh_token=...).
     */
    suspend fun acceptCallbackFragment(fragment: String?): Boolean {
        val values = parseFragment(fragment ?: return false)
        val access = values["access_token"] ?: return false
        val refresh = values["refresh_token"] ?: return false
        val expiresIn = values["expires_in"]?.toLongOrNull() ?: 3600
        mutex.withLock { adopt(TokenResponse(access, refresh, expiresIn)) }
        return true
    }

    /** Calls a database function as the signed-in user. */
    suspend fun rpc(function: String, params: JsonObject = JsonObject(emptyMap())): JsonElement {
        val token = validAccessToken(forceRefresh = false)
        return try {
            http.rpc(function, params, token)
        } catch (e: BackendError.Unauthorized) {
            http.rpc(function, params, validAccessToken(forceRefresh = true))
        }
    }

    private suspend fun validAccessToken(forceRefresh: Boolean): String = mutex.withLock {
        val current = session ?: throw BackendError.NotSignedIn()
        if (!forceRefresh && current.expiresAt - nowSeconds() > EXPIRY_MARGIN_SECONDS) {
            return@withLock current.accessToken
        }
        try {
            adopt(http.refresh(current.refreshToken))
        } catch (e: BackendError.Network) {
            throw e
        } catch (e: BackendError) {
            clearLocked()
            throw BackendError.NotSignedIn()
        }
        session!!.accessToken
    }

    private fun adopt(tokens: TokenResponse) {
        session = Session(tokens.accessToken, tokens.refreshToken, nowSeconds() + tokens.expiresIn)
        store.save(tokens.refreshToken)
    }

    private fun clearLocked() {
        session = null
        store.save(null)
    }

    companion object {
        const val REDIRECT_URL = "org.bardaibrahmglobal.app://auth-callback"
        private const val EXPIRY_MARGIN_SECONDS = 60L

        fun parseFragment(fragment: String): Map<String, String> =
            fragment.removePrefix("#").split('&').mapNotNull { part ->
                val i = part.indexOf('=')
                if (i <= 0) null
                else part.substring(0, i) to java.net.URLDecoder.decode(part.substring(i + 1), "UTF-8")
            }.toMap()
    }
}
